#!/usr/bin/env python3
"""Minimal mock of the Immich API for exercising the ImmichCull iOS app.

Serves on 127.0.0.1:2283. API key: "test-key".
Logs every mutating call to mock_immich.log (JSON lines) for post-run assertions.
"""
import json
import struct
import sys
import uuid
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

API_KEY = "test-key"
LOG_PATH = Path(__file__).parent / "mock_immich.log"

def make_id(n):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"immich-mock-{n}"))

COLORS = [
    (220, 60, 60), (60, 160, 220), (80, 190, 100), (230, 180, 60),
    (170, 90, 210), (240, 130, 50), (70, 200, 190), (150, 150, 150),
]

def png(color, width=400, height=500):
    def chunk(tag, data):
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload))
    raw = b"".join(b"\x00" + bytes(color) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))

# 8 assets total; first 5 belong to "Test Album".
ASSETS = []
for i in range(8):
    ASSETS.append({
        "id": make_id(f"asset-{i}"),
        "type": "IMAGE",
        "originalFileName": f"IMG_{1000 + i}.jpg",
        "localDateTime": f"2026-06-{10 + i:02d}T12:00:00.000Z",
        "isFavorite": False,
        "originalMimeType": "image/jpeg",
        "exifInfo": {"make": "Apple", "model": "iPhone 14 Pro"},
        "trashed": False,
        "color": COLORS[i % len(COLORS)],
    })
# Asset 6 is a screenshot: PNG, no camera EXIF, telltale filename.
ASSETS[6]["originalFileName"] = "Screenshot_2026-07-01.png"
ASSETS[6]["originalMimeType"] = "image/png"
ASSETS[6]["exifInfo"] = {"make": None, "model": None}

TEST_ALBUM_ID = make_id("album-test")
KEEPERS_ALBUM_ID = make_id("album-keepers")
ALBUM_MEMBERS = {
    TEST_ALBUM_ID: [a["id"] for a in ASSETS[:5]],
    KEEPERS_ALBUM_ID: [],
}
TAGS = {}          # name -> tag id
TAGGED = {}        # tag id -> set of asset ids

def log_event(event):
    with LOG_PATH.open("a") as fh:
        fh.write(json.dumps(event) + "\n")
    print("EVENT", json.dumps(event), flush=True)

def asset_dto(asset):
    dto = {k: asset[k] for k in ("id", "type", "originalFileName", "localDateTime",
                                 "isFavorite", "originalMimeType", "exifInfo")}
    dto["isTrashed"] = asset["trashed"]
    return dto

