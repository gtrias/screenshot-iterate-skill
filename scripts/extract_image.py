#!/usr/bin/env python3
"""Extract base64 image payload from codex session rollout JSONL files.

Usage: extract_image.py <output_path.png> <list_of_session_files.txt>

Exit 0 on success, exit 1 if no image payload found.
"""

import base64
import pathlib
import sys


def main():
    out_path = pathlib.Path(sys.argv[1])
    list_path = pathlib.Path(sys.argv[2])

    file_list = list_path.read_text().strip().splitlines()
    file_list = [f for f in file_list if f.strip()]

    if not file_list:
        print("No session files to scan", file=sys.stderr)
        sys.exit(1)

    # Image magic headers (first 8 bytes of base64-decoded data)
    png_header = b"\x89PNG\r\n\x1a\n"
    jpeg_headers = [b"\xff\xd8\xff"]
    webp_header = b"RIFF"

    def has_image_magic(data: bytes) -> bool:
        if len(data) >= 8 and data[:8] == png_header:
            return True
        if len(data) >= 3 and data[:3] in jpeg_headers:
            return True
        if len(data) >= 4 and data[:4] == webp_header:
            return True
        return False

    largest_size = 0
    largest_data = None

    for session_file in file_list:
        sp = pathlib.Path(session_file.strip())
        if not sp.is_file():
            continue
        try:
            text = sp.read_text()
        except Exception:
            continue

        for line in text.splitlines():
            if not line.strip():
                continue
            # Look for base64 blobs in the rollout JSONL
            import json
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            def scan(obj, depth=0):
                nonlocal largest_size, largest_data
                if isinstance(obj, str):
                    if len(obj) > 500 and "image" in line.lower():
                        try:
                            decoded = base64.b64decode(obj, validate=False)
                            if has_image_magic(decoded) and len(decoded) > largest_size:
                                largest_size = len(decoded)
                                largest_data = decoded
                        except Exception:
                            pass
                elif isinstance(obj, dict):
                    for v in obj.values():
                        scan(v, depth + 1)
                elif isinstance(obj, list):
                    for item in obj:
                        scan(item, depth + 1)

            scan(obj)

    if largest_data is None or largest_size == 0:
        print("No image payload found in session files", file=sys.stderr)
        sys.exit(1)

    out_path.write_bytes(largest_data)
    print(f"Extracted {largest_size} bytes -> {out_path}")


if __name__ == "__main__":
    main()
