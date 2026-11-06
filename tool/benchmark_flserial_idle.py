"""Measure an already built flserial on a quiet Linux PTY, before and after U16.

This script never builds or downloads a library. Run the same script against
both binaries. It reports process CPU divided by wall time (100% = one core),
not application power consumption, USB hardware latency or radio performance.
"""

import argparse
import ctypes
import hashlib
import os
from pathlib import Path
import sys
import threading
import time

from test_linux_usb_native import CALLBACK, load_library, read_master, require


PAYLOAD = bytes([0x3E, 0x06, 0x00, 0x17, 0x00, 0xFF, 0x3C, 0x3E, 0x80])


def measure(library, seconds):
    master, slave = os.openpty()
    handle = None
    arrived = threading.Event()
    lengths = []

    # Keep the callback alive until fl_close has joined SerialThread.
    @CALLBACK
    def on_data(_handle, length):
        lengths.append(length)
        arrived.set()

    try:
        require(library.fl_init(16) == 0, "fl_init failed")
        handle = library.fl_open(-1, os.fsencode(os.ttyname(slave)), 115200)
        require(handle >= 0, "Invalid native handle")
        require(library.fl_ctrl(handle, 1, 0) == 1, "PTY did not open")
        require(library.fl_set_callback(handle, on_data) == 0, "Set callback failed")
        time.sleep(0.1)
        require(not arrived.is_set(), "Unexpected idle callback")

        wall_start = time.perf_counter()
        cpu_start = time.process_time()
        time.sleep(seconds)
        cpu_seconds = time.process_time() - cpu_start
        wall_seconds = time.perf_counter() - wall_start
        idle_core_percent = 100 * cpu_seconds / wall_seconds
        require(not arrived.is_set(), "Unexpected callback during idle measurement")

        rx_start = time.perf_counter()
        os.write(master, PAYLOAD)
        require(arrived.wait(2), "RX after idle timed out")
        rx_us = (time.perf_counter() - rx_start) * 1_000_000
        require(sum(lengths) == len(PAYLOAD), "Incorrect RX callback byte count")
        received = ctypes.create_string_buffer(len(PAYLOAD))
        require(library.fl_read(handle, len(PAYLOAD), received) == len(PAYLOAD),
                "RX bytes were lost")
        require(received.raw == PAYLOAD, "RX bytes changed")

        # Drain RX completely, then exercise queued TX with no incoming data.
        time.sleep(0.05)
        tx_start = time.perf_counter()
        sent = ctypes.create_string_buffer(PAYLOAD)
        require(library.fl_write(handle, len(PAYLOAD), sent) == 0, "TX enqueue failed")
        require(read_master(master, len(PAYLOAD)) == PAYLOAD, "TX bytes changed")
        tx_us = (time.perf_counter() - tx_start) * 1_000_000

        time.sleep(0.05)
        close_start = time.perf_counter()
        require(library.fl_close(handle) == 0, "Idle close failed")
        handle = None
        close_us = (time.perf_counter() - close_start) * 1_000_000
        require(close_us < 2_000_000, "Idle close did not join promptly")
        return idle_core_percent, wall_seconds, cpu_seconds, rx_us, tx_us, close_us
    finally:
        try:
            if handle is not None:
                library.fl_close(handle)
            library.fl_free()
        finally:
            os.close(master)
            os.close(slave)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--idle-seconds", type=float, default=2)
    parser.add_argument("--max-idle-core-percent", type=float,
                        help="Optional post-change idle CPU regression limit")
    # Only the parent enforces a wall-clock limit on a hung native join.
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("The native PTY measurement requires Linux")
    if not 1 <= args.rounds <= 10 or not 0.5 <= args.idle_seconds <= 30:
        parser.error("Use 1..10 rounds and an idle interval of 0.5..30 seconds")
    if args.max_idle_core_percent is not None and not 0 < args.max_idle_core_percent <= 100:
        parser.error("The optional CPU limit must be greater than 0 and at most 100")
    path = args.library.resolve()
    if not path.is_file():
        parser.error("Build the library first: " + str(path))

    if args.worker:
        values = measure(load_library(path), args.idle_seconds)
        percent, wall, cpu, rx, tx, close = values
        print(f"idleCorePercent={percent:.3f} wallSeconds={wall:.3f} "
              f"cpuSeconds={cpu:.6f} rxUs={rx:.0f} txUs={tx:.0f} "
              f"closeUs={close:.0f}; binaryRXTX=equal", flush=True)
        if args.max_idle_core_percent is not None:
            require(percent <= args.max_idle_core_percent,
                    f"Idle CPU {percent:.3f}% exceeds {args.max_idle_core_percent}%")
        return 0

    import subprocess

    print("Library SHA256=" + hashlib.sha256(path.read_bytes()).hexdigest(), flush=True)
    print("Fixed binary payload; quiet Linux PTY; 100% = one CPU core.", flush=True)
    print("Not Flutter, real USB/radio, application energy or a latency guarantee.", flush=True)
    failed = False
    for round_number in range(1, args.rounds + 1):
        command = [sys.executable, "-B", str(Path(__file__).resolve()),
                   "--worker", "--library", str(path),
                   "--idle-seconds", str(args.idle_seconds)]
        if args.max_idle_core_percent is not None:
            command += ["--max-idle-core-percent", str(args.max_idle_core_percent)]
        try:
            result = subprocess.run(command, capture_output=True, text=True,
                                    timeout=args.idle_seconds + 10, check=False)
            print(f"round={round_number} {result.stdout.strip()}", flush=True)
            require(result.returncode == 0,
                    f"Native exit {result.returncode}: {result.stderr.strip()}")
        except (AssertionError, subprocess.TimeoutExpired) as error:
            failed = True
            print(f"FAIL round={round_number}: {error}", file=sys.stderr, flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
