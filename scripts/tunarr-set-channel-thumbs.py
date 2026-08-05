#!/usr/bin/env python3
"""Generate + attach Tunarr channel thumbnails for all channels."""

from __future__ import annotations

import io
import json
import re
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BASE = "http://127.0.0.1:8000"
API = f"{BASE}/api"

# Genre / theme → background hex
PALETTE = {
    "Action": "#c0392b",
    "Adventure": "#d35400",
    "Drama": "#8e44ad",
    "Sci-Fi": "#1abc9c",
    "Science Fiction": "#1abc9c",
    "Thriller": "#2c3e50",
    "Comedy": "#f39c12",
    "Crime": "#7f8c8d",
    "Fantasy": "#9b59b6",
    "Horror": "#1a1a2e",
    "Romance": "#e91e63",
    "Mystery": "#34495e",
    "Family": "#27ae60",
    "Animation": "#3498db",
    "War": "#5d4037",
    "History": "#6d4c41",
    "1990s": "#16a085",
    "2000s": "#2980b9",
    "2010s": "#8e44ad",
    "2020s": "#e67e22",
    "Scary": "#4a0e0e",
    "Brain": "#5e35b1",
    "Escape": "#00695c",
    "Laugh": "#f9a825",
    "Mix": "#455a64",
}

VARIANT_ACCENT = {
    "Shuffle": "#ffffff",
    "Classics": "#ffd54f",
    "Fresh": "#81d4fa",
}


def api(method: str, path: str, body=None):
    if body is None and method in ("DELETE", "POST", "PUT", "PATCH"):
        body = {}
    data = None if body is None else json.dumps(body).encode()
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        API + path, data=data, method=method, headers=headers
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def upload_png(filename: str, png_bytes: bytes) -> str:
    boundary = "----TunarrThumb7e3"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: image/png\r\n\r\n"
    ).encode() + png_bytes + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(
        API + "/upload/image",
        data=body,
        method="POST",
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read())
    url = resp.get("fileUrl") or resp.get("url")
    if not url:
        raise RuntimeError(f"upload failed: {resp}")
    # Normalize to path Jellyfin can reach via tunarr hostname
    # fileUrl may be http://127.0.0.1:8000/images/uploads/...
    path = url
    if "/images/uploads/" in url:
        path = "/images/uploads/" + url.split("/images/uploads/")[-1]
        path = f"http://tunarr:8000{path}"
    return path


def pick_color(name: str) -> str:
    for key, color in PALETTE.items():
        if key.lower() in name.lower():
            return color
    return "#37474f"


def pick_accent(name: str) -> str:
    for key, color in VARIANT_ACCENT.items():
        if key.lower() in name.lower():
            return color
    return "#eceff1"


def wrap_lines(text: str, max_chars: int = 12) -> list[str]:
    words = text.replace(" + ", "+").split()
    lines: list[str] = []
    cur = ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if len(trial) <= max_chars:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines[:3] or [text[:max_chars]]


def make_thumb(number: int, name: str, size: int = 512) -> bytes:
    bg = pick_color(name)
    accent = pick_accent(name)
    img = Image.new("RGB", (size, size), bg)
    draw = ImageDraw.Draw(img)

    # Top bar
    draw.rectangle([0, 0, size, 72], fill="#00000088")
    # Bottom accent stripe
    draw.rectangle([0, size - 28, size, size], fill=accent)

    try:
        font_lg = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 54
        )
        font_num = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 42
        )
        font_sm = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 28
        )
    except OSError:
        font_lg = font_num = font_sm = ImageFont.load_default()

    # Channel number badge
    badge = f"CH {number}"
    draw.text((24, 18), badge, fill="white", font=font_num)

    # Title lines centered
    lines = wrap_lines(name, 14)
    y = size // 2 - (len(lines) * 64) // 2
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font_lg)
        tw = bbox[2] - bbox[0]
        draw.text(((size - tw) // 2, y), line, fill="white", font=font_lg)
        y += 64

    # Variant tag from name
    m = re.search(r"(Shuffle|Classics|Fresh)$", name)
    tag = m.group(1) if m else "LIVE"
    bbox = draw.textbbox((0, 0), tag, font=font_sm)
    tw = bbox[2] - bbox[0]
    draw.text(((size - tw) // 2, size - 88), tag, fill=accent, font=font_sm)

    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def main() -> None:
    channels = api("GET", "/channels") or []
    channels = sorted(channels, key=lambda c: c["number"])
    print(f"Updating icons for {len(channels)} channels…")

    for ch in channels:
        num = ch["number"]
        name = ch["name"]
        png = make_thumb(num, name)
        fname = f"ch{num:02d}-{re.sub(r'[^a-zA-Z0-9]+', '-', name).strip('-').lower()}.png"
        url = upload_png(fname, png)

        body = dict(ch)
        for k in ("programCount", "sessions", "fallback"):
            body.pop(k, None)
        body["duration"] = int(body.get("duration") or 0)
        body["icon"] = {
            "path": url,
            "width": 0,
            "duration": 0,
            "position": "bottom-right",
            "useDefaultIconFallback": False,
        }
        api("PUT", f"/channels/{ch['id']}", body)
        print(f"#{num:02d} {name} → {url}")

    try:
        api("POST", "/tasks/UpdateXmlTvTask/run")
        print("Triggered XMLTV refresh")
    except Exception as e:
        print(f"XMLTV refresh note: {e}")

    # Sanity: icons in xmltv
    with urllib.request.urlopen(f"{BASE}/api/xmltv.xml") as r:
        xml = r.read().decode()
    icons = len(re.findall(r"<icon ", xml))
    print(f"XMLTV icon tags: {icons}")


if __name__ == "__main__":
    main()
