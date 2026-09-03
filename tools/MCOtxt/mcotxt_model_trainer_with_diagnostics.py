#!/usr/bin/env python3
"""
MCOtxt v1 static TOP-4 model trainer / exporter.

Builds a per-language static model from UTF-8 corpora and exports:
  * Dart model source (runtime-compatible codepoint tables + compact index tables)
  * C/C++ header for nRF (TOP-4 stored as uint8 symbol indexes)
  * Markdown validation report
  * optional JSON debug artifact

No ML framework is used. Training is deterministic counting of symbol frequencies
and previous-symbol -> next-symbol transitions.

The trainer intentionally does NOT use str.lower()/casefold(). Case normalization is
performed only through language-specific, explicitly defined one-codepoint mappings.
Unicode NFC normalization uses Python's unicodedata database; its version is written
into the report for reproducibility.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import glob
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import re
import sys
import unicodedata
from typing import Counter, DefaultDict, Dict, Iterable, Iterator, List, Mapping, MutableMapping, Optional, Sequence, Tuple


# ---------------------------------------------------------------------------
# MCOtxt v1 wire constants
# ---------------------------------------------------------------------------

MCOTXT_VERSION = 1
SPACE = 0x0020
LF = 0x000A

# Source-of-truth fallback copied from the MCOtxt v1 specification discussed for
# the codec. When possible, pass --punctuation-dart pointing at the actual
# lib/mcotxt/models/punctuation.dart; the trainer will verify that the Dart file
# contains an equivalent 32-codepoint list and will fail on mismatch.
PUNCTUATION_V1: Tuple[int, ...] = (
    0x0020,  #  0 SPACE
    0x002E,  #  1 .
    0x002C,  #  2 ,
    0x0021,  #  3 !
    0x003F,  #  4 ?
    0x003A,  #  5 :
    0x003B,  #  6 ;
    0x002D,  #  7 -
    0x2014,  #  8 —
    0x005F,  #  9 _
    0x0027,  # 10 '
    0x0022,  # 11 "
    0x00AB,  # 12 «
    0x00BB,  # 13 »
    0x201C,  # 14 “
    0x201D,  # 15 ”
    0x201E,  # 16 „
    0x2018,  # 17 ‘
    0x2019,  # 18 ’
    0x0028,  # 19 (
    0x0029,  # 20 )
    0x005B,  # 21 [
    0x005D,  # 22 ]
    0x002F,  # 23 /
    0x005C,  # 24 \
    0x0040,  # 25 @
    0x0023,  # 26 #
    0x0025,  # 27 %
    0x0026,  # 28 &
    0x002B,  # 29 +
    0x003D,  # 30 =
    0x000A,  # 31 LF
)

# Token costs from MCOtxt v1.
TOP4_BITS_BY_RANK = (2, 3, 4, 4)
BITS_SHIFT = 5
BITS_TOGGLE = 6
BITS_PRIMARY_LITERAL = 7
BITS_PUNCTUATION = 8
BITS_EXTENSION_LITERAL = 9
BITS_HEADER = 9  # VVV AAA BBB. Single-language validation uses B=NONE.
BITS_RAW_UTF8_HEADER = 16  # RAW_UTF8 mode header padded/aligned to 2 bytes.
BITS_CASE_MODE_TOGGLE = 9  # EXTENDED_CONTROL + TOGGLE_CASE_MODE subopcode.
BITS_UTF8_RUN_OVERHEAD = 14  # EXTENDED_CONTROL + subtype + lengthMinus1.
UTF8_RUN_MAX_BYTES = 32

# Diagnostics-only sentinel; Unicode codepoints are non-negative.
AFTER_PUNCT_SENTINEL = -1

def _top4_bits(rank: int) -> int:
    if rank < 0 or rank >= len(TOP4_BITS_BY_RANK):
        raise ValueError(f"invalid TOP4 rank: {rank}")
    return TOP4_BITS_BY_RANK[rank]


LANGUAGE_IDS: Mapping[str, int] = {
    "en": 0,
    "ru": 1,
    "fr": 2,
    "de": 3,
    "it": 4,
    "uk": 5,
    "be": 6,
}


# ---------------------------------------------------------------------------
# Explicit language definitions
# ---------------------------------------------------------------------------

@dataclasses.dataclass(frozen=True)
class LanguageDefinition:
    code: str
    wire_id: int
    lowercase_letters: Tuple[int, ...]
    uppercase_to_lowercase: Mapping[int, int]
    include_ascii_digits: bool = True

    @property
    def canonical_symbols(self) -> Tuple[int, ...]:
        # SPACE is always a language symbol. Digits are included because the
        # punctuation page intentionally has no digits and MCOtxt is expected
        # to carry technical/chat text (RSSI, dates, coordinates, etc.).
        symbols: List[int] = [SPACE]
        symbols.extend(self.lowercase_letters)
        if self.include_ascii_digits:
            symbols.extend(range(ord("0"), ord("9") + 1))
        # Preserve explicit language ordering while removing accidental dupes.
        return tuple(dict.fromkeys(symbols))


def _make_case_map(lower: str, upper: str) -> Dict[int, int]:
    if len(lower) != len(upper):
        raise ValueError(f"Case-map strings have different lengths: {lower!r} / {upper!r}")
    out: Dict[int, int] = {}
    for lo, up in zip(lower, upper):
        lo_cp = ord(lo)
        up_cp = ord(up)
        existing = out.get(up_cp)
        if existing is not None and existing != lo_cp:
            raise ValueError(f"Conflicting uppercase mapping for U+{up_cp:04X}")
        out[up_cp] = lo_cp
    return out


def _lang(code: str, lower: str, upper: str) -> LanguageDefinition:
    return LanguageDefinition(
        code=code,
        wire_id=LANGUAGE_IDS[code],
        lowercase_letters=tuple(ord(ch) for ch in lower),
        uppercase_to_lowercase=_make_case_map(lower, upper),
    )


# IMPORTANT: these are explicit one-codepoint mappings. Do not replace with
# Python str.lower()/casefold(): model reproducibility must not depend on locale
# or implicit multi-codepoint case transforms.
LANGUAGES: Mapping[str, LanguageDefinition] = {
    "en": _lang(
        "en",
        "abcdefghijklmnopqrstuvwxyz",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    ),
    "ru": _lang(
        "ru",
        "абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
        "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ",
    ),
    "fr": _lang(
        "fr",
        # Base Latin + common French precomposed letters/ligatures.
        "abcdefghijklmnopqrstuvwxyzàâæçéèêëîïôœùûüÿ",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸ",
    ),
    "de": _lang(
        "de",
        "abcdefghijklmnopqrstuvwxyzäöüß",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜẞ",
    ),
    "it": _lang(
        "it",
        # Includes the normal grave/acute accented vowels encountered in modern
        # Italian text. All still fit comfortably within 64 language symbols.
        "abcdefghijklmnopqrstuvwxyzàèéìíòóùú",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZÀÈÉÌÍÒÓÙÚ",
    ),
    "uk": _lang(
        "uk",
        "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя",
        "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ",
    ),
    "be": _lang(
        "be",
        "абвгдеёжзійклмнопрстуўфхцчшыьэюя",
        "АБВГДЕЁЖЗІЙКЛМНОПРСТУЎФХЦЧШЫЬЭЮЯ",
    ),
}


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclasses.dataclass
class CorpusStats:
    messages: int = 0
    source_utf8_bytes: int = 0
    normalized_codepoints: int = 0
    language_codepoints: int = 0
    uppercase_codepoints: int = 0
    punctuation_codepoints: int = 0
    unsupported_codepoints: int = 0
    global_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    start_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    punct_start_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    transitions: DefaultDict[int, collections.Counter[int]] = dataclasses.field(
        default_factory=lambda: collections.defaultdict(collections.Counter)
    )
    punctuation_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    unsupported_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)

    # Diagnostics only; these counters do not affect model construction.
    # A START transition means that a language symbol was encoded with
    # previous == START. The reason records why the context was START.
    start_reason_counts: collections.Counter[str] = dataclasses.field(default_factory=collections.Counter)
    start_target_by_reason: DefaultDict[str, collections.Counter[int]] = dataclasses.field(
        default_factory=lambda: collections.defaultdict(collections.Counter)
    )
    punct_start_trigger_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    message_begin_counts: collections.Counter[str] = dataclasses.field(default_factory=collections.Counter)


@dataclasses.dataclass(frozen=True)
class Model:
    language: LanguageDefinition
    primary: Tuple[int, ...]
    extension: Tuple[int, ...]
    symbols: Tuple[int, ...]
    symbol_to_index: Mapping[int, int]
    start_top4_indexes: Tuple[int, int, int, int]
    punct_start_top4_indexes: Tuple[int, int, int, int]
    top4_indexes: Tuple[int, ...]  # flattened: symbolCount * 4
    uppercase_to_lowercase: Mapping[int, int]
    primary_selection: str
    training_top4_hits: int
    training_language_symbols: int

    @property
    def symbol_count(self) -> int:
        return len(self.symbols)

    def start_top4_codepoints(self) -> Tuple[int, int, int, int]:
        return tuple(self.symbols[i] for i in self.start_top4_indexes)  # type: ignore[return-value]

    def punct_start_top4_codepoints(self) -> Tuple[int, int, int, int]:
        return tuple(self.symbols[i] for i in self.punct_start_top4_indexes)  # type: ignore[return-value]

    def top4_row_indexes(self, symbol_index: int) -> Tuple[int, int, int, int]:
        start = symbol_index * 4
        row = self.top4_indexes[start:start + 4]
        return tuple(row)  # type: ignore[return-value]

    def top4_row_codepoints(self, symbol_index: int) -> Tuple[int, int, int, int]:
        return tuple(self.symbols[i] for i in self.top4_row_indexes(symbol_index))  # type: ignore[return-value]


@dataclasses.dataclass
class EvalStats:
    messages: int = 0
    original_utf8_bytes: int = 0
    normalized_codepoints: int = 0
    output_codepoints: int = 0
    language_symbols: int = 0
    top4_hits: int = 0
    top4_rank_hits: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    primary_literals: int = 0
    extension_literals: int = 0
    punctuation_symbols: int = 0
    shifts: int = 0
    skipped: int = 0
    utf8_fallback_runs: int = 0
    utf8_fallback_codepoints: int = 0
    utf8_fallback_bytes: int = 0
    utf8_fallback_bits: int = 0
    token_bits: int = 0
    header_bits: int = 0
    decoded_utf8_bytes: int = 0

    # Final message-level candidate simulation. These fields do NOT replace the
    # model-only metrics above: token_bits/header_bits/total_bits continue to
    # describe forced normal MCOtxt encoding so model quality remains comparable.
    mcotxt_candidate_bits: int = 0
    mcotxt_candidate_bytes: int = 0
    raw_utf8_candidate_bits: int = 0
    raw_utf8_candidate_bytes: int = 0
    selected_bits: int = 0
    selected_bytes: int = 0
    selected_mcotxt_messages: int = 0
    selected_raw_utf8_messages: int = 0
    optimized_case_mode_toggles: int = 0
    optimized_shifts: int = 0
    optimized_utf8_runs: int = 0
    unsupported_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)

    # Diagnostics only.
    start_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    punct_start_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    start_reason_counts: collections.Counter[str] = dataclasses.field(default_factory=collections.Counter)
    start_target_by_reason: DefaultDict[str, collections.Counter[int]] = dataclasses.field(
        default_factory=lambda: collections.defaultdict(collections.Counter)
    )
    punct_start_trigger_counts: collections.Counter[int] = dataclasses.field(default_factory=collections.Counter)
    message_begin_counts: collections.Counter[str] = dataclasses.field(default_factory=collections.Counter)
    # Key = (previous codepoint, None for START, or AFTER_PUNCT_SENTINEL, target codepoint).
    top4_miss_counts: collections.Counter[Tuple[Optional[int], int]] = dataclasses.field(
        default_factory=collections.Counter
    )

    @property
    def total_bits(self) -> int:
        return self.token_bits + self.header_bits

    @property
    def top4_hit_rate(self) -> float:
        return self.top4_hits / self.language_symbols if self.language_symbols else 0.0

    @property
    def bits_per_output_char_tokens(self) -> float:
        return self.token_bits / self.output_codepoints if self.output_codepoints else 0.0

    @property
    def bits_per_output_char_total(self) -> float:
        return self.total_bits / self.output_codepoints if self.output_codepoints else 0.0

    @property
    def ratio_vs_decoded_utf8(self) -> float:
        if self.total_bits == 0:
            return math.inf if self.decoded_utf8_bytes else 1.0
        return (self.decoded_utf8_bytes * 8) / self.total_bits


    @property
    def selector_savings_bytes_vs_mcotxt(self) -> int:
        return self.mcotxt_candidate_bytes - self.selected_bytes

    @property
    def selected_ratio_vs_normalized_utf8(self) -> float:
        if self.selected_bits == 0:
            return math.inf if self.decoded_utf8_bytes else 1.0
        return (self.decoded_utf8_bytes * 8) / self.selected_bits


# ---------------------------------------------------------------------------
# Input handling
# ---------------------------------------------------------------------------

def _expand_paths(items: Sequence[str]) -> List[Path]:
    found: List[Path] = []
    seen: set[Path] = set()
    for raw in items:
        expanded = glob.glob(raw, recursive=True)
        candidates = [Path(p) for p in expanded] if expanded else [Path(raw)]
        for candidate in candidates:
            if candidate.is_dir():
                for path in sorted(p for p in candidate.rglob("*") if p.is_file()):
                    rp = path.resolve()
                    if rp not in seen:
                        seen.add(rp)
                        found.append(path)
            elif candidate.is_file():
                rp = candidate.resolve()
                if rp not in seen:
                    seen.add(rp)
                    found.append(candidate)
            else:
                raise FileNotFoundError(f"Input path does not exist: {candidate}")
    if not found:
        raise FileNotFoundError("No corpus files found")
    return found


def _detect_format(path: Path, requested: str) -> str:
    if requested != "auto":
        return requested
    if path.suffix.lower() in {".jsonl", ".ndjson"}:
        return "jsonl"
    return "lines"


def iter_messages_from_file(path: Path, input_format: str, jsonl_field: str) -> Iterator[str]:
    fmt = _detect_format(path, input_format)
    if fmt == "text":
        yield path.read_text(encoding="utf-8-sig")
        return

    with path.open("r", encoding="utf-8-sig", newline=None) as fh:
        if fmt == "lines":
            # Every physical line is one message. Newline separators are not part
            # of messages; use JSONL or --format text for embedded LF training.
            for line in fh:
                yield line.rstrip("\r\n")
            return

        if fmt == "jsonl":
            for line_no, line in enumerate(fh, 1):
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    obj = json.loads(stripped)
                except json.JSONDecodeError as exc:
                    raise ValueError(f"{path}:{line_no}: invalid JSONL: {exc}") from exc
                if not isinstance(obj, dict) or jsonl_field not in obj:
                    raise ValueError(f"{path}:{line_no}: expected object with field {jsonl_field!r}")
                text = obj[jsonl_field]
                if not isinstance(text, str):
                    raise ValueError(f"{path}:{line_no}: field {jsonl_field!r} must be a string")
                yield text
            return

    raise ValueError(f"Unsupported input format: {fmt}")


def iter_messages(paths: Sequence[Path], input_format: str, jsonl_field: str) -> Iterator[Tuple[Path, int, str]]:
    for path in paths:
        for idx, text in enumerate(iter_messages_from_file(path, input_format, jsonl_field)):
            yield path, idx, text


def _is_validation_message(text: str, ratio: float, seed: str) -> bool:
    if ratio <= 0.0:
        return False
    if ratio >= 1.0:
        return True
    digest = hashlib.sha256(seed.encode("utf-8") + b"\0" + text.encode("utf-8")).digest()
    value = int.from_bytes(digest[:8], "big") / float(1 << 64)
    return value < ratio


# ---------------------------------------------------------------------------
# Normalization and statistics
# ---------------------------------------------------------------------------

def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return unicodedata.normalize("NFC", text)


def _language_symbol(cp: int, lang: LanguageDefinition, allowed: set[int]) -> Tuple[Optional[int], bool]:
    mapped = lang.uppercase_to_lowercase.get(cp)
    if mapped is not None:
        return (mapped if mapped in allowed else None), True
    if cp in allowed:
        return cp, False
    return None, False


def _is_symbol_of_other_language(cp: int, current_lang: LanguageDefinition) -> bool:
    """True when cp is a language symbol of another built-in MCOtxt profile.

    This is diagnostics only. It does not change training semantics.
    """
    for code, other in LANGUAGES.items():
        if code == current_lang.code:
            continue
        allowed = set(other.canonical_symbols)
        symbol, _ = _language_symbol(cp, other, allowed)
        if symbol is not None:
            return True
    return False


def _classify_message_begin(
    text: str,
    lang: LanguageDefinition,
    allowed: set[int],
    punctuation: set[int],
) -> str:
    if not text:
        return "empty"
    cp = ord(text[0])
    symbol, _ = _language_symbol(cp, lang, allowed)
    if symbol is not None:
        if cp == SPACE:
            return "space"
        return "language_symbol"
    if cp == LF:
        return "newline"
    if cp in punctuation:
        return "punctuation"
    if _is_symbol_of_other_language(cp, lang):
        return "foreign_language"
    return "unsupported"


def collect_stats_from_messages(
    messages: Iterable[str],
    lang: LanguageDefinition,
) -> CorpusStats:
    stats = CorpusStats()
    allowed = set(lang.canonical_symbols)
    punctuation = set(PUNCTUATION_V1)

    for original in messages:
        stats.messages += 1
        stats.source_utf8_bytes += len(original.encode("utf-8"))
        text = normalize_text(original)
        stats.normalized_codepoints += len(text)
        stats.message_begin_counts[_classify_message_begin(text, lang, allowed, punctuation)] += 1

        # Explicit prediction context matching the MCOtxt v1 runtime.
        context = "start"
        previous: Optional[int] = None
        start_reason = "message_start"
        punct_trigger: Optional[int] = None

        for ch in text:
            cp = ord(ch)
            symbol, was_upper = _language_symbol(cp, lang, allowed)
            if symbol is not None:
                stats.language_codepoints += 1
                if was_upper:
                    stats.uppercase_codepoints += 1
                stats.global_counts[symbol] += 1

                if context == "start":
                    stats.start_counts[symbol] += 1
                    stats.start_reason_counts[start_reason] += 1
                    stats.start_target_by_reason[start_reason][symbol] += 1
                elif context == "after_punct":
                    stats.punct_start_counts[symbol] += 1
                    if punct_trigger is not None:
                        stats.punct_start_trigger_counts[punct_trigger] += 1
                else:
                    assert previous is not None
                    stats.transitions[previous][symbol] += 1

                previous = symbol
                context = "symbol"
                punct_trigger = None
                continue

            if cp in punctuation:
                stats.punctuation_codepoints += 1
                stats.punctuation_counts[cp] += 1
                if cp == SPACE:
                    continue  # defensive: SPACE normally matched above
                if cp == LF:
                    context = "start"
                    previous = None
                    start_reason = "newline"
                    punct_trigger = None
                else:
                    context = "after_punct"
                    previous = None
                    punct_trigger = cp
                continue

            stats.unsupported_codepoints += 1
            stats.unsupported_counts[cp] += 1
            # Runtime encodes unsupported symbols as UTF8_RUN. They do not train
            # language transitions and reset prediction context to START.
            context = "start"
            previous = None
            start_reason = "utf8_fallback"
            punct_trigger = None

    return stats


# ---------------------------------------------------------------------------
# Model building
# ---------------------------------------------------------------------------

def _rank_candidates(
    candidates: Sequence[int],
    local_counts: Mapping[int, int],
    global_counts: Mapping[int, int],
) -> List[int]:
    # Required deterministic tie-break:
    #   1) transition/start frequency
    #   2) global symbol frequency
    #   3) smaller Unicode codepoint
    return sorted(
        candidates,
        key=lambda cp: (-local_counts.get(cp, 0), -global_counts.get(cp, 0), cp),
    )


def _pick_top4(
    candidates: Sequence[int],
    local_counts: Mapping[int, int],
    global_counts: Mapping[int, int],
) -> Tuple[int, int, int, int]:
    if len(candidates) < 4:
        raise ValueError("MCOtxt TOP-4 model requires at least four language symbols")
    ranked = _rank_candidates(candidates, local_counts, global_counts)
    return tuple(ranked[:4])  # type: ignore[return-value]


def _build_prediction_codepoints(
    lang: LanguageDefinition,
    stats: CorpusStats,
) -> Tuple[
    Tuple[int, int, int, int],
    Tuple[int, int, int, int],
    Dict[int, Tuple[int, int, int, int]],
]:
    symbols = lang.canonical_symbols
    start = _pick_top4(symbols, stats.start_counts, stats.global_counts)
    punct_start = _pick_top4(symbols, stats.punct_start_counts, stats.global_counts)
    rows: Dict[int, Tuple[int, int, int, int]] = {}
    for previous in symbols:
        rows[previous] = _pick_top4(symbols, stats.transitions.get(previous, {}), stats.global_counts)
    return start, punct_start, rows


def _training_hits_by_target(
    lang: LanguageDefinition,
    stats: CorpusStats,
    start_top4: Tuple[int, int, int, int],
    punct_start_top4: Tuple[int, int, int, int],
    top4_rows: Mapping[int, Tuple[int, int, int, int]],
) -> collections.Counter[int]:
    hits: collections.Counter[int] = collections.Counter()
    start_set = set(start_top4)
    for target, count in stats.start_counts.items():
        if target in start_set:
            hits[target] += count
    punct_set = set(punct_start_top4)
    for target, count in stats.punct_start_counts.items():
        if target in punct_set:
            hits[target] += count
    for previous, row_counts in stats.transitions.items():
        row_set = set(top4_rows[previous])
        for target, count in row_counts.items():
            if target in row_set:
                hits[target] += count
    return hits


def build_model(
    lang: LanguageDefinition,
    stats: CorpusStats,
    primary_selection: str,
) -> Model:
    canonical = lang.canonical_symbols
    if len(canonical) > 64:
        raise ValueError(
            f"Language {lang.code} has {len(canonical)} canonical symbols; "
            "MCOtxt v1 supports at most 32 primary + 32 extension = 64"
        )
    if SPACE not in canonical:
        raise ValueError("SPACE must be part of the canonical language alphabet")

    start_cp, punct_start_cp, rows_cp = _build_prediction_codepoints(lang, stats)
    hits_by_target = _training_hits_by_target(
        lang, stats, start_cp, punct_start_cp, rows_cp
    )

    def primary_key(cp: int) -> Tuple[int, int, int]:
        freq = stats.global_counts.get(cp, 0)
        misses = freq - hits_by_target.get(cp, 0)
        if primary_selection == "frequency":
            return (-freq, 0, cp)
        # Each non-TOP4 occurrence saves exactly 2 bits when the symbol is
        # primary (7-bit literal) instead of extension (9-bit literal).
        return (-misses, -freq, cp)

    remaining = [cp for cp in canonical if cp != SPACE]
    ranked = sorted(remaining, key=primary_key)
    primary = tuple([SPACE] + ranked[:31])
    extension = tuple(ranked[31:])

    symbols = primary + extension
    symbol_to_index = {cp: idx for idx, cp in enumerate(symbols)}

    start_idx = tuple(symbol_to_index[cp] for cp in start_cp)
    punct_start_idx = tuple(symbol_to_index[cp] for cp in punct_start_cp)
    top4_flat: List[int] = []
    for cp in symbols:
        top4_flat.extend(symbol_to_index[nxt] for nxt in rows_cp[cp])

    uppercase = {
        upper: lower
        for upper, lower in lang.uppercase_to_lowercase.items()
        if lower in symbol_to_index
    }

    model = Model(
        language=lang,
        primary=primary,
        extension=extension,
        symbols=symbols,
        symbol_to_index=symbol_to_index,
        start_top4_indexes=tuple(start_idx),  # type: ignore[arg-type]
        punct_start_top4_indexes=tuple(punct_start_idx),  # type: ignore[arg-type]
        top4_indexes=tuple(top4_flat),
        uppercase_to_lowercase=uppercase,
        primary_selection=primary_selection,
        training_top4_hits=sum(hits_by_target.values()),
        training_language_symbols=sum(stats.global_counts.values()),
    )
    validate_model(model)
    return model


def validate_model(model: Model) -> None:
    errors: List[str] = []
    if not (1 <= len(model.primary) <= 32):
        errors.append(f"primary count must be 1..32, got {len(model.primary)}")
    if len(model.extension) > 32:
        errors.append(f"extension count must be <=32, got {len(model.extension)}")
    if SPACE not in model.primary:
        errors.append("SPACE U+0020 is missing from primary")
    if len(set(model.primary)) != len(model.primary):
        errors.append("primary contains duplicates")
    if len(set(model.extension)) != len(model.extension):
        errors.append("extension contains duplicates")
    if set(model.primary) & set(model.extension):
        errors.append("primary and extension overlap")
    if model.symbol_count != len(model.primary) + len(model.extension):
        errors.append("symbol count mismatch")
    if model.symbol_count > 64:
        errors.append("symbol count exceeds 64")
    if model.symbol_count < 4:
        errors.append("symbol count is below 4")
    if len(model.start_top4_indexes) != 4:
        errors.append("startTop4 must contain exactly 4 indexes")
    if len(set(model.start_top4_indexes)) != 4:
        errors.append("startTop4 contains duplicate indexes")
    if len(model.punct_start_top4_indexes) != 4:
        errors.append("punctStartTop4 must contain exactly 4 indexes")
    if len(set(model.punct_start_top4_indexes)) != 4:
        errors.append("punctStartTop4 contains duplicate indexes")
    if len(model.top4_indexes) != model.symbol_count * 4:
        errors.append("flattened top4 length mismatch")

    for idx in model.start_top4_indexes:
        if not (0 <= idx < model.symbol_count):
            errors.append(f"invalid startTop4 index {idx}")
    for idx in model.punct_start_top4_indexes:
        if not (0 <= idx < model.symbol_count):
            errors.append(f"invalid punctStartTop4 index {idx}")
    for idx in model.top4_indexes:
        if not (0 <= idx < model.symbol_count):
            errors.append(f"invalid top4 index {idx}")
    for row in range(model.symbol_count):
        indexes = model.top4_row_indexes(row)
        if len(set(indexes)) != 4:
            errors.append(f"TOP-4 row {row} contains duplicates: {indexes}")

    for cp in model.symbols:
        if not (0 <= cp <= 0xFFFF):
            errors.append(f"U+{cp:X} does not fit uint16_t")
    for upper, lower in model.uppercase_to_lowercase.items():
        if not (0 <= upper <= 0xFFFF):
            errors.append(f"uppercase U+{upper:X} does not fit uint16_t")
        if lower not in model.symbol_to_index:
            errors.append(f"case-map lowercase U+{lower:04X} is not in model symbols")

    # Only SPACE is intentionally shared with the punctuation page.
    overlap = (set(model.symbols) & set(PUNCTUATION_V1)) - {SPACE}
    if overlap:
        rendered = ", ".join(f"U+{cp:04X}" for cp in sorted(overlap))
        errors.append(f"language symbols overlap punctuation page: {rendered}")

    if errors:
        raise ValueError("Invalid generated model:\n  - " + "\n  - ".join(errors))


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

def _is_eval_supported(cp: int, model: Model, allowed: set[int], punctuation: set[int]) -> bool:
    if cp in punctuation:
        return True
    symbol, _ = _language_symbol(cp, model.language, allowed)
    return symbol is not None


def _utf8_fallback_run(
    chars: Sequence[str],
    start: int,
    model: Model,
    allowed: set[int],
    punctuation: set[int],
) -> Tuple[int, int, str]:
    data = bytearray()
    codepoints = 0
    i = start
    while i < len(chars):
        cp = ord(chars[i])
        if _is_eval_supported(cp, model, allowed, punctuation):
            break
        encoded = chars[i].encode("utf-8")
        if data and len(data) + len(encoded) > UTF8_RUN_MAX_BYTES:
            break
        data.extend(encoded)
        codepoints += 1
        i += 1
        if len(data) == UTF8_RUN_MAX_BYTES:
            break
    if codepoints == 0:
        encoded = chars[start].encode("utf-8")
        data.extend(encoded)
        codepoints = 1
    return codepoints, len(data), "".join(chars[start:start + codepoints])


@dataclasses.dataclass(frozen=True)
class _OptimizedCost:
    bits: int
    tokens: int = 0
    case_toggles: int = 0
    shifts: int = 0
    utf8_runs: int = 0
    top4_hits: int = 0


def _better_optimized_cost(a: _OptimizedCost, b: Optional[_OptimizedCost]) -> bool:
    if b is None:
        return True
    return (a.bits, a.tokens, -a.top4_hits, a.case_toggles, a.shifts, a.utf8_runs) < (
        b.bits, b.tokens, -b.top4_hits, b.case_toggles, b.shifts, b.utf8_runs
    )


def _build_single_language_case_plan(text: str, model: Model) -> Tuple[set[int], set[int]]:
    """Return (toggle_before_positions, shift_positions) using a tiny 2-state DP.

    Case control is independent of TOP4/literal/context costs because both
    CAPS_MODE and SHIFT only change reconstructed case, never the normalized
    lowercase symbol that drives prediction. Unsupported characters are ignored
    here because they are carried by UTF8_RUN fallback.
    """
    allowed = set(model.symbols)
    positions: List[int] = []
    wants_upper: List[bool] = []
    for pos, ch in enumerate(text):
        symbol, was_upper = _language_symbol(ord(ch), model.language, allowed)
        if symbol is None or symbol not in model.uppercase_to_lowercase.values():
            continue
        positions.append(pos)
        wants_upper.append(was_upper)

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
                    prev[0] + (BITS_CASE_MODE_TOGGLE if toggled else 0) + (BITS_SHIFT if shifted else 0),
                    prev[1] + int(toggled),
                    prev[2] + int(shifted),
                )
                if better(cand, nxt[next_state]):
                    nxt[next_state] = cand
                    decisions[next_state] = (prev_state, toggled, shifted)
        previous = nxt
        backtrack.append(decisions)

    state = 0 if better(previous[0], previous[1]) else 1
    toggle_positions: set[int] = set()
    shift_positions: set[int] = set()
    for i in range(len(positions) - 1, -1, -1):
        decision = backtrack[i][state]
        assert decision is not None
        prev_state, toggled, shifted = decision
        if toggled:
            toggle_positions.add(positions[i])
        if shifted:
            shift_positions.add(positions[i])
        state = prev_state
    return toggle_positions, shift_positions


def _optimized_single_language_mcotxt_cost(text: str, model: Model) -> _OptimizedCost:
    """Single-language v1 runtime cost with cheap CAPS plan and fallback UTF8_RUN."""
    chars = list(text)
    punctuation = set(PUNCTUATION_V1)
    primary = set(model.primary)
    extension = set(model.extension)
    allowed = set(model.symbols)
    toggle_positions, shift_positions = _build_single_language_case_plan(text, model)
    memo: Dict[Tuple[int, str, Optional[int]], _OptimizedCost] = {}

    def add(a: _OptimizedCost, b: _OptimizedCost) -> _OptimizedCost:
        return _OptimizedCost(
            bits=a.bits + b.bits,
            tokens=a.tokens + b.tokens,
            case_toggles=a.case_toggles + b.case_toggles,
            shifts=a.shifts + b.shifts,
            utf8_runs=a.utf8_runs + b.utf8_runs,
            top4_hits=a.top4_hits + b.top4_hits,
        )

    def best_from(pos: int, context: str, previous: Optional[int]) -> _OptimizedCost:
        if pos >= len(chars):
            return _OptimizedCost(0)
        key = (pos, context, previous)
        cached = memo.get(key)
        if cached is not None:
            return cached
        cp = ord(chars[pos])
        best: Optional[_OptimizedCost] = None

        if cp in punctuation:
            if cp == LF:
                next_context, next_previous = "start", None
            elif cp == SPACE and context == "symbol" and previous is not None:
                next_context, next_previous = "symbol", previous
            elif cp == SPACE:
                next_context, next_previous = "start", None
            else:
                next_context, next_previous = "after_punct", None
            cand = add(
                _OptimizedCost(BITS_PUNCTUATION, tokens=1),
                best_from(pos + 1, next_context, next_previous),
            )
            if _better_optimized_cost(cand, best):
                best = cand

        symbol, _was_upper = _language_symbol(cp, model.language, allowed)
        if symbol is not None:
            symbol_index = model.symbol_to_index[symbol]
            if context == "start":
                row = model.start_top4_indexes
            elif context == "after_punct":
                row = model.punct_start_top4_indexes
            else:
                assert previous is not None
                row = model.top4_row_indexes(model.symbol_to_index[previous])
            if symbol_index in row:
                rank = row.index(symbol_index)
                base_bits, top4 = _top4_bits(rank), 1
            elif symbol in primary:
                base_bits, top4 = BITS_PRIMARY_LITERAL, 0
            elif symbol in extension:
                base_bits, top4 = BITS_EXTENSION_LITERAL, 0
            else:
                raise AssertionError("symbol is in neither primary nor extension")

            toggle = pos in toggle_positions
            shift = pos in shift_positions
            prefix = _OptimizedCost(
                bits=base_bits + (BITS_CASE_MODE_TOGGLE if toggle else 0) + (BITS_SHIFT if shift else 0),
                tokens=1 + int(toggle) + int(shift),
                case_toggles=int(toggle),
                shifts=int(shift),
                top4_hits=top4,
            )
            cand = add(prefix, best_from(pos + 1, "symbol", symbol))
            if _better_optimized_cost(cand, best):
                best = cand

        # UTF8_RUN is only the universal fallback. Do not compete against legal
        # language/punctuation encodings: that search was expensive for ~0.6%
        # RU gain and is unsuitable for the MCU encoder target.
        if best is None:
            run_codepoints, run_bytes, _run_text = _utf8_fallback_run(
                chars, pos, model, allowed, punctuation
            )
            prefix = _OptimizedCost(
                BITS_UTF8_RUN_OVERHEAD + run_bytes * 8,
                tokens=1,
                utf8_runs=1,
            )
            best = add(prefix, best_from(pos + run_codepoints, "start", None))

        memo[key] = best
        return best

    return best_from(0, "start", None)


def evaluate_messages(messages: Iterable[str], model: Model) -> EvalStats:
    result = EvalStats()
    punctuation = set(PUNCTUATION_V1)
    primary_set = set(model.primary)
    extension_set = set(model.extension)
    allowed = set(model.symbols)

    for original in messages:
        result.messages += 1
        result.original_utf8_bytes += len(original.encode("utf-8"))

        # Snapshot aggregate token bits so we can derive this message's exact
        # forced-MCOtxt cost after evaluation.
        message_token_bits_before = result.token_bits

        result.header_bits += BITS_HEADER
        text = normalize_text(original)
        result.normalized_codepoints += len(text)
        result.message_begin_counts[_classify_message_begin(text, model.language, allowed, punctuation)] += 1

        context = "start"
        previous: Optional[int] = None
        start_reason = "message_start"
        punct_trigger: Optional[int] = None
        decoded_chars: List[str] = []

        chars = list(text)
        index = 0
        while index < len(chars):
            ch = chars[index]
            cp = ord(ch)
            symbol, was_upper = _language_symbol(cp, model.language, allowed)
            if symbol is not None:
                result.language_symbols += 1
                result.output_codepoints += 1
                if was_upper:
                    result.shifts += 1
                    result.token_bits += BITS_SHIFT

                symbol_index = model.symbol_to_index[symbol]
                if context == "start":
                    row = model.start_top4_indexes
                    result.start_counts[symbol] += 1
                    result.start_reason_counts[start_reason] += 1
                    result.start_target_by_reason[start_reason][symbol] += 1
                    miss_previous: Optional[int] = None
                elif context == "after_punct":
                    row = model.punct_start_top4_indexes
                    result.punct_start_counts[symbol] += 1
                    if punct_trigger is not None:
                        result.punct_start_trigger_counts[punct_trigger] += 1
                    miss_previous = AFTER_PUNCT_SENTINEL
                else:
                    assert previous is not None
                    row = model.top4_row_indexes(model.symbol_to_index[previous])
                    miss_previous = previous

                predicted = symbol_index in row
                if predicted:
                    rank = row.index(symbol_index)
                    result.top4_hits += 1
                    result.top4_rank_hits[rank] += 1
                    result.token_bits += _top4_bits(rank)
                elif symbol in primary_set:
                    result.primary_literals += 1
                    result.token_bits += BITS_PRIMARY_LITERAL
                    result.top4_miss_counts[(miss_previous, symbol)] += 1
                elif symbol in extension_set:
                    result.extension_literals += 1
                    result.token_bits += BITS_EXTENSION_LITERAL
                    result.top4_miss_counts[(miss_previous, symbol)] += 1
                else:
                    raise AssertionError("symbol is in neither primary nor extension")

                decoded_chars.append(chr(cp if was_upper else symbol))
                previous = symbol
                context = "symbol"
                punct_trigger = None
                index += 1
                continue

            if cp in punctuation:
                result.punctuation_symbols += 1
                result.output_codepoints += 1
                result.token_bits += BITS_PUNCTUATION
                decoded_chars.append(chr(cp))
                if cp == SPACE:
                    continue
                if cp == LF:
                    context = "start"
                    previous = None
                    start_reason = "newline"
                    punct_trigger = None
                else:
                    context = "after_punct"
                    previous = None
                    punct_trigger = cp
                index += 1
                continue

            run_codepoints, run_bytes, run_text = _utf8_fallback_run(
                chars, index, model, allowed, punctuation
            )
            run_bits = BITS_UTF8_RUN_OVERHEAD + run_bytes * 8
            result.utf8_fallback_runs += 1
            result.utf8_fallback_codepoints += run_codepoints
            result.utf8_fallback_bytes += run_bytes
            result.utf8_fallback_bits += run_bits
            result.output_codepoints += run_codepoints
            result.token_bits += run_bits
            for fallback_ch in run_text:
                result.unsupported_counts[ord(fallback_ch)] += 1
            decoded_chars.append(run_text)
            context = "start"
            previous = None
            start_reason = "utf8_fallback"
            punct_trigger = None
            index += run_codepoints

        decoded_text = "".join(decoded_chars)
        decoded_bytes = len(decoded_text.encode("utf-8"))
        result.decoded_utf8_bytes += decoded_bytes

        # Final encoder candidate simulation:
        #   A) forced normal MCOtxt (including local UTF8_RUN fallback)
        #   B) whole-message RAW_UTF8
        #
        # Selection matches the reference benchmark:
        #   1) smaller physical payload byte count;
        #   2) smaller exact bit length;
        #   3) normal MCOtxt wins a complete tie.
        message_token_bits = result.token_bits - message_token_bits_before
        # message_token_bits remains the legacy/model-only diagnostic. Final
        # candidate selection follows the optimized runtime planner.
        optimized = _optimized_single_language_mcotxt_cost(text, model)
        mcotxt_bits = BITS_HEADER + optimized.bits
        mcotxt_bytes = math.ceil(mcotxt_bits / 8)
        result.optimized_case_mode_toggles += optimized.case_toggles
        result.optimized_shifts += optimized.shifts
        result.optimized_utf8_runs += optimized.utf8_runs

        normalized_utf8_bytes = len(text.encode("utf-8"))
        raw_bits = BITS_RAW_UTF8_HEADER + normalized_utf8_bytes * 8
        raw_bytes = math.ceil(raw_bits / 8)

        result.mcotxt_candidate_bits += mcotxt_bits
        result.mcotxt_candidate_bytes += mcotxt_bytes
        result.raw_utf8_candidate_bits += raw_bits
        result.raw_utf8_candidate_bytes += raw_bytes

        raw_wins = (
            raw_bytes < mcotxt_bytes
            or (raw_bytes == mcotxt_bytes and raw_bits < mcotxt_bits)
        )
        if raw_wins:
            result.selected_raw_utf8_messages += 1
            result.selected_bits += raw_bits
            result.selected_bytes += raw_bytes
        else:
            result.selected_mcotxt_messages += 1
            result.selected_bits += mcotxt_bits
            result.selected_bytes += mcotxt_bytes

    return result


# ---------------------------------------------------------------------------
# Punctuation verification
# ---------------------------------------------------------------------------

def _extract_dart_list_candidates(text: str) -> List[List[int]]:
    """Best-effort extraction of flat integer list literals from Dart source.

    This intentionally does not try to parse Dart. It identifies bracket blocks
    with exactly 32 integer literals (hex or decimal), then punctuation verifier
    compares them with PUNCTUATION_V1. If punctuation.dart uses expressions
    instead of literals, verification will fail with a useful message.
    """
    # Strip // and /* */ comments to prevent comment numbers from being parsed.
    no_block = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    clean = re.sub(r"//.*", "", no_block)

    candidates: List[List[int]] = []
    stack: List[int] = []
    for i, ch in enumerate(clean):
        if ch == "[":
            stack.append(i)
        elif ch == "]" and stack:
            start = stack.pop()
            block = clean[start + 1:i]
            if "[" in block or "]" in block:
                continue
            tokens = re.findall(r"(?<![A-Za-z0-9_])(?:0x[0-9A-Fa-f]+|\d+)(?![A-Za-z0-9_])", block)
            if len(tokens) == 32:
                values = [int(tok, 0) for tok in tokens]
                candidates.append(values)
    return candidates


def verify_punctuation_dart(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig")
    candidates = _extract_dart_list_candidates(text)
    expected = list(PUNCTUATION_V1)
    if expected in candidates:
        return

    if candidates:
        best = max(candidates, key=lambda c: sum(a == b for a, b in zip(c, expected)))
        mismatches = [
            f"#{i}: dart=U+{a:04X}, expected=U+{b:04X}"
            for i, (a, b) in enumerate(zip(best, expected))
            if a != b
        ]
        raise ValueError(
            f"{path}: no 32-entry literal list matches trainer PUNCTUATION_V1. "
            f"Closest candidate differs at {len(mismatches)} position(s):\n  "
            + "\n  ".join(mismatches[:20])
        )

    raise ValueError(
        f"{path}: could not find a flat 32-integer Dart list to verify. "
        "If punctuation.dart builds the list using expressions/constants, verify "
        "PUNCTUATION_V1 manually or adapt verify_punctuation_dart()."
    )


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def cp_hex(cp: int) -> str:
    return f"0x{cp:04X}"


def cp_label(cp: int) -> str:
    if cp == SPACE:
        visible = "SPACE"
    elif cp == LF:
        visible = "LF"
    else:
        ch = chr(cp)
        visible = ch if ch.isprintable() else ""
    try:
        name = unicodedata.name(chr(cp))
    except ValueError:
        name = "<unnamed>"
    return f"U+{cp:04X} {visible!r} {name}".strip()


def _wrap_numbers(values: Sequence[str], indent: str = "  ", width: int = 100) -> str:
    lines: List[str] = []
    current = indent
    for token in values:
        piece = token + ","
        if len(current) + len(piece) + 1 > width and current.strip():
            lines.append(current.rstrip())
            current = indent + piece + " "
        else:
            current += piece + " "
    if current.strip():
        lines.append(current.rstrip())
    return "\n".join(lines)


def _dart_int_list(values: Sequence[int], indent: str = "  ") -> str:
    return _wrap_numbers([cp_hex(v) for v in values], indent=indent)


def _dart_index_list(values: Sequence[int], indent: str = "  ") -> str:
    return _wrap_numbers([str(v) for v in values], indent=indent)


def _safe_identifier(code: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", code.lower())


def _camel(code: str) -> str:
    return "".join(part.capitalize() for part in re.split(r"[^A-Za-z0-9]+", code) if part)


# ---------------------------------------------------------------------------
# Export: Dart
# ---------------------------------------------------------------------------

def render_dart(model: Model, import_path: str, variable_name: Optional[str]) -> str:
    code = model.language.code
    camel = _camel(code)
    prefix = f"mcotxt{camel}"
    var_name = variable_name or f"mcotxtModel{camel}"

    start_cp = model.start_top4_codepoints()
    punct_start_cp = model.punct_start_top4_codepoints()
    top4_rows_cp = [model.top4_row_codepoints(i) for i in range(model.symbol_count)]

    lines: List[str] = []
    lines.append("// GENERATED FILE - DO NOT EDIT BY HAND.")
    lines.append(f"// MCOtxt v1 static TOP-4 model (START + AFTER_PUNCT): {code.upper()} (wire id {model.language.wire_id}).")
    lines.append(f"// Generated with Python Unicode database {unicodedata.unidata_version}.")
    lines.append("")
    if import_path:
        lines.append("// Package import is intentional: generated models may live outside lib/.")
        lines.append(f"import '{import_path}';")
        lines.append("")

    lines.append(f"const List<int> {prefix}PrimarySymbols = <int>[")
    lines.append(_dart_int_list(model.primary))
    lines.append("];")
    lines.append("")

    lines.append(f"const List<int> {prefix}ExtensionSymbols = <int>[")
    lines.append(_dart_int_list(model.extension))
    lines.append("];")
    lines.append("")

    # Compact indexes are exported for inspection/parity with nRF, even though
    # the current Dart runtime constructor described by the project expects
    # codepoints in startTop4/top4.
    lines.append(f"const List<int> {prefix}StartTop4Indexes = <int>[")
    lines.append(_dart_index_list(model.start_top4_indexes))
    lines.append("];")
    lines.append("")

    lines.append(f"const List<int> {prefix}PunctStartTop4Indexes = <int>[")
    lines.append(_dart_index_list(model.punct_start_top4_indexes))
    lines.append("];")
    lines.append("")

    lines.append(f"const List<int> {prefix}Top4Indexes = <int>[")
    lines.append(_dart_index_list(model.top4_indexes))
    lines.append("];")
    lines.append("")

    lines.append(f"const List<int> {prefix}StartTop4 = <int>[")
    lines.append(_dart_int_list(start_cp))
    lines.append("];")
    lines.append("")

    lines.append(f"const List<int> {prefix}PunctStartTop4 = <int>[")
    lines.append(_dart_int_list(punct_start_cp))
    lines.append("];")
    lines.append("")

    lines.append(f"const List<List<int>> {prefix}Top4 = <List<int>>[")
    for idx, row in enumerate(top4_rows_cp):
        symbol = model.symbols[idx]
        row_text = ", ".join(cp_hex(cp) for cp in row)
        lines.append(f"  <int>[{row_text}], // #{idx}: {cp_label(symbol)}")
    lines.append("];")
    lines.append("")

    lines.append(f"const Map<int, int> {prefix}UppercaseToLowercase = <int, int>{{")
    for upper, lower in sorted(model.uppercase_to_lowercase.items()):
        lines.append(f"  {cp_hex(upper)}: {cp_hex(lower)}, // {chr(upper)} -> {chr(lower)}")
    lines.append("};")
    lines.append("")

    lines.append(f"final McotxtLanguageModel {var_name} = McotxtLanguageModel(")
    lines.append(f"  id: McotxtLanguageId.{code},")
    lines.append(f"  primarySymbols: {prefix}PrimarySymbols,")
    lines.append(f"  extensionSymbols: {prefix}ExtensionSymbols,")
    lines.append(f"  startTop4: {prefix}StartTop4,")
    lines.append(f"  punctStartTop4: {prefix}PunctStartTop4,")
    lines.append(f"  top4: {prefix}Top4,")
    lines.append(f"  uppercaseToLowercase: {prefix}UppercaseToLowercase,")
    lines.append(");")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Export: C/C++ header
# ---------------------------------------------------------------------------

def render_c_header(model: Model) -> str:
    code = _safe_identifier(model.language.code)
    upper = code.upper()
    guard = f"MCOTXT_MODEL_{upper}_H"
    prefix = f"mcotxt_{code}"

    case_items = sorted(model.uppercase_to_lowercase.items())

    lines: List[str] = []
    lines.append("/* GENERATED FILE - DO NOT EDIT BY HAND. */")
    lines.append(f"/* MCOtxt v1 static TOP-4 model (START + AFTER_PUNCT): {upper} (wire id {model.language.wire_id}). */")
    lines.append(f"#ifndef {guard}")
    lines.append(f"#define {guard}")
    lines.append("")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.append("#ifndef MCOTXT_UPPERCASE_PAIR_T_DEFINED")
    lines.append("#define MCOTXT_UPPERCASE_PAIR_T_DEFINED")
    lines.append("#if defined(__GNUC__) || defined(__clang__)")
    lines.append("#define MCOTXT_PACKED __attribute__((packed))")
    lines.append("#else")
    lines.append("#define MCOTXT_PACKED")
    lines.append("#endif")
    lines.append("typedef struct MCOTXT_PACKED {")
    lines.append("  uint16_t uppercase_codepoint;")
    lines.append("  uint8_t lowercase_symbol_index;")
    lines.append("} mcotxt_uppercase_pair_t;")
    lines.append("#endif")
    lines.append("")

    lines.append(f"static const uint8_t {prefix}_language_id = {model.language.wire_id}u;")
    lines.append(f"static const uint8_t {prefix}_primary_count = {len(model.primary)}u;")
    lines.append(f"static const uint8_t {prefix}_extension_count = {len(model.extension)}u;")
    lines.append(f"static const uint8_t {prefix}_symbol_count = {model.symbol_count}u;")
    lines.append(f"static const uint8_t {prefix}_uppercase_count = {len(case_items)}u;")
    lines.append("")

    def c_array_u16(name: str, values: Sequence[int]) -> None:
        size = max(1, len(values))
        lines.append(f"static const uint16_t {name}[{size}] = {{")
        if values:
            lines.append(_wrap_numbers([f"0x{v:04X}u" for v in values], indent="  "))
        else:
            lines.append("  0u, /* empty table sentinel; count is zero */")
        lines.append("};")
        lines.append("")

    def c_array_u8(name: str, values: Sequence[int], forced_size: Optional[int] = None) -> None:
        size = forced_size if forced_size is not None else max(1, len(values))
        lines.append(f"static const uint8_t {name}[{size}] = {{")
        if values:
            lines.append(_wrap_numbers([f"{v}u" for v in values], indent="  "))
        else:
            lines.append("  0u, /* empty table sentinel; count is zero */")
        lines.append("};")
        lines.append("")

    c_array_u16(f"{prefix}_primary_symbols", model.primary)
    c_array_u16(f"{prefix}_extension_symbols", model.extension)
    c_array_u8(f"{prefix}_start_top4", model.start_top4_indexes, forced_size=4)
    c_array_u8(f"{prefix}_punct_start_top4", model.punct_start_top4_indexes, forced_size=4)
    c_array_u8(f"{prefix}_top4", model.top4_indexes, forced_size=model.symbol_count * 4)

    size = max(1, len(case_items))
    lines.append(f"static const mcotxt_uppercase_pair_t {prefix}_uppercase_map[{size}] = {{")
    if case_items:
        for upper_cp, lower_cp in case_items:
            lines.append(
                f"  {{ 0x{upper_cp:04X}u, {model.symbol_to_index[lower_cp]}u }}, "
                f"/* {chr(upper_cp)} -> {chr(lower_cp)} */"
            )
    else:
        lines.append("  { 0u, 0u }, /* empty table sentinel; count is zero */")
    lines.append("};")
    lines.append("")
    lines.append(f"#endif /* {guard} */")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Report / debug JSON
# ---------------------------------------------------------------------------

def _percent(value: float) -> str:
    return f"{value * 100:.2f}%"


def _fmt_float(value: float) -> str:
    if math.isinf(value):
        return "∞"
    return f"{value:.4f}"


def _symbol_table_rows(model: Model, train: CorpusStats) -> List[str]:
    rows = ["| idx | tier | symbol | codepoint | train count |", "|---:|---|---|---|---:|"]
    for idx, cp in enumerate(model.symbols):
        tier = "primary" if idx < len(model.primary) else "extension"
        symbol = "SPACE" if cp == SPACE else chr(cp).replace("|", "\\|")
        rows.append(f"| {idx} | {tier} | `{symbol}` | U+{cp:04X} | {train.global_counts.get(cp, 0)} |")
    return rows


def _md_symbol(cp: int) -> str:
    if cp == SPACE:
        return "SPACE"
    if cp == LF:
        return "LF"
    ch = chr(cp)
    if ch == "|":
        return "\\|"
    if ch == "`":
        return "\\`"
    return ch if ch.isprintable() else f"U+{cp:04X}"


def _start_reason_breakdown(
    target: int,
    by_reason: Mapping[str, Mapping[int, int]],
) -> str:
    parts: List[str] = []
    for reason in ("message_start", "punctuation_reset", "newline", "utf8_fallback", "foreign_span"):
        count = by_reason.get(reason, {}).get(target, 0)
        if count:
            parts.append(f"{reason}={count}")
    # Preserve any future/unknown reasons too.
    known = {"message_start", "punctuation_reset", "newline", "utf8_fallback", "foreign_span"}
    for reason in sorted(set(by_reason) - known):
        count = by_reason.get(reason, {}).get(target, 0)
        if count:
            parts.append(f"{reason}={count}")
    return ", ".join(parts) if parts else "—"


def _bit_breakdown_rows(validation: EvalStats) -> List[Tuple[str, int, int]]:
    top4_bits = sum(
        validation.top4_rank_hits.get(rank, 0) * _top4_bits(rank)
        for rank in range(4)
    )
    return [
        ("TOP-4 variable", validation.top4_hits, top4_bits),
        ("Primary literal", validation.primary_literals, validation.primary_literals * BITS_PRIMARY_LITERAL),
        ("Extension literal", validation.extension_literals, validation.extension_literals * BITS_EXTENSION_LITERAL),
        ("SHIFT", validation.shifts, validation.shifts * BITS_SHIFT),
        ("Punctuation", validation.punctuation_symbols, validation.punctuation_symbols * BITS_PUNCTUATION),
        ("UTF-8 fallback", validation.utf8_fallback_runs, validation.utf8_fallback_bits),
        ("Header", validation.messages, validation.header_bits),
    ]


def render_report(
    model: Model,
    train: CorpusStats,
    validation: EvalStats,
    validation_source: str,
    train_files: Sequence[Path],
    validation_files: Sequence[Path],
    max_unsupported: int,
    punctuation_verified: Optional[Path],
) -> str:
    train_hit_rate = (
        model.training_top4_hits / model.training_language_symbols
        if model.training_language_symbols else 0.0
    )

    lines: List[str] = []
    lines.append(f"# MCOtxt v1 model report — {model.language.code.upper()}")
    lines.append("")
    lines.append("## Build")
    lines.append("")
    lines.append(f"- Language wire ID: `{model.language.wire_id}`")
    lines.append(f"- Unicode database: `{unicodedata.unidata_version}`")
    lines.append(f"- Primary selection: `{model.primary_selection}`")
    lines.append(f"- Canonical language symbols: `{len(model.language.canonical_symbols)}`")
    lines.append(f"- Primary: `{len(model.primary)}`")
    lines.append(f"- Extension: `{len(model.extension)}`")
    lines.append(f"- Total model symbols: `{model.symbol_count}`")
    lines.append("- Prediction contexts: `START`, `AFTER_PUNCT`, `SYMBOL(previous)`")
    if punctuation_verified is not None:
        lines.append(f"- Punctuation table verified against: `{punctuation_verified}`")
    else:
        lines.append("- Punctuation table: built-in MCOtxt v1 fallback; **not verified against punctuation.dart in this run**")
    lines.append("")

    lines.append("## Training corpus")
    lines.append("")
    lines.append(f"- Files: `{len(train_files)}`")
    lines.append(f"- Messages: `{train.messages}`")
    lines.append(f"- UTF-8 bytes (message payloads): `{train.source_utf8_bytes}`")
    lines.append(f"- Normalized codepoints: `{train.normalized_codepoints}`")
    lines.append(f"- Language symbols: `{train.language_codepoints}`")
    lines.append(f"- Uppercase mapped: `{train.uppercase_codepoints}`")
    lines.append(f"- Punctuation: `{train.punctuation_codepoints}`")
    lines.append(f"- Unsupported: `{train.unsupported_codepoints}`")
    lines.append(f"- Training TOP-4 hit rate: `{_percent(train_hit_rate)}`")
    lines.append("")

    lines.append("## Validation")
    lines.append("")
    lines.append(f"- Source: `{validation_source}`")
    lines.append(f"- Explicit validation files: `{len(validation_files)}`")
    lines.append(f"- Messages: `{validation.messages}`")
    lines.append(f"- Original UTF-8 bytes: `{validation.original_utf8_bytes}`")
    lines.append(f"- Normalized codepoints: `{validation.normalized_codepoints}`")
    lines.append(f"- Output codepoints: `{validation.output_codepoints}`")
    lines.append(f"- Skipped unsupported: `{validation.skipped}`")
    lines.append(f"- UTF-8 fallback runs: `{validation.utf8_fallback_runs}`")
    lines.append(f"- UTF-8 fallback codepoints: `{validation.utf8_fallback_codepoints}`")
    lines.append(f"- UTF-8 fallback bytes: `{validation.utf8_fallback_bytes}`")
    lines.append(f"- UTF-8 fallback bits: `{validation.utf8_fallback_bits}`")
    lines.append(f"- Language symbols: `{validation.language_symbols}`")
    lines.append(f"- TOP-4 hits: `{validation.top4_hits}` (`{_percent(validation.top4_hit_rate)}`)")
    lines.append(f"- Primary literals: `{validation.primary_literals}`")
    lines.append(f"- Extension literals: `{validation.extension_literals}`")
    lines.append(f"- SHIFT tokens: `{validation.shifts}`")
    lines.append(f"- Punctuation tokens: `{validation.punctuation_symbols}`")
    lines.append(f"- Token bits: `{validation.token_bits}`")
    lines.append(f"- Header bits (9/message): `{validation.header_bits}`")
    lines.append(f"- Total bits: `{validation.total_bits}`")
    lines.append(f"- Bits/output-char, tokens only: `{_fmt_float(validation.bits_per_output_char_tokens)}`")
    lines.append(f"- Bits/output-char, incl. per-message header: `{_fmt_float(validation.bits_per_output_char_total)}`")
    lines.append(f"- UTF-8 bytes of the same decoded/supported text: `{validation.decoded_utf8_bytes}`")
    lines.append(f"- Compression ratio vs same decoded UTF-8: `{_fmt_float(validation.ratio_vs_decoded_utf8)}x`")
    lines.append("")
    lines.append("> Validation here is single-language model evaluation. It includes real MCOtxt v1 variable TOP-4 / literal / SHIFT / punctuation / UTF8_RUN costs and a 9-bit normal MCOtxt header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.")
    lines.append("")

    lines.append("## TOP-4 rank diagnostics — validation")
    lines.append("")
    rank_total = sum(validation.top4_rank_hits.values())
    lines.append("| rank | hits | share of TOP-4 hits |")
    lines.append("|---:|---:|---:|")
    for rank in range(4):
        count = validation.top4_rank_hits.get(rank, 0)
        share = (count / rank_total * 100.0) if rank_total else 0.0
        lines.append(f"| {rank} | {count} | {share:.2f}% |")
    lines.append("")
    lines.append(
        "> Variable TOP-4 is enabled in v1: rank 0 = 2 bits, rank 1 = 3 bits, "
        "ranks 2/3 = 4 bits. The table above shows the observed rank distribution."
    )
    lines.append("")

    lines.append("## Final encoder candidate simulation — validation")
    lines.append("")
    lines.append(
        "This section simulates the final message-level selector between optimized normal "
        "MCOtxt (precomputed CAPS/SHIFT plan + fallback-only UTF8_RUN) and whole-message RAW_UTF8. "
        "It is intentionally separate from the "
        "model-only metrics above so TOP-4/model quality remains comparable between builds."
    )
    lines.append("")
    lines.append(f"- Optimized MCOtxt candidate bits: `{validation.mcotxt_candidate_bits}`")
    lines.append(f"- Optimized MCOtxt candidate packed bytes: `{validation.mcotxt_candidate_bytes}`")
    lines.append(f"- RAW_UTF8 candidate bits: `{validation.raw_utf8_candidate_bits}`")
    lines.append(f"- RAW_UTF8 candidate packed bytes: `{validation.raw_utf8_candidate_bytes}`")
    lines.append(f"- Selected MCOtxt messages: `{validation.selected_mcotxt_messages}`")
    lines.append(f"- Selected RAW_UTF8 messages: `{validation.selected_raw_utf8_messages}`")
    lines.append(f"- Optimized CAPS_MODE toggles in MCOtxt candidates: `{validation.optimized_case_mode_toggles}`")
    lines.append(f"- Optimized one-symbol SHIFTs in MCOtxt candidates: `{validation.optimized_shifts}`")
    lines.append(f"- Optimized fallback UTF8_RUNs in MCOtxt candidates: `{validation.optimized_utf8_runs}`")
    lines.append(f"- Final selected bits: `{validation.selected_bits}`")
    lines.append(f"- Final selected packed bytes: `{validation.selected_bytes}`")
    lines.append(
        f"- Savings vs optimized MCOtxt: `{validation.selector_savings_bytes_vs_mcotxt}` bytes"
    )
    lines.append(
        f"- Selected ratio vs normalized UTF-8: "
        f"`{_fmt_float(validation.selected_ratio_vs_normalized_utf8)}x`"
    )
    lines.append("")
    lines.append(
        f"> RAW_UTF8 simulation uses a `{BITS_RAW_UTF8_HEADER}`-bit byte-aligned "
        "message-mode header, matching the current Python A/B reference benchmark."
    )
    lines.append("")

    lines.append("## Symbol index table")
    lines.append("")
    lines.extend(_symbol_table_rows(model, train))
    lines.append("")

    lines.append("## START TOP-4")
    lines.append("")
    for rank, idx in enumerate(model.start_top4_indexes):
        cp = model.symbols[idx]
        lines.append(f"- `{rank}` → index `{idx}` → {cp_label(cp)}")
    lines.append("")

    lines.append("## AFTER_PUNCT TOP-4")
    lines.append("")
    for rank, idx in enumerate(model.punct_start_top4_indexes):
        cp = model.symbols[idx]
        lines.append(f"- `{rank}` → index `{idx}` → {cp_label(cp)}")
    lines.append("")

    lines.append("## Prediction-context diagnostics")
    lines.append("")
    lines.append("### Message begins with — training")
    lines.append("")
    lines.append("| class | messages |")
    lines.append("|---|---:|")
    for cls, count in train.message_begin_counts.most_common():
        lines.append(f"| `{cls}` | {count} |")
    lines.append("")

    lines.append("### Why a language symbol used START — training")
    lines.append("")
    lines.append("| reason | transitions |")
    lines.append("|---|---:|")
    for reason, count in train.start_reason_counts.most_common():
        lines.append(f"| `{reason}` | {count} |")
    lines.append("")

    lines.append("### START target frequencies — training")
    lines.append("")
    total_train_starts = sum(train.start_counts.values())
    start_top4_set = set(model.start_top4_codepoints())
    lines.append("| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |")
    lines.append("|---:|---|---|---:|---:|---|---|")
    for rank, (cp, count) in enumerate(train.start_counts.most_common(30), 1):
        share = (count / total_train_starts * 100.0) if total_train_starts else 0.0
        flag = "yes" if cp in start_top4_set else ""
        reasons = _start_reason_breakdown(cp, train.start_target_by_reason)
        lines.append(f"| {rank} | `{_md_symbol(cp)}` | U+{cp:04X} | {count} | {share:.2f}% | {flag} | {reasons} |")
    lines.append("")

    lines.append("### AFTER_PUNCT target frequencies — training")
    lines.append("")
    total_train_punct = sum(train.punct_start_counts.values())
    punct_top4_set = set(model.punct_start_top4_codepoints())
    lines.append("| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |")
    lines.append("|---:|---|---|---:|---:|---|")
    for rank, (cp, count) in enumerate(train.punct_start_counts.most_common(30), 1):
        share = (count / total_train_punct * 100.0) if total_train_punct else 0.0
        flag = "yes" if cp in punct_top4_set else ""
        lines.append(f"| {rank} | `{_md_symbol(cp)}` | U+{cp:04X} | {count} | {share:.2f}% | {flag} |")
    lines.append("")

    lines.append("### Ordinary punctuation that led to AFTER_PUNCT — training")
    lines.append("")
    lines.append("| punctuation | codepoint | following language contexts |")
    lines.append("|---|---|---:|")
    for cp, count in train.punct_start_trigger_counts.most_common(30):
        lines.append(f"| `{_md_symbol(cp)}` | U+{cp:04X} | {count} |")
    lines.append("")

    lines.append("### START target frequencies — validation")
    lines.append("")
    total_val_starts = sum(validation.start_counts.values())
    lines.append("| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |")
    lines.append("|---:|---|---|---:|---:|---|---|")
    for rank, (cp, count) in enumerate(validation.start_counts.most_common(30), 1):
        share = (count / total_val_starts * 100.0) if total_val_starts else 0.0
        flag = "yes" if cp in start_top4_set else ""
        reasons = _start_reason_breakdown(cp, validation.start_target_by_reason)
        lines.append(f"| {rank} | `{_md_symbol(cp)}` | U+{cp:04X} | {count} | {share:.2f}% | {flag} | {reasons} |")
    lines.append("")

    lines.append("### AFTER_PUNCT target frequencies — validation")
    lines.append("")
    total_val_punct = sum(validation.punct_start_counts.values())
    lines.append("| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |")
    lines.append("|---:|---|---|---:|---:|---|")
    for rank, (cp, count) in enumerate(validation.punct_start_counts.most_common(30), 1):
        share = (count / total_val_punct * 100.0) if total_val_punct else 0.0
        flag = "yes" if cp in punct_top4_set else ""
        lines.append(f"| {rank} | `{_md_symbol(cp)}` | U+{cp:04X} | {count} | {share:.2f}% | {flag} |")
    lines.append("")

    lines.append("## Bit cost breakdown — validation")
    lines.append("")
    lines.append("| category | tokens | bits | share of total bits |")
    lines.append("|---|---:|---:|---:|")
    for label, tokens, bits in _bit_breakdown_rows(validation):
        share = (bits / validation.total_bits * 100.0) if validation.total_bits else 0.0
        lines.append(f"| {label} | {tokens} | {bits} | {share:.2f}% |")
    lines.append("")

    lines.append("## UTF-8 fallback — validation")
    lines.append("")
    fallback_share = (
        validation.utf8_fallback_bits / validation.total_bits * 100.0
        if validation.total_bits else 0.0
    )
    lines.append(f"- Runs: `{validation.utf8_fallback_runs}`")
    lines.append(f"- Unicode codepoints: `{validation.utf8_fallback_codepoints}`")
    lines.append(f"- UTF-8 bytes: `{validation.utf8_fallback_bytes}`")
    lines.append(f"- Total fallback bits: `{validation.utf8_fallback_bits}`")
    lines.append(f"- Share of total encoded bits: `{fallback_share:.2f}%`")
    lines.append("")
    if not validation.unsupported_counts:
        lines.append("No UTF-8 fallback symbols encountered.")
    else:
        lines.append("| count | codepoint | symbol | Unicode name |")
        lines.append("|---:|---|---|---|")
        for cp, count in validation.unsupported_counts.most_common(max_unsupported):
            char = chr(cp)
            visible = char if char.isprintable() and char not in {"|", "`"} else repr(char)
            try:
                name = unicodedata.name(char)
            except ValueError:
                name = "<unnamed>"
            lines.append(f"| {count} | U+{cp:04X} | `{visible}` | {name} |")
    lines.append("")

    lines.append("## Most expensive TOP-4 misses — validation")
    lines.append("")
    lines.append(
        "Sorted by avoidable bit cost relative to a hypothetical 3-bit TOP-4 reference hit for the same target. "
        "SHIFT cost is excluded because it is paid in both cases."
    )
    lines.append("")
    miss_rows = []
    for (previous, target), count in validation.top4_miss_counts.items():
        literal_bits = BITS_PRIMARY_LITERAL if target in set(model.primary) else BITS_EXTENSION_LITERAL
        # A miss has no actual rank. Use the historical 3-bit TOP4 average as
        # a neutral diagnostic reference rather than pretending a missing
        # target would necessarily occupy rank 0/1/2/3.
        extra_per_occurrence = literal_bits - 3
        miss_rows.append((count * extra_per_occurrence, count, previous, target, literal_bits))
    def _miss_sort_context(previous: Optional[int]) -> int:
        if previous is None:
            return -2
        if previous == AFTER_PUNCT_SENTINEL:
            return -1
        return previous

    miss_rows.sort(key=lambda row: (-row[0], -row[1], _miss_sort_context(row[2]), row[3]))
    lines.append("| previous | next | tier | misses | literal bits | extra vs TOP-4 |")
    lines.append("|---|---|---|---:|---:|---:|")
    primary_set_for_report = set(model.primary)
    for extra_bits, count, previous, target, literal_bits in miss_rows[:40]:
        if previous is None:
            prev_text = "START"
        elif previous == AFTER_PUNCT_SENTINEL:
            prev_text = "AFTER_PUNCT"
        else:
            prev_text = f"`{_md_symbol(previous)}` U+{previous:04X}"
        next_text = f"`{_md_symbol(target)}` U+{target:04X}"
        tier = "primary" if target in primary_set_for_report else "extension"
        lines.append(f"| {prev_text} | {next_text} | {tier} | {count} | {literal_bits} | {extra_bits} |")
    lines.append("")

    lines.append("## Unsupported symbols in validation")
    lines.append("")
    if not validation.unsupported_counts:
        lines.append("No unsupported symbols encountered.")
    else:
        lines.append("These symbols were encoded losslessly through UTF8_RUN during validation.")
        lines.append("| count | codepoint | symbol | Unicode name |")
        lines.append("|---:|---|---|---|")
        for cp, count in validation.unsupported_counts.most_common(max_unsupported):
            char = chr(cp)
            visible = char if char.isprintable() and char not in {"|", "`"} else repr(char)
            try:
                name = unicodedata.name(char)
            except ValueError:
                name = "<unnamed>"
            lines.append(f"| {count} | U+{cp:04X} | `{visible}` | {name} |")
    lines.append("")

    lines.append("## Input files")
    lines.append("")
    lines.append("### Train")
    for p in train_files:
        lines.append(f"- `{p}`")
    if validation_files:
        lines.append("")
        lines.append("### Validation")
        for p in validation_files:
            lines.append(f"- `{p}`")
    lines.append("")
    return "\n".join(lines)


def model_to_debug_json(model: Model, train: CorpusStats, validation: EvalStats) -> Dict[str, object]:
    validation_dict: Dict[str, object] = {
        "messages": validation.messages,
        "original_utf8_bytes": validation.original_utf8_bytes,
        "normalized_codepoints": validation.normalized_codepoints,
        "output_codepoints": validation.output_codepoints,
        "language_symbols": validation.language_symbols,
        "top4_hits": validation.top4_hits,
        "top4_rank_hits": {str(rank): validation.top4_rank_hits.get(rank, 0) for rank in range(4)},
        "primary_literals": validation.primary_literals,
        "extension_literals": validation.extension_literals,
        "punctuation_symbols": validation.punctuation_symbols,
        "shifts": validation.shifts,
        "skipped": validation.skipped,
        "utf8_fallback_runs": validation.utf8_fallback_runs,
        "utf8_fallback_codepoints": validation.utf8_fallback_codepoints,
        "utf8_fallback_bytes": validation.utf8_fallback_bytes,
        "utf8_fallback_bits": validation.utf8_fallback_bits,
        "token_bits": validation.token_bits,
        "header_bits": validation.header_bits,
        "decoded_utf8_bytes": validation.decoded_utf8_bytes,
        "mcotxt_candidate_bits": validation.mcotxt_candidate_bits,
        "mcotxt_candidate_bytes": validation.mcotxt_candidate_bytes,
        "raw_utf8_candidate_bits": validation.raw_utf8_candidate_bits,
        "raw_utf8_candidate_bytes": validation.raw_utf8_candidate_bytes,
        "selected_bits": validation.selected_bits,
        "selected_bytes": validation.selected_bytes,
        "selected_mcotxt_messages": validation.selected_mcotxt_messages,
        "selected_raw_utf8_messages": validation.selected_raw_utf8_messages,
        "optimized_case_mode_toggles": validation.optimized_case_mode_toggles,
        "optimized_shifts": validation.optimized_shifts,
        "optimized_utf8_runs": validation.optimized_utf8_runs,
        "selector_savings_bytes_vs_mcotxt": validation.selector_savings_bytes_vs_mcotxt,
        "selected_ratio_vs_normalized_utf8": validation.selected_ratio_vs_normalized_utf8,
        "unsupported_counts": {str(cp): count for cp, count in validation.unsupported_counts.items()},
        "start_counts": {str(cp): count for cp, count in validation.start_counts.items()},
        "punct_start_counts": {str(cp): count for cp, count in validation.punct_start_counts.items()},
        "punct_start_trigger_counts": {str(cp): count for cp, count in validation.punct_start_trigger_counts.items()},
        "start_reason_counts": dict(validation.start_reason_counts),
        "start_target_by_reason": {
            reason: {str(cp): count for cp, count in counts.items()}
            for reason, counts in validation.start_target_by_reason.items()
        },
        "message_begin_counts": dict(validation.message_begin_counts),
        "top4_misses": [
            {
                "context": (
                    "START" if previous is None
                    else "AFTER_PUNCT" if previous == AFTER_PUNCT_SENTINEL
                    else "SYMBOL"
                ),
                "previousCodepoint": (
                    previous if previous is not None and previous != AFTER_PUNCT_SENTINEL else None
                ),
                "targetCodepoint": target,
                "count": count,
            }
            for (previous, target), count in validation.top4_miss_counts.most_common()
        ],
        "total_bits": validation.total_bits,
        "top4_hit_rate": validation.top4_hit_rate,
        "bits_per_output_char_tokens": validation.bits_per_output_char_tokens,
        "bits_per_output_char_total": validation.bits_per_output_char_total,
        "ratio_vs_decoded_utf8": validation.ratio_vs_decoded_utf8,
    }

    return {
        "format": "MCOtxt model debug v1",
        "language": model.language.code,
        "languageId": model.language.wire_id,
        "unicodeDatabaseVersion": unicodedata.unidata_version,
        "primarySelection": model.primary_selection,
        "primarySymbols": list(model.primary),
        "extensionSymbols": list(model.extension),
        "startTop4Indexes": list(model.start_top4_indexes),
        "punctStartTop4Indexes": list(model.punct_start_top4_indexes),
        "top4Indexes": list(model.top4_indexes),
        "uppercaseMap": [
            {
                "uppercaseCodepoint": upper,
                "lowercaseSymbolIndex": model.symbol_to_index[lower],
                "lowercaseCodepoint": lower,
            }
            for upper, lower in sorted(model.uppercase_to_lowercase.items())
        ],
        "training": {
            "messages": train.messages,
            "normalizedCodepoints": train.normalized_codepoints,
            "languageSymbols": train.language_codepoints,
            "unsupported": train.unsupported_codepoints,
            "messageBeginCounts": dict(train.message_begin_counts),
            "startReasonCounts": dict(train.start_reason_counts),
            "startCounts": {str(cp): count for cp, count in train.start_counts.items()},
            "punctStartCounts": {str(cp): count for cp, count in train.punct_start_counts.items()},
            "punctStartTriggerCounts": {str(cp): count for cp, count in train.punct_start_trigger_counts.items()},
            "startTargetByReason": {
                reason: {str(cp): count for cp, count in counts.items()}
                for reason, counts in train.start_target_by_reason.items()
            },
        },
        "validation": validation_dict,
    }


# ---------------------------------------------------------------------------
# Dataset partitioning helpers
# ---------------------------------------------------------------------------

def _messages_for_explicit_paths(paths: Sequence[Path], fmt: str, jsonl_field: str) -> Iterator[str]:
    for _, _, text in iter_messages(paths, fmt, jsonl_field):
        yield text


def _messages_for_implicit_partition(
    paths: Sequence[Path],
    fmt: str,
    jsonl_field: str,
    ratio: float,
    seed: str,
    want_validation: bool,
) -> Iterator[str]:
    for _, _, text in iter_messages(paths, fmt, jsonl_field):
        is_val = _is_validation_message(text, ratio, seed)
        if is_val == want_validation:
            yield text


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Train/export a deterministic static MCOtxt v1 TOP-4 language model.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--lang", required=True, choices=sorted(LANGUAGES), help="Language model to build")
    p.add_argument("--train", required=True, nargs="+", help="Training file(s), directories, or glob patterns")
    p.add_argument("--validation", nargs="*", default=None, help="Explicit validation file(s)/dirs/globs")
    p.add_argument(
        "--format",
        choices=("auto", "lines", "text", "jsonl"),
        default="auto",
        help="Corpus input format; auto treats .jsonl/.ndjson as JSONL and other files as one-message-per-line",
    )
    p.add_argument("--jsonl-field", default="text", help="JSONL field containing message text")
    p.add_argument(
        "--validation-ratio",
        type=float,
        default=0.20,
        help="Deterministic hold-out ratio when --validation is omitted",
    )
    p.add_argument("--split-seed", default="mcotxt-v1", help="Stable hash split seed")
    p.add_argument(
        "--primary-selection",
        choices=("literal-savings", "frequency"),
        default="literal-savings",
        help="How to choose the 32 primary symbols; literal-savings minimizes 7-vs-9-bit literal cost",
    )
    p.add_argument(
        "--out-dir",
        default=None,
        help=(
            "Directory for generated artifacts. By default the trainer finds "
            "the meshcore-open project root (pubspec.yaml) and writes to "
            "tools/MCOtxt/generated. The Dart model is additionally copied to "
            "assets/models/MCOtxt/v<version>."
        ),
    )
    p.add_argument(
        "--dart-import",
        default="package:meshcore_open/mcotxt/models/mcotxt_model.dart",
        help=(
            "Import emitted at top of generated Dart model. "
            "Defaults to the meshcore_open package import so generated files "
            "compile from tools/ as well as lib/. Use an empty string to omit."
        ),
    )
    p.add_argument("--dart-variable", default=None, help="Override generated McotxtLanguageModel variable name")
    p.add_argument(
        "--punctuation-dart",
        default=None,
        help="Optional path to codec punctuation.dart; if supplied, its 32-codepoint literal list must match",
    )
    p.add_argument("--max-unsupported", type=int, default=100, help="Max unsupported symbols listed in report")
    p.add_argument("--debug-json", action="store_true", help="Also emit non-production JSON debug artifact")
    return p


def _count_messages(iterator: Iterable[str]) -> int:
    return sum(1 for _ in iterator)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)

    if not (0.0 <= args.validation_ratio < 1.0):
        raise SystemExit("--validation-ratio must be >=0 and <1")

    lang = LANGUAGES[args.lang]
    train_files = _expand_paths(args.train)
    explicit_val_files = _expand_paths(args.validation) if args.validation else []

    punctuation_verified: Optional[Path] = None
    if args.punctuation_dart:
        punctuation_verified = Path(args.punctuation_dart)
        if not punctuation_verified.is_file():
            raise SystemExit(f"punctuation.dart not found: {punctuation_verified}")
        verify_punctuation_dart(punctuation_verified)

    if explicit_val_files:
        train_messages_factory = lambda: _messages_for_explicit_paths(train_files, args.format, args.jsonl_field)
        val_messages_factory = lambda: _messages_for_explicit_paths(explicit_val_files, args.format, args.jsonl_field)
        validation_source = "explicit --validation corpus"
    elif args.validation_ratio > 0:
        train_messages_factory = lambda: _messages_for_implicit_partition(
            train_files, args.format, args.jsonl_field, args.validation_ratio, args.split_seed, False
        )
        val_messages_factory = lambda: _messages_for_implicit_partition(
            train_files, args.format, args.jsonl_field, args.validation_ratio, args.split_seed, True
        )
        validation_source = f"deterministic SHA-256 hold-out ({args.validation_ratio:.1%})"
    else:
        train_messages_factory = lambda: _messages_for_explicit_paths(train_files, args.format, args.jsonl_field)
        val_messages_factory = lambda: _messages_for_explicit_paths(train_files, args.format, args.jsonl_field)
        validation_source = "training corpus reused (no hold-out)"

    train_stats = collect_stats_from_messages(train_messages_factory(), lang)
    if train_stats.messages == 0:
        raise SystemExit("Training partition contains zero messages")
    if train_stats.language_codepoints == 0:
        raise SystemExit(f"Training partition contains zero supported {args.lang.upper()} language symbols")

    model = build_model(lang, train_stats, args.primary_selection)

    # A tiny corpus can hash entirely into train. Fall back to train evaluation,
    # but report it explicitly instead of silently producing an empty metric.
    val_count = _count_messages(val_messages_factory())
    if val_count == 0:
        print(
            "warning: validation partition contains zero messages; evaluating on training corpus instead",
            file=sys.stderr,
        )
        val_messages_factory = train_messages_factory
        validation_source += " -> EMPTY, fallback to training corpus"

    validation = evaluate_messages(val_messages_factory(), model)

    # Resolve the meshcore-open project root. It is needed both for the
    # default generated directory and for the mirrored Dart asset.
    script_path = Path(__file__).resolve()
    project_root = None
    for candidate in (script_path.parent, *script_path.parents):
        if (candidate / "pubspec.yaml").is_file():
            project_root = candidate
            break

    if project_root is None:
        cwd = Path.cwd().resolve()
        for candidate in (cwd, *cwd.parents):
            if (candidate / "pubspec.yaml").is_file():
                project_root = candidate
                break

    if project_root is None:
        raise SystemExit(
            "Cannot locate meshcore-open project root (pubspec.yaml). "
            "Run the trainer from inside the repository."
        )

    if args.out_dir:
        out_dir = Path(args.out_dir)
    else:
        out_dir = project_root / "tools" / "MCOtxt" / "generated"

    out_dir.mkdir(parents=True, exist_ok=True)
    stem = f"model_{args.lang}"

    dart_path = out_dir / f"{stem}.dart"
    c_path = out_dir / f"{stem}.h"
    report_path = out_dir / f"{stem}_report.md"

    dart_path.write_text(
        render_dart(model, args.dart_import, args.dart_variable),
        encoding="utf-8",
        newline="\n",
    )

    # Mirror only the Dart runtime model into assets/models/MCOtxt.
    # Reports, debug JSON and C/C++ headers remain in tools/MCOtxt/generated.
    dart_assets_dir = project_root / "assets" / "models" / "MCOtxt" / f"v{MCOTXT_VERSION}"
    dart_assets_dir.mkdir(parents=True, exist_ok=True)
    dart_assets_path = dart_assets_dir / dart_path.name
    shutil.copy2(dart_path, dart_assets_path)
    c_path.write_text(render_c_header(model), encoding="utf-8", newline="\n")
    report_path.write_text(
        render_report(
            model=model,
            train=train_stats,
            validation=validation,
            validation_source=validation_source,
            train_files=train_files,
            validation_files=explicit_val_files,
            max_unsupported=args.max_unsupported,
            punctuation_verified=punctuation_verified,
        ),
        encoding="utf-8",
        newline="\n",
    )

    debug_path: Optional[Path] = None
    if args.debug_json:
        debug_path = out_dir / f"{stem}_debug.json"
        payload = model_to_debug_json(model, train_stats, validation)
        # Counter keys must be strings for clean JSON.
        if isinstance(payload.get("validation"), dict):
            v = payload["validation"]
            if isinstance(v.get("unsupported_counts"), dict):
                v["unsupported_counts"] = {str(k): val for k, val in v["unsupported_counts"].items()}
        debug_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")

    print(f"MCOtxt v1 model generated: {args.lang.upper()}")
    print(f"  train messages:       {train_stats.messages}")
    print(f"  primary / extension:  {len(model.primary)} / {len(model.extension)}")
    print(f"  validation messages:  {validation.messages}")
    print(f"  TOP-4 hit rate:       {validation.top4_hit_rate * 100:.2f}%")
    print(f"  bits/output char:     {validation.bits_per_output_char_total:.4f} (forced MCOtxt, incl. 9-bit header/message)")
    print(
        f"  RAW_UTF8 selected:    {validation.selected_raw_utf8_messages} / "
        f"{validation.messages} messages"
    )
    print(
        f"  selected bytes:       {validation.selected_bytes} "
        f"(saved {validation.selector_savings_bytes_vs_mcotxt} vs optimized MCOtxt)"
    )
    print(f"  optimized CAPS/SHIFT: {validation.optimized_case_mode_toggles} / {validation.optimized_shifts}")
    print(f"  fallback UTF8_RUNs:   {validation.optimized_utf8_runs}")
    print(f"  Dart:                 {dart_path}")
    print(f"  Dart copy:            {dart_assets_path}")
    print(f"  C/C++:                {c_path}")
    print(f"  report:               {report_path}")
    if debug_path:
        print(f"  debug JSON:           {debug_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