def album_dto(album_id, name):
    members = ALBUM_MEMBERS[album_id]
    return {
        "id": album_id,
        "albumName": name,
        "assetCount": len(members),
        "albumThumbnailAssetId": members[0] if members else None,
    }

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length))

    def send_json(self, obj, status=200):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_png(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def check_auth(self):
        if self.headers.get("x-api-key") != API_KEY:
            self.send_json({"message": "Invalid API key"}, status=401)
            return False
        return True

    def handle_request(self):
        path = self.path.split("?")[0].rstrip("/")
        parts = path.strip("/").split("/")  # e.g. ["api", "assets", "<id>", "thumbnail"]
        method = self.command

        if path == "/api/server/ping":
            return self.send_json({"res": "pong"})
        if not self.check_auth():
            return

        if method == "GET" and path == "/api/users/me":
            return self.send_json({"id": make_id("user"), "name": "Test User", "email": "test@example.com"})

        if method == "GET" and path == "/api/albums":
            return self.send_json([
                album_dto(TEST_ALBUM_ID, "Test Album"),
                album_dto(KEEPERS_ALBUM_ID, "Keepers"),
            ])

        if method == "GET" and path == "/api/assets/statistics":
            trashed = [a for a in ASSETS if a["trashed"]]
            return self.send_json({"images": len(trashed), "total": len(trashed), "videos": 0})

        if method == "GET" and path == "/api/duplicates":
            # One group: assets 5 and 7 (outside the test album); keep 5.
            members = [a for a in (ASSETS[5], ASSETS[7]) if not a["trashed"]]
            groups = []
            if len(members) > 1:
                groups.append({
                    "duplicateId": make_id("dup-1"),
                    "assets": [asset_dto(a) for a in members],
                    "suggestedKeepAssetIds": [ASSETS[5]["id"]],
                })
            return self.send_json(groups)

        if method == "POST" and path == "/api/search/smart":
            # Pretend assets 5..7 are the best "receipt" matches.
            items = [asset_dto(a) for a in ASSETS[5:8] if not a["trashed"]]
            return self.send_json({
                "albums": {"items": [], "nextPage": None, "total": 0, "count": 0},
                "assets": {"items": items, "nextPage": None,
                           "total": len(items), "count": len(items)},
            })

        if method == "POST" and path == "/api/search/metadata":
            body = self.read_body()
            # withDeleted + trashedAfter → the trash bin listing.
            if body.get("withDeleted") and body.get("trashedAfter"):
                items = [a for a in ASSETS if a["trashed"]]
            else:
                items = [a for a in ASSETS if not a["trashed"]]
            album_ids = body.get("albumIds")
            if album_ids:
                allowed = set()
                for album_id in album_ids:
                    allowed.update(ALBUM_MEMBERS.get(album_id, []))
                items = [a for a in items if a["id"] in allowed]
            tag_ids = body.get("tagIds")
            if tag_ids:
                tagged = set()
                for tag_id in tag_ids:
                    tagged.update(TAGGED.get(tag_id, set()))
                items = [a for a in items if a["id"] in tagged]
            reverse = body.get("order", "desc") == "desc"
            items.sort(key=lambda a: a["localDateTime"], reverse=reverse)
            page = int(body.get("page", 1))
            size = int(body.get("size", 250))
            start = (page - 1) * size
            page_items = items[start:start + size]
            next_page = str(page + 1) if start + size < len(items) else None
            return self.send_json({
                "albums": {"items": [], "nextPage": None, "total": 0, "count": 0},
                "assets": {
                    "items": [asset_dto(a) for a in page_items],
                    "nextPage": next_page,
                    "total": len(items),
                    "count": len(page_items),
                },
            })

        if method == "GET" and len(parts) == 4 and parts[1] == "assets" and parts[3] == "thumbnail":
            asset = next((a for a in ASSETS if a["id"] == parts[2]), None)
            if asset is None:
                return self.send_json({"message": "Not found"}, status=404)
            return self.send_png(png(asset["color"]))

        if method == "DELETE" and path == "/api/assets":
            body = self.read_body()
            ids = body.get("ids", [])
            if body.get("force"):
                # Permanent delete: remove the assets entirely.
                ASSETS[:] = [a for a in ASSETS if a["id"] not in ids]
                log_event({"action": "delete-permanent", "ids": ids})
            else:
                for a in ASSETS:
                    if a["id"] in ids:
                        a["trashed"] = True
                log_event({"action": "trash", "ids": ids, "force": body.get("force")})
            return self.send_json({})

        if method == "POST" and path == "/api/trash/restore/assets":
            body = self.read_body()
            for a in ASSETS:
                if a["id"] in body.get("ids", []):
                    a["trashed"] = False
            log_event({"action": "restore", "ids": body.get("ids")})
            return self.send_json({})

        if method == "PUT" and path == "/api/assets":
            body = self.read_body()
            for a in ASSETS:
                if a["id"] in body.get("ids", []):
                    a["isFavorite"] = bool(body.get("isFavorite"))
            log_event({"action": "favorite", "ids": body.get("ids"), "isFavorite": body.get("isFavorite")})
            return self.send_json({})

        if method == "PUT" and path == "/api/tags":
            body = self.read_body()
            result = []
            for name in body.get("tags", []):
                tag_id = TAGS.setdefault(name, make_id(f"tag-{name}"))
                TAGGED.setdefault(tag_id, set())
                result.append({"id": tag_id, "name": name, "value": name})
            log_event({"action": "upsert-tags", "tags": body.get("tags")})
            return self.send_json(result)

        if method == "PUT" and path == "/api/tags/assets":
            body = self.read_body()
            for tag_id in body.get("tagIds", []):
                TAGGED.setdefault(tag_id, set()).update(body.get("assetIds", []))
            log_event({"action": "tag-assets", "tagIds": body.get("tagIds"), "assetIds": body.get("assetIds")})
            return self.send_json([])

        if method == "DELETE" and len(parts) == 4 and parts[1] == "tags" and parts[3] == "assets":
            body = self.read_body()
            TAGGED.setdefault(parts[2], set()).difference_update(body.get("ids", []))
            log_event({"action": "untag-assets", "tagId": parts[2], "ids": body.get("ids")})
            return self.send_json([])

        if len(parts) == 4 and parts[1] == "albums" and parts[3] == "assets":
            body = self.read_body()
            album_id = parts[2]
            members = ALBUM_MEMBERS.setdefault(album_id, [])
            if method == "PUT":
                for asset_id in body.get("ids", []):
                    if asset_id not in members:
                        members.append(asset_id)
                log_event({"action": "album-add", "albumId": album_id, "ids": body.get("ids")})
                return self.send_json([{"id": i, "success": True} for i in body.get("ids", [])])
            if method == "DELETE":
                for asset_id in body.get("ids", []):
                    if asset_id in members:
                        members.remove(asset_id)
                log_event({"action": "album-remove", "albumId": album_id, "ids": body.get("ids")})
                return self.send_json([{"id": i, "success": True} for i in body.get("ids", [])])

        self.send_json({"message": f"Unhandled {method} {path}"}, status=404)

    do_GET = handle_request
    do_POST = handle_request
    do_PUT = handle_request
    do_DELETE = handle_request

if __name__ == "__main__":
    LOG_PATH.write_text("")
    server = ThreadingHTTPServer(("127.0.0.1", 2283), Handler)
    print("Mock Immich listening on http://127.0.0.1:2283", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
