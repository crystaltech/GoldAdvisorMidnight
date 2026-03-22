#!/usr/bin/env python3
"""
decode_data.py — Gold Advisor Midnight data file decoder.

Reverses encode_data.py for development and round-trip verification.

Usage:
    python tools/decode_data.py Data/StratsEncoded.lua
    python tools/decode_data.py Data/WorkbookEncoded.lua --out decoded.lua
    python tools/decode_data.py Data/StratsEncoded.lua | head -30

Pass --key to override if you used a non-default key when encoding.
"""

import base64
import argparse
import os
import re
import sys

# ── Must match encode_data.py exactly ────────────────────────────────────────

XOR_KEY = "MidnightGold2026"

CUSTOM_B64 = (
    "QRSTUVWXYZabcdefvutsrqponmlkjihg"
    "wxyz0123456789+/ABCDEFGHIJKLMNOP"
)

STANDARD_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


# ── Decode helpers ────────────────────────────────────────────────────────────

def xor_bytes(data: bytes, key: str) -> bytes:
    key_bytes = key.encode("utf-8")
    key_len = len(key_bytes)
    return bytes(b ^ key_bytes[i % key_len] for i, b in enumerate(data))


def custom_b64_decode(s: str) -> bytes:
    """Base64-decode using CUSTOM_B64 alphabet."""
    trans = str.maketrans(CUSTOM_B64, STANDARD_B64)
    standard = s.translate(trans)
    return base64.b64decode(standard)


def decode_file(src_path: str, key: str) -> str:
    with open(src_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Extract the encoded string from the Lua assignment line
    m = re.search(r'=\s*"([A-Za-z0-9+/QRSTUVWXYZabcdefvutsrqponmlkjihgwxyz=]+)"', content)
    if not m:
        raise ValueError(f"Could not find encoded string in {src_path}")

    encoded        = m.group(1)
    xored          = custom_b64_decode(encoded)
    original_bytes = xor_bytes(xored, key)
    return original_bytes  # return raw bytes; caller decides encoding


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Decode a GAM encoded data file.")
    parser.add_argument("file", help="Path to encoded .lua file (e.g. Data/StratsEncoded.lua)")
    parser.add_argument("--key", default=XOR_KEY, help="Override XOR key")
    parser.add_argument("--out", help="Write decoded Lua to this file (default: stdout)")
    args = parser.parse_args()

    decoded = decode_file(args.file, args.key)

    if args.out:
        # Write raw bytes to preserve exact line endings from original
        with open(args.out, "wb") as f:
            f.write(decoded)
        print(f"Decoded → {args.out}", file=sys.stderr)
    else:
        sys.stdout.buffer.write(decoded)


if __name__ == "__main__":
    main()
