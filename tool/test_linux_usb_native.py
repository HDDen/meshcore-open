"""Exercise a built flserial on Linux PTYs without Flutter or a physical radio.

Run explicitly with --library; this script neither builds nor downloads code.
Native failures stay in child processes so a null callback gives a test failure
instead of killing the parent runner.
"""

import argparse
import ctypes
import os
from pathlib import Path
import select
import subprocess
import sys
import threading
import time


CASES = ("early-rx", "close-before-callback", "binary-io-and-baud")
CALLBACK = ctypes.CFUNCTYPE(None, ctypes.c_uint, ctypes.c_uint)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def load_library(path):
    library = ctypes.CDLL(str(path))
    signatures = {
        "fl_init": [ctypes.c_int],
        "fl_open": [ctypes.c_int, ctypes.c_char_p, ctypes.c_int],
        "fl_ctrl": [ctypes.c_int, ctypes.c_int, ctypes.c_int],
        "fl_set_callback": [ctypes.c_int, CALLBACK],
        "fl_read": [ctypes.c_int, ctypes.c_int, ctypes.c_void_p],
        "fl_write": [ctypes.c_int, ctypes.c_int, ctypes.c_void_p],
        "fl_close": [ctypes.c_int],
        "fl_free": [],
    }
    for name, arguments in signatures.items():
        function = getattr(library, name)
        function.argtypes = arguments
        function.restype = ctypes.c_int
    return library


def read_master(master, count):
    result = bytearray()
    deadline = time.monotonic() + 2
    while len(result) < count:
        remaining = deadline - time.monotonic()
        require(remaining > 0, "Timed out waiting for native TX")
        readable, _, _ = select.select([master], [], [], remaining)
        require(bool(readable), "Native TX did not reach the PTY")
        result.extend(os.read(master, count - len(result)))
    return bytes(result)


def exercise(library, case, baud):
    import termios  # Linux-only; keep --help usable on other hosts.

    master, slave = os.openpty()
    handle = None
    # Keep this callback alive until fl_close has joined the native thread.
    arrived = threading.Event()
    lengths = []

    @CALLBACK
    def on_data(_handle, length):
        lengths.append(length)
        arrived.set()

    payload = bytes([0x3E, 0x06, 0x00, 0x17, 0x00, 0xFF, 0x3C, 0x3E, 0x80])
    try:
        require(library.fl_init(16) == 0, "fl_init failed")
        handle = library.fl_open(-1, os.fsencode(os.ttyname(slave)), baud)
        require(handle >= 0, "fl_open returned an invalid handle")
        # FL_CTRL_IS_PORT_OPEN is 1 in the retained flserial.h ABI.
        require(library.fl_ctrl(handle, 1, 0) == 1, "PTY did not open")
        speed = getattr(termios, "B" + str(baud))
        attributes = termios.tcgetattr(slave)
        require(attributes[4:6] == [speed, speed], "Incorrect RX/TX baud")

        if case != "binary-io-and-baud":
            os.write(master, payload)
            # Let SerialThread reach its formerly unguarded null callback.
            time.sleep(0.1)
            require(not arrived.is_set(), "Unexpected callback before install")
            if case == "close-before-callback":
                require(library.fl_close(handle) == 0, "fl_close failed")
                handle = None
                return

        require(library.fl_set_callback(handle, on_data) == 0, "Set callback failed")
        if case == "binary-io-and-baud":
            os.write(master, payload)
        require(arrived.wait(2), "No RX notification after installing callback")
        require(sum(lengths) == len(payload), "Incorrect callback byte count")
        received = ctypes.create_string_buffer(len(payload))
        count = library.fl_read(handle, len(payload), received)
        require(count == len(payload), "Early RX bytes were lost")
        require(received.raw == payload, "Binary RX was changed")

        sent = ctypes.create_string_buffer(payload)
        require(library.fl_write(handle, len(payload), sent) == 0, "fl_write failed")
        require(read_master(master, len(payload)) == payload, "Binary TX was changed")
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
    parser.add_argument("--case", choices=CASES, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("The native PTY checks require Linux (WSL is supported)")
    library_path = args.library.resolve()
    if not library_path.is_file():
        parser.error("Build libflserial.so first; library not found: " + str(library_path))

    if args.case:
        library = load_library(library_path)
        rates = (9600, 115200, 230400) if args.case == "binary-io-and-baud" else (115200,)
        for baud in rates:
            exercise(library, args.case, baud)
        return 0

    failed = False
    for case in CASES:
        try:
            result = subprocess.run(
                [sys.executable, "-B", str(Path(__file__).resolve()),
                 "--library", str(library_path), "--case", case],
                capture_output=True, text=True, timeout=12, check=False,
            )
            require(result.returncode == 0,
                    f"Native exit {result.returncode}\n{result.stdout}{result.stderr}")
            print("PASS:", case)
        except (AssertionError, subprocess.TimeoutExpired) as error:
            failed = True
            print("FAIL:", case, str(error), file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
