#!/usr/bin/env python3
"""
MCOtxt v1 RU/EN A/B benchmark.

Reads two trainer debug JSON models and one or more TXT/JSONL corpora.
Computes exact MCOtxt v1 bit COST for the current token tree and A/B TOGGLE
semantics using dynamic programming.

This is a reference cost benchmark, not a bitstream encoder/decoder.
It is useful for comparing trained tables/corpora independently of Flutter.

Semantics:
- 9-bit header/message.
- variable TOP4: rank0=2 bits, rank1=3 bits, rank2/rank3=4 bits.
- PRIMARY literal 7 bits.
- EXTENSION literal 9 bits.
- SHIFT 5 bits + symbol token.
- PUNCTUATION 8 bits.
- TOGGLE_LANGUAGE 6 bits.
- START / AFTER_PUNCT / SYMBOL(previous) contexts.
- LF -> START.
- ordinary punctuation -> AFTER_PUNCT.
- language toggle -> START in new language.
- UTF8_RUN is fallback-only for unsupported A/B fragments, up to 32 UTF-8 bytes, and resets context to START.
- persistent CAPS_MODE costs 9 bits to toggle; SHIFT (5 bits) inverts case for one caseable symbol; case controls are preplanned by a tiny 2-state DP.
- RAW_UTF8 is a message-level candidate and is selected when its complete
  payload is smaller than the normal MCOtxt candidate.
- NFC; CRLF/CR -> LF.
- all input is lossless after NFC/newline normalization; supported text is not diverted into UTF8_RUN.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import math
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, Sequence, Tuple

HEADER_BITS = 9
RAW_UTF8_HEADER_BITS = 16
TOP4_BITS_BY_RANK = (2, 3, 4, 4)
PRIMARY_BITS = 7
PUNCT_BITS = 8
EXT_BITS = 9
SHIFT_BITS = 5
TOGGLE_BITS = 6
UTF8_RUN_OVERHEAD_BITS = 14
UTF8_RUN_MAX_BYTES = 32
CASE_MODE_TOGGLE_BITS = 9

def _top4_bits(rank: int) -> int:
    if rank < 0 or rank >= len(TOP4_BITS_BY_RANK):
        raise ValueError(f"invalid TOP4 rank: {rank}")
    return TOP4_BITS_BY_RANK[rank]


SPACE = 0x0020
LF = 0x000A

PUNCTUATION_V1 = (
    0x0020,  # SPACE (normally encoded as a language symbol)
    0x002E,  # .
    0x002C,  # ,
    0x0021,  # !
    0x003F,  # ?
    0x003A,  # :
    0x003B,  # ;
    0x002D,  # -
    0x2014,  # —
    0x005F,  # _
    0x0027,  # '
    0x0022,  # "
    0x00AB,  # «
    0x00BB,  # »
    0x201C,  # “
    0x201D,  # ”
    0x201E,  # „
    0x2018,  # ‘
    0x2019,  # ’
    0x0028,  # (
    0x0029,  # )
    0x005B,  # [
    0x005D,  # ]
    0x002F,  # /
    0x005C,  # \
    0x0040,  # @
    0x0023,  # #
    0x0025,  # %
    0x0026,  # &
    0x002B,  # +
    0x003D,  # =
    0x000A,  # LF
)
PUNCT_SET = set(PUNCTUATION_V1)


@dataclass(frozen=True)
class Model:
    code: str
    language_id: int
    primary: Tuple[int, ...]
    extension: Tuple[int, ...]
    start_top4: Tuple[int, ...]
    punct_start_top4: Tuple[int, ...]
    top4: Dict[int, Tuple[int, ...]]
    uppercase_to_lowercase: Dict[int, int]

    @property
    def symbol_set(self):
        return set(self.primary) | set(self.extension)

    @property
    def lowercase_to_uppercase(self):
        return {lower: upper for upper, lower in self.uppercase_to_lowercase.items()}

    def normalize_symbol(self, cp: int) -> Tuple[Optional[int], bool]:
        if cp in self.symbol_set:
            return cp, False
        lower = self.uppercase_to_lowercase.get(cp)
        if lower is not None:
            return lower, True
        return None, False

    def symbol_cost(self, base_cp: int, shifted: bool, ctx: Tuple[str, Optional[int]]) -> int:
        kind, previous = ctx
        if kind == "START":
            row = self.start_top4
        elif kind == "PUNCT":
            row = self.punct_start_top4
        else:
            row = self.top4[previous]

        if base_cp in row:
            cost = TOP4_BITS
        elif base_cp in self.primary:
            cost = PRIMARY_BITS
        elif base_cp in self.extension:
            cost = EXT_BITS
        else:
            raise ValueError(f"{self.code}: symbol U+{base_cp:04X} is not in model")
        if shifted:
            cost += SHIFT_BITS
        return cost


def load_model(path: Path) -> Model:
    obj = json.loads(path.read_text(encoding="utf-8"))
    symbols = list(obj["primarySymbols"]) + list(obj["extensionSymbols"])
    start = tuple(symbols[i] for i in obj["startTop4Indexes"])
    punct = tuple(symbols[i] for i in obj["punctStartTop4Indexes"])
    flat = obj["top4Indexes"]
    if len(flat) != len(symbols) * 4:
        raise ValueError(f"{path}: top4Indexes length mismatch")
    top4 = {
        cp: tuple(symbols[flat[i * 4 + j]] for j in range(4))
        for i, cp in enumerate(symbols)
    }
    upper = {
        int(item["uppercaseCodepoint"]): int(item["lowercaseCodepoint"])
        for item in obj["uppercaseMap"]
    }
    return Model(
        code=obj["language"],
        language_id=int(obj["languageId"]),
        primary=tuple(obj["primarySymbols"]),
        extension=tuple(obj["extensionSymbols"]),
        start_top4=start,
        punct_start_top4=punct,
        top4=top4,
        uppercase_to_lowercase=upper,
    )


def expand_paths(items: Sequence[str]) -> List[Path]:
    out: List[Path] = []
    for item in items:
        matches = [Path(p) for p in glob.glob(item, recursive=True)]
        if not matches:
            matches = [Path(item)]
        for path in matches:
            if path.is_dir():
                out.extend(sorted(p for p in path.rglob("*") if p.is_file()))
            elif path.is_file():
                out.append(path)
    # stable dedupe
    seen = set()
    result = []
    for p in out:
        rp = p.resolve()
        if rp not in seen:
            seen.add(rp)
            result.append(p)
    return result


def is_validation_message(text: str, ratio: float, seed: str) -> bool:
    """Match MCOtxt_model_trainer_with_diagnostics.py deterministic SHA-256 hold-out exactly."""
    if ratio <= 0.0:
        return False
    if ratio >= 1.0:
        return True
    digest = hashlib.sha256(seed.encode("utf-8") + b"\0" + text.encode("utf-8")).digest()
    value = int.from_bytes(digest[:8], "big") / float(1 << 64)
    return value < ratio


def iter_messages(paths: Sequence[Path], fmt: str, jsonl_field: str) -> Iterator[Tuple[str, str]]:
    for path in paths:
        actual_fmt = fmt
        if actual_fmt == "auto":
            actual_fmt = "jsonl" if path.suffix.lower() in (".jsonl", ".ndjson") else "lines"

        if actual_fmt == "jsonl":
            for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if not line.strip():
                    continue
                obj = json.loads(line)
                text = obj.get(jsonl_field)
                if not isinstance(text, str):
                    raise ValueError(f"{path}:{line_no}: field {jsonl_field!r} is not a string")
                yield str(path), text
        elif actual_fmt in ("lines", "text"):
            for line in path.read_text(encoding="utf-8").splitlines():
                yield str(path), line
        else:
            raise ValueError(actual_fmt)


@dataclass(frozen=True)
class _PathCost:
    bits: int
    tokens: int = 0
    language_switches: int = 0
    toggles: int = 0
    case_toggles: int = 0
    shifts: int = 0
    utf8_runs: int = 0
    utf8_codepoints: int = 0
    utf8_bytes: int = 0
    utf8_bits: int = 0
    top4_hits: int = 0
    top4_rank_hits: Tuple[int, int, int, int] = (0, 0, 0, 0)


@dataclass
class BenchResult:
    bits: int
    payload_bytes: int
    mode: str
    toggles: int
    case_toggles: int
    shifts: int
    output_chars: int
    output_utf8_bytes: int
    skipped_chars: int
    utf8_fallback_runs: int
    utf8_fallback_codepoints: int
    utf8_fallback_bytes: int
    utf8_fallback_bits: int
    top4_rank_hits: Tuple[int, int, int, int]
    initial_language: str
    mixed: bool
    mcotxt_candidate_bits: int = 0
    mcotxt_candidate_bytes: int = 0
    raw_utf8_candidate_bits: int = 0
    raw_utf8_candidate_bytes: int = 0
    mcotxt_case_toggles: int = 0
    mcotxt_shifts: int = 0
    mcotxt_utf8_runs: int = 0
    mcotxt_top4_rank_hits: Tuple[int, int, int, int] = (0, 0, 0, 0)


def _add_cost(a: _PathCost, b: _PathCost) -> _PathCost:
    return _PathCost(
        bits=a.bits + b.bits,
        tokens=a.tokens + b.tokens,
        language_switches=a.language_switches + b.language_switches,
        toggles=a.toggles + b.toggles,
        case_toggles=a.case_toggles + b.case_toggles,
        shifts=a.shifts + b.shifts,
        utf8_runs=a.utf8_runs + b.utf8_runs,
        utf8_codepoints=a.utf8_codepoints + b.utf8_codepoints,
        utf8_bytes=a.utf8_bytes + b.utf8_bytes,
        utf8_bits=a.utf8_bits + b.utf8_bits,
        top4_hits=a.top4_hits + b.top4_hits,
        top4_rank_hits=tuple(a.top4_rank_hits[i] + b.top4_rank_hits[i] for i in range(4)),
    )


def _better_path(a: _PathCost, b: Optional[_PathCost]) -> bool:
    if b is None:
        return True
    # Mirrors the meaningful Dart _MCOtxtPlan.compare priorities.
    return (
        a.bits,
        a.tokens,
        a.language_switches,
        -a.top4_hits,
        a.case_toggles,
        a.shifts,
        a.utf8_runs,
    ) < (
        b.bits,
        b.tokens,
        b.language_switches,
        -b.top4_hits,
        b.case_toggles,
        b.shifts,
        b.utf8_runs,
    )


def _prefer_result(a: BenchResult, b: BenchResult) -> bool:
    if a.payload_bytes != b.payload_bytes:
        return a.payload_bytes < b.payload_bytes
    if a.bits != b.bits:
        return a.bits < b.bits
    if a.mode != b.mode:
        return a.mode == "mcotxt"
    if a.toggles != b.toggles:
        return a.toggles < b.toggles
    return a.case_toggles < b.case_toggles


def _context_after_punctuation(cp: int, kind: str, previous: Optional[int]) -> Tuple[str, Optional[int]]:
    if cp == SPACE:
        if kind == "SYMBOL" and previous is not None:
            return "SYMBOL", previous
        return "START", None
    if cp == LF:
        return "START", None
    return "PUNCT", None


def _symbol_base_cost(model: Model, base_cp: int, ctx: Tuple[str, Optional[int]]) -> Tuple[int, Optional[int]]:
    kind, previous = ctx
    if kind == "START":
        row = model.start_top4
    elif kind == "PUNCT":
        row = model.punct_start_top4
    else:
        row = model.top4[previous]
    if base_cp in row:
        rank = row.index(base_cp)
        return _top4_bits(rank), rank
    if base_cp in model.primary:
        return PRIMARY_BITS, None
    if base_cp in model.extension:
        return EXT_BITS, None
    raise ValueError(f"{model.code}: symbol U+{base_cp:04X} is not in model")


def _message_mixed(text: str, models: Tuple[Model, Model]) -> bool:
    seen = set()
    for ch in text:
        cp = ord(ch)
        support = [model.normalize_symbol(cp)[0] is not None for model in models]
        if support[0] and not support[1]:
            seen.add(0)
        elif support[1] and not support[0]:
            seen.add(1)
    return len(seen) > 1


def _build_case_plan(text: str, models: Tuple[Model, Model]) -> Tuple[set[int], set[int]]:
    """Optimize persistent CAPS_MODE independently with a tiny 2-state DP."""
    positions: List[int] = []
    wants_upper: List[bool] = []
    for pos, ch in enumerate(text):
        cp = ord(ch)
        requirement: Optional[bool] = None
        for model in models:
            base, input_is_upper = model.normalize_symbol(cp)
            if base is None or base not in model.lowercase_to_uppercase:
                continue
            requirement = input_is_upper
            break
        if requirement is None:
            continue
        positions.append(pos)
        wants_upper.append(requirement)

    if not positions:
        return set(), set()

    # state -> (bits, toggles, shifts)
    previous: List[Optional[Tuple[int, int, int]]] = [(0, 0, 0), None]
    backtrack: List[List[Optional[Tuple[int, bool, bool]]]] = []

    def better(a: Tuple[int, int, int], b: Optional[Tuple[int, int, int]]) -> bool:
        return b is None or a < b

    for desired_upper in wants_upper:
        nxt: List[Optional[Tuple[int, int, int]]] = [None, None]
        decisions: List[Optional[Tuple[int, bool, bool]]] = [None, None]
        for prev_state in (0, 1):
            prev = previous[prev_state]
            if prev is None:
                continue
            for next_state in (0, 1):
                toggled = prev_state != next_state
                shifted = desired_upper != bool(next_state)
                cand = (
                    prev[0] + (CASE_MODE_TOGGLE_BITS if toggled else 0) + (SHIFT_BITS if shifted else 0),
                    prev[1] + int(toggled),
                    prev[2] + int(shifted),
                )
                if better(cand, nxt[next_state]):
                    nxt[next_state] = cand
                    decisions[next_state] = (prev_state, toggled, shifted)
        previous = nxt
        backtrack.append(decisions)

    state = 0 if better(previous[0], previous[1]) else 1
    toggles: set[int] = set()
    shifts: set[int] = set()
    for i in range(len(positions) - 1, -1, -1):
        decision = backtrack[i][state]
        assert decision is not None
        prev_state, toggled, shifted = decision
        if toggled:
            toggles.add(positions[i])
        if shifted:
            shifts.add(positions[i])
        state = prev_state
    return toggles, shifts


def _is_supported_by_ab(cp: int, models: Tuple[Model, Model]) -> bool:
    if cp in PUNCT_SET:
        return True
    return any(model.normalize_symbol(cp)[0] is not None for model in models)


def _fallback_run_at(chars: Sequence[str], position: int, models: Tuple[Model, Model]) -> Tuple[int, int]:
    data = bytearray()
    codepoints = 0
    for i in range(position, len(chars)):
        cp = ord(chars[i])
        if _is_supported_by_ab(cp, models):
            break
        encoded = chars[i].encode("utf-8")
        if data and len(data) + len(encoded) > UTF8_RUN_MAX_BYTES:
            break
        data.extend(encoded)
        codepoints += 1
        if len(data) == UTF8_RUN_MAX_BYTES:
            break
    if codepoints == 0:
        encoded = chars[position].encode("utf-8")
        data.extend(encoded)
        codepoints = 1
    return codepoints, len(data)


def benchmark_message(text: str, a: Model, b: Model, initial_index: int) -> BenchResult:
    text = unicodedata.normalize("NFC", text.replace("\r\n", "\n").replace("\r", "\n"))
    chars = list(text)
    models = (a, b)
    normalized_symbols = [
        tuple(model.normalize_symbol(ord(ch)) for model in models)
        for ch in chars
    ]
    case_toggle_positions, shift_positions = _build_case_plan(text, models)

    memo: Dict[Tuple[int, int, str, Optional[int]], _PathCost] = {}

    def best_from(
        position: int,
        active: int,
        kind: str,
        previous: Optional[int],
    ) -> _PathCost:
        if position >= len(chars):
            return _PathCost(0)
        key = (position, active, kind, previous)
        cached = memo.get(key)
        if cached is not None:
            return cached

        cp = ord(chars[position])
        best: Optional[_PathCost] = None

        if cp in PUNCT_SET:
            nkind, nprev = _context_after_punctuation(cp, kind, previous)
            cand = _add_cost(
                _PathCost(PUNCT_BITS, tokens=1),
                best_from(position + 1, active, nkind, nprev),
            )
            if _better_path(cand, best):
                best = cand

        for target in (0, 1):
            base, _input_is_upper = normalized_symbols[position][target]
            if base is None:
                continue
            switched = target != active
            target_ctx = ("START", None) if switched else (kind, previous)
            base_bits, rank = _symbol_base_cost(models[target], base, target_ctx)
            case_toggle = position in case_toggle_positions
            shift = position in shift_positions
            if shift and base not in models[target].lowercase_to_uppercase:
                continue

            rank_hits = [0, 0, 0, 0]
            if rank is not None:
                rank_hits[rank] = 1
            prefix = _PathCost(
                bits=(TOGGLE_BITS if switched else 0)
                + (CASE_MODE_TOGGLE_BITS if case_toggle else 0)
                + (SHIFT_BITS if shift else 0)
                + base_bits,
                tokens=1 + int(switched) + int(case_toggle) + int(shift),
                language_switches=int(switched),
                toggles=int(switched),
                case_toggles=int(case_toggle),
                shifts=int(shift),
                top4_hits=int(rank is not None),
                top4_rank_hits=tuple(rank_hits),
            )
            cand = _add_cost(
                prefix,
                best_from(position + 1, target, "SYMBOL", base),
            )
            if _better_path(cand, best):
                best = cand

        # UTF8_RUN is fallback-only again. It is used only if neither A/B nor
        # punctuation can represent the current codepoint.
        if best is None:
            codepoints, run_bytes = _fallback_run_at(chars, position, models)
            run_bits = UTF8_RUN_OVERHEAD_BITS + run_bytes * 8
            prefix = _PathCost(
                bits=run_bits,
                tokens=1,
                utf8_runs=1,
                utf8_codepoints=codepoints,
                utf8_bytes=run_bytes,
                utf8_bits=run_bits,
            )
            best = _add_cost(
                prefix,
                best_from(position + codepoints, active, "START", None),
            )

        memo[key] = best
        return best

    path = best_from(0, initial_index, "START", None)
    total_bits = HEADER_BITS + path.bits
    output_utf8_bytes = len(text.encode("utf-8"))
    return BenchResult(
        bits=total_bits,
        payload_bytes=math.ceil(total_bits / 8),
        mode="mcotxt",
        toggles=path.toggles,
        case_toggles=path.case_toggles,
        shifts=path.shifts,
        output_chars=len(text),
        output_utf8_bytes=output_utf8_bytes,
        skipped_chars=0,
        utf8_fallback_runs=path.utf8_runs,
        utf8_fallback_codepoints=path.utf8_codepoints,
        utf8_fallback_bytes=path.utf8_bytes,
        utf8_fallback_bits=path.utf8_bits,
        top4_rank_hits=path.top4_rank_hits,
        initial_language=models[initial_index].code,
        mixed=_message_mixed(text, models),
    )


def best_message(text: str, a: Model, b: Model) -> BenchResult:
    r0 = benchmark_message(text, a, b, 0)
    r1 = benchmark_message(text, a, b, 1)
    normal = r1 if _prefer_result(r1, r0) else r0
    normalized = unicodedata.normalize("NFC", text.replace("\r\n", "\n").replace("\r", "\n"))
    raw_bytes = len(normalized.encode("utf-8"))
    raw_bits = RAW_UTF8_HEADER_BITS + raw_bytes * 8
    raw = BenchResult(
        bits=raw_bits,
        payload_bytes=math.ceil(raw_bits / 8),
        mode="rawUtf8",
        toggles=0,
        case_toggles=0,
        shifts=0,
        output_chars=len(normalized),
        output_utf8_bytes=raw_bytes,
        skipped_chars=0,
        utf8_fallback_runs=0,
        utf8_fallback_codepoints=0,
        utf8_fallback_bytes=0,
        utf8_fallback_bits=0,
        top4_rank_hits=(0, 0, 0, 0),
        initial_language="RAW_UTF8",
        mixed=normal.mixed,
    )

    selected = raw if _prefer_result(raw, normal) else normal
    selected.mcotxt_candidate_bits = normal.bits
    selected.mcotxt_candidate_bytes = normal.payload_bytes
    selected.raw_utf8_candidate_bits = raw.bits
    selected.raw_utf8_candidate_bytes = raw.payload_bytes
    selected.mcotxt_case_toggles = normal.case_toggles
    selected.mcotxt_shifts = normal.shifts
    selected.mcotxt_utf8_runs = normal.utf8_fallback_runs
    selected.mcotxt_top4_rank_hits = normal.top4_rank_hits
    return selected


def main() -> int:
    ap = argparse.ArgumentParser(description="Benchmark MCOtxt v1 A/B cost using trainer debug JSON models")
    ap.add_argument("--model-a", required=True, help="First model debug JSON, e.g. model_ru_debug.json")
    ap.add_argument("--model-b", required=True, help="Second model debug JSON, e.g. model_en_debug.json")
    ap.add_argument("--input", required=True, nargs="+", help="TXT/JSONL files, dirs, or globs")
    ap.add_argument("--format", choices=("auto", "lines", "text", "jsonl"), default="auto")
    ap.add_argument("--jsonl-field", default="text")
    ap.add_argument("--top", type=int, default=10, help="Show N most expensive messages by encoded bits")
    ap.add_argument(
        "--validation-only",
        action="store_true",
        help="Benchmark only messages in the trainer's deterministic validation hold-out",
    )
    ap.add_argument("--validation-ratio", type=float, default=0.20)
    ap.add_argument("--split-seed", default="mcotxt-v1")
    ap.add_argument(
        "--mixed-only",
        action="store_true",
        help="Only include messages that contain language-specific symbols from both models",
    )
    args = ap.parse_args()

    a = load_model(Path(args.model_a))
    b = load_model(Path(args.model_b))
    paths = expand_paths(args.input)
    if not paths:
        raise SystemExit("No input files found")

    total_messages = 0
    total_bits = 0
    total_payload_bytes = 0
    forced_mcotxt_bits = 0
    forced_mcotxt_bytes = 0
    forced_raw_utf8_bits = 0
    forced_raw_utf8_bytes = 0
    total_chars = 0
    total_utf8 = 0
    total_skipped = 0
    total_utf8_fallback_runs = 0
    total_utf8_fallback_codepoints = 0
    total_utf8_fallback_bytes = 0
    total_utf8_fallback_bits = 0
    total_toggles = 0
    total_case_toggles = 0
    total_shifts = 0
    mcotxt_case_toggles = 0
    mcotxt_shifts = 0
    mcotxt_utf8_runs = 0
    mcotxt_rank_hits = [0, 0, 0, 0]
    messages_with_toggle = 0
    mixed_messages = 0
    raw_messages = 0
    initial_counts = {a.code: 0, b.code: 0}
    expensive = []

    for source, text in iter_messages(paths, args.format, args.jsonl_field):
        if args.validation_only and not is_validation_message(
            text, args.validation_ratio, args.split_seed
        ):
            continue

        r = best_message(text, a, b)
        if args.mixed_only and not r.mixed:
            continue

        total_messages += 1
        total_bits += r.bits
        total_payload_bytes += r.payload_bytes
        forced_mcotxt_bits += r.mcotxt_candidate_bits
        forced_mcotxt_bytes += r.mcotxt_candidate_bytes
        forced_raw_utf8_bits += r.raw_utf8_candidate_bits
        forced_raw_utf8_bytes += r.raw_utf8_candidate_bytes
        total_chars += r.output_chars
        total_utf8 += r.output_utf8_bytes
        total_skipped += r.skipped_chars
        total_utf8_fallback_runs += r.utf8_fallback_runs
        total_utf8_fallback_codepoints += r.utf8_fallback_codepoints
        total_utf8_fallback_bytes += r.utf8_fallback_bytes
        total_utf8_fallback_bits += r.utf8_fallback_bits
        total_toggles += r.toggles
        total_case_toggles += r.case_toggles
        total_shifts += r.shifts
        mcotxt_case_toggles += r.mcotxt_case_toggles
        mcotxt_shifts += r.mcotxt_shifts
        mcotxt_utf8_runs += r.mcotxt_utf8_runs
        for rank in range(4):
            mcotxt_rank_hits[rank] += r.mcotxt_top4_rank_hits[rank]
        messages_with_toggle += int(r.toggles > 0)
        mixed_messages += int(r.mixed)
        raw_messages += int(r.mode == "rawUtf8")
        if r.initial_language in initial_counts:
            initial_counts[r.initial_language] += 1
        expensive.append((r.bits, r.payload_bytes, r.toggles, r.case_toggles, r.mode, text, source))

    expensive.sort(reverse=True, key=lambda x: (x[1], x[0], x[2], x[3]))

    scope = "validation hold-out" if args.validation_only else "all input messages"
    if args.mixed_only:
        scope += ", mixed only"
    print(f"MCOtxt v1 A/B benchmark: {a.code.upper()} + {b.code.upper()} ({scope})")
    print(f"  files:                    {len(paths)}")
    print(f"  messages:                 {total_messages}")
    print(f"  output chars:             {total_chars}")
    print(f"  skipped unsupported:      {total_skipped}")
    print(f"  UTF-8 fallback runs:      {total_utf8_fallback_runs}")
    print(f"  UTF-8 fallback codepoints: {total_utf8_fallback_codepoints}")
    print(f"  UTF-8 fallback bytes:     {total_utf8_fallback_bytes}")
    print(f"  UTF-8 fallback bits:      {total_utf8_fallback_bits}")
    print(f"  output UTF-8 bytes:       {total_utf8}")
    print(f"  optimized MCOtxt bits:       {forced_mcotxt_bits}")
    print(f"  optimized MCOtxt bytes:      {forced_mcotxt_bytes}")
    print(f"  forced RAW_UTF8 bits:     {forced_raw_utf8_bits}")
    print(f"  forced RAW_UTF8 bytes:    {forced_raw_utf8_bytes}")
    print(f"  selected bits:            {total_bits}")
    print(f"  selected bytes:           {total_payload_bytes}")
    print(f"  saved vs optimized MCOtxt:   {forced_mcotxt_bytes - total_payload_bytes} bytes")
    if total_chars:
        print(f"  bits/output char:         {total_bits / total_chars:.4f}")
    if total_utf8:
        print(f"  ratio vs UTF-8 bits:      {(total_utf8 * 8) / total_bits:.4f}x")
    print(f"  language toggles:         {total_toggles}")
    print(f"  selected CAPS toggles:    {total_case_toggles}")
    print(f"  selected SHIFT tokens:    {total_shifts}")
    print(f"  MCOtxt CAPS toggles:      {mcotxt_case_toggles}")
    print(f"  MCOtxt SHIFT tokens:      {mcotxt_shifts}")
    print(f"  MCOtxt fallback UTF8_RUNs:   {mcotxt_utf8_runs}")
    rank_total = sum(mcotxt_rank_hits)
    if rank_total:
        rank_text = ", ".join(
            f"r{rank}={mcotxt_rank_hits[rank]} ({mcotxt_rank_hits[rank] / rank_total * 100:.2f}%)"
            for rank in range(4)
        )
        print(f"  MCOtxt TOP4 ranks:        {rank_text}")
    print(f"  messages with toggle:     {messages_with_toggle}")
    print(f"  mixed-language messages:  {mixed_messages}")
    print(f"  RAW_UTF8 messages:        {raw_messages}")
    print(f"  initial {a.code}:                {initial_counts[a.code]}")
    print(f"  initial {b.code}:                {initial_counts[b.code]}")
    print("")
    print(f"Top {min(args.top, len(expensive))} messages by selected payload size:")
    for bits, payload_bytes, toggles, case_toggles, mode, text, source in expensive[:args.top]:
        preview = text.replace("\n", "\\n")
        if len(preview) > 140:
            preview = preview[:137] + "..."
        print(f"  {payload_bytes:4d} bytes  {bits:5d} bits  {mode:7s}  lang={toggles:2d} caps={case_toggles:2d}  {preview!r}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
