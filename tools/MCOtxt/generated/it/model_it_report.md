# MCOtxt v1 model report — IT

## Build

- Language wire ID: `4`
- Unicode database: `15.1.0`
- Primary selection: `literal-savings`
- Canonical language symbols: `46`
- Primary: `32`
- Extension: `14`
- Total model symbols: `46`
- Prediction contexts: `START`, `AFTER_PUNCT`, `SYMBOL(previous)`
- Punctuation table: built-in MCOtxt v1 fallback; **not verified against punctuation.dart in this run**

## Training corpus

- Files: `1`
- Messages: `1236`
- UTF-8 bytes (message payloads): `48251`
- Normalized codepoints: `47831`
- Language symbols: `46271`
- Uppercase mapped: `2216`
- Punctuation: `1470`
- Unsupported: `90`
- Training TOP-4 hit rate: `64.39%`

## Validation

- Source: `deterministic SHA-256 hold-out (20.0%)`
- Explicit validation files: `0`
- Messages: `307`
- Original UTF-8 bytes: `11681`
- Normalized codepoints: `11591`
- Output codepoints: `11591`
- Skipped unsupported: `0`
- UTF-8 fallback runs: `25`
- UTF-8 fallback codepoints: `26`
- UTF-8 fallback bytes: `59`
- UTF-8 fallback bits: `822`
- Language symbols: `11200`
- TOP-4 hits: `7149` (`63.83%`)
- Primary literals: `3957`
- Extension literals: `94`
- SHIFT tokens: `584`
- Punctuation tokens: `365`
- Token bits: `55964`
- Header bits (12/message): `3684`
- Total bits: `59648`
- Bits/output-char, tokens only: `4.8282`
- Bits/output-char, incl. per-message header: `5.1461`
- UTF-8 bytes of the same decoded/supported text: `11681`
- Compression ratio vs same decoded UTF-8: `1.5667x`

> Validation here is single-language model evaluation. It includes real MCOtxt v1 variable TOP-4 / literal / SHIFT / punctuation / UTF8_RUN costs and a 12-bit normal MCOtxt header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.

## TOP-4 rank diagnostics — validation

| rank | hits | share of TOP-4 hits |
|---:|---:|---:|
| 0 | 3028 | 42.36% |
| 1 | 1783 | 24.94% |
| 2 | 1345 | 18.81% |
| 3 | 993 | 13.89% |

> Variable TOP-4 is enabled in v1: rank 0 = 2 bits, rank 1 = 3 bits, ranks 2/3 = 4 bits. The table above shows the observed rank distribution.

## Final encoder candidate simulation — validation

This section simulates the final message-level selector between optimized normal MCOtxt (precomputed CAPS/SHIFT plan + fallback-only UTF8_RUN) and whole-message RAW_UTF8. It is intentionally separate from the model-only metrics above so TOP-4/model quality remains comparable between builds.

- Optimized MCOtxt candidate bits: `59287`
- Optimized MCOtxt candidate packed bytes: `7547`
- RAW_UTF8 candidate bits: `98360`
- RAW_UTF8 candidate packed bytes: `12295`
- Selected MCOtxt messages: `306`
- Selected RAW_UTF8 messages: `1`
- Optimized CAPS_MODE toggles in MCOtxt candidates: `37`
- Optimized one-symbol SHIFTs in MCOtxt candidates: `454`
- Optimized fallback UTF8_RUNs in MCOtxt candidates: `25`
- Final selected bits: `59238`
- Final selected packed bytes: `7540`
- Savings vs optimized MCOtxt: `7` bytes
- Selected ratio vs normalized UTF-8: `1.5775x`

> RAW_UTF8 simulation uses a `16`-bit byte-aligned message-mode header, matching the current Python A/B reference benchmark.

## Symbol index table

| idx | tier | symbol | codepoint | train count |
|---:|---|---|---|---:|
| 0 | primary | `SPACE` | U+0020 | 7287 |
| 1 | primary | `t` | U+0074 | 2446 |
| 2 | primary | `l` | U+006C | 1602 |
| 3 | primary | `m` | U+006D | 1138 |
| 4 | primary | `p` | U+0070 | 1140 |
| 5 | primary | `u` | U+0075 | 1440 |
| 6 | primary | `i` | U+0069 | 3792 |
| 7 | primary | `r` | U+0072 | 2478 |
| 8 | primary | `c` | U+0063 | 1549 |
| 9 | primary | `s` | U+0073 | 1989 |
| 10 | primary | `g` | U+0067 | 885 |
| 11 | primary | `v` | U+0076 | 738 |
| 12 | primary | `e` | U+0065 | 3701 |
| 13 | primary | `o` | U+006F | 4374 |
| 14 | primary | `a` | U+0061 | 4316 |
| 15 | primary | `n` | U+006E | 2777 |
| 16 | primary | `d` | U+0064 | 1090 |
| 17 | primary | `b` | U+0062 | 848 |
| 18 | primary | `h` | U+0068 | 678 |
| 19 | primary | `z` | U+007A | 338 |
| 20 | primary | `f` | U+0066 | 294 |
| 21 | primary | `q` | U+0071 | 206 |
| 22 | primary | `è` | U+00E8 | 107 |
| 23 | primary | `1` | U+0031 | 121 |
| 24 | primary | `3` | U+0033 | 127 |
| 25 | primary | `2` | U+0032 | 90 |
| 26 | primary | `4` | U+0034 | 69 |
| 27 | primary | `w` | U+0077 | 65 |
| 28 | primary | `k` | U+006B | 64 |
| 29 | primary | `7` | U+0037 | 52 |
| 30 | primary | `6` | U+0036 | 60 |
| 31 | primary | `8` | U+0038 | 54 |
| 32 | extension | `5` | U+0035 | 56 |
| 33 | extension | `y` | U+0079 | 44 |
| 34 | extension | `à` | U+00E0 | 36 |
| 35 | extension | `ì` | U+00EC | 34 |
| 36 | extension | `9` | U+0039 | 40 |
| 37 | extension | `ò` | U+00F2 | 26 |
| 38 | extension | `0` | U+0030 | 57 |
| 39 | extension | `ù` | U+00F9 | 18 |
| 40 | extension | `j` | U+006A | 17 |
| 41 | extension | `é` | U+00E9 | 17 |
| 42 | extension | `x` | U+0078 | 11 |
| 43 | extension | `í` | U+00ED | 0 |
| 44 | extension | `ó` | U+00F3 | 0 |
| 45 | extension | `ú` | U+00FA | 0 |

## START TOP-4

- `0` → index `17` → U+0062 'b' LATIN SMALL LETTER B
- `1` → index `8` → U+0063 'c' LATIN SMALL LETTER C
- `2` → index `9` → U+0073 's' LATIN SMALL LETTER S
- `3` → index `6` → U+0069 'i' LATIN SMALL LETTER I

## AFTER_PUNCT TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `6` → U+0069 'i' LATIN SMALL LETTER I
- `2` → index `14` → U+0061 'a' LATIN SMALL LETTER A
- `3` → index `7` → U+0072 'r' LATIN SMALL LETTER R

## Prediction-context diagnostics

### Message begins with — training

| class | messages |
|---|---:|
| `language_symbol` | 1217 |
| `unsupported` | 15 |
| `punctuation` | 4 |

### Why a language symbol used START — training

| reason | transitions |
|---|---:|
| `message_start` | 1217 |
| `utf8_fallback` | 65 |
| `newline` | 19 |

### START target frequencies — training

| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `b` | U+0062 | 381 | 29.29% | yes | message_start=378, newline=3 |
| 2 | `c` | U+0063 | 187 | 14.37% | yes | message_start=180, utf8_fallback=7 |
| 3 | `s` | U+0073 | 103 | 7.92% | yes | message_start=99, utf8_fallback=4 |
| 4 | `i` | U+0069 | 55 | 4.23% | yes | message_start=52, newline=1, utf8_fallback=2 |
| 5 | `a` | U+0061 | 54 | 4.15% |  | message_start=48, newline=2, utf8_fallback=4 |
| 6 | `g` | U+0067 | 53 | 4.07% |  | message_start=52, newline=1 |
| 7 | `m` | U+006D | 50 | 3.84% |  | message_start=44, newline=1, utf8_fallback=5 |
| 8 | `p` | U+0070 | 49 | 3.77% |  | message_start=49 |
| 9 | `t` | U+0074 | 44 | 3.38% |  | message_start=42, newline=1, utf8_fallback=1 |
| 10 | `r` | U+0072 | 36 | 2.77% |  | message_start=34, utf8_fallback=2 |
| 11 | `n` | U+006E | 32 | 2.46% |  | message_start=30, utf8_fallback=2 |
| 12 | `o` | U+006F | 30 | 2.31% |  | message_start=28, utf8_fallback=2 |
| 13 | `e` | U+0065 | 27 | 2.08% |  | message_start=20, utf8_fallback=7 |
| 14 | `d` | U+0064 | 27 | 2.08% |  | message_start=24, newline=1, utf8_fallback=2 |
| 15 | `q` | U+0071 | 26 | 2.00% |  | message_start=25, utf8_fallback=1 |
| 16 | `SPACE` | U+0020 | 22 | 1.69% |  | utf8_fallback=22 |
| 17 | `h` | U+0068 | 19 | 1.46% |  | message_start=16, newline=1, utf8_fallback=2 |
| 18 | `u` | U+0075 | 17 | 1.31% |  | message_start=16, newline=1 |
| 19 | `v` | U+0076 | 16 | 1.23% |  | message_start=15, utf8_fallback=1 |
| 20 | `f` | U+0066 | 11 | 0.85% |  | message_start=9, newline=2 |
| 21 | `l` | U+006C | 10 | 0.77% |  | message_start=9, utf8_fallback=1 |
| 22 | `3` | U+0033 | 8 | 0.61% |  | message_start=7, newline=1 |
| 23 | `è` | U+00E8 | 8 | 0.61% |  | message_start=7, newline=1 |
| 24 | `4` | U+0034 | 6 | 0.46% |  | message_start=6 |
| 25 | `6` | U+0036 | 6 | 0.46% |  | message_start=5, newline=1 |
| 26 | `7` | U+0037 | 5 | 0.38% |  | message_start=4, newline=1 |
| 27 | `w` | U+0077 | 5 | 0.38% |  | message_start=5 |
| 28 | `1` | U+0031 | 4 | 0.31% |  | message_start=4 |
| 29 | `2` | U+0032 | 4 | 0.31% |  | message_start=3, newline=1 |
| 30 | `8` | U+0038 | 2 | 0.15% |  | message_start=2 |

### AFTER_PUNCT target frequencies — training

| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 600 | 67.64% | yes |
| 2 | `i` | U+0069 | 26 | 2.93% | yes |
| 3 | `a` | U+0061 | 24 | 2.71% | yes |
| 4 | `r` | U+0072 | 24 | 2.71% | yes |
| 5 | `l` | U+006C | 21 | 2.37% |  |
| 6 | `m` | U+006D | 17 | 1.92% |  |
| 7 | `è` | U+00E8 | 16 | 1.80% |  |
| 8 | `p` | U+0070 | 16 | 1.80% |  |
| 9 | `b` | U+0062 | 16 | 1.80% |  |
| 10 | `4` | U+0034 | 11 | 1.24% |  |
| 11 | `c` | U+0063 | 11 | 1.24% |  |
| 12 | `e` | U+0065 | 11 | 1.24% |  |
| 13 | `s` | U+0073 | 10 | 1.13% |  |
| 14 | `t` | U+0074 | 10 | 1.13% |  |
| 15 | `h` | U+0068 | 9 | 1.01% |  |
| 16 | `1` | U+0031 | 7 | 0.79% |  |
| 17 | `7` | U+0037 | 6 | 0.68% |  |
| 18 | `3` | U+0033 | 5 | 0.56% |  |
| 19 | `0` | U+0030 | 5 | 0.56% |  |
| 20 | `2` | U+0032 | 5 | 0.56% |  |
| 21 | `d` | U+0064 | 5 | 0.56% |  |
| 22 | `w` | U+0077 | 4 | 0.45% |  |
| 23 | `n` | U+006E | 4 | 0.45% |  |
| 24 | `g` | U+0067 | 3 | 0.34% |  |
| 25 | `v` | U+0076 | 3 | 0.34% |  |
| 26 | `f` | U+0066 | 3 | 0.34% |  |
| 27 | `o` | U+006F | 3 | 0.34% |  |
| 28 | `5` | U+0035 | 3 | 0.34% |  |
| 29 | `9` | U+0039 | 2 | 0.23% |  |
| 30 | `z` | U+007A | 2 | 0.23% |  |

### Ordinary punctuation that led to AFTER_PUNCT — training

| punctuation | codepoint | following language contexts |
|---|---|---:|
| `,` | U+002C | 302 |
| `.` | U+002E | 206 |
| `-` | U+002D | 70 |
| `'` | U+0027 | 53 |
| `(` | U+0028 | 53 |
| `!` | U+0021 | 40 |
| `?` | U+003F | 26 |
| `:` | U+003A | 21 |
| `"` | U+0022 | 19 |
| `’` | U+2019 | 18 |
| `/` | U+002F | 15 |
| `)` | U+0029 | 12 |
| `[` | U+005B | 12 |
| `]` | U+005D | 10 |
| `_` | U+005F | 7 |
| `+` | U+002B | 6 |
| `“` | U+201C | 5 |
| `%` | U+0025 | 4 |
| `#` | U+0023 | 3 |
| `”` | U+201D | 2 |
| `@` | U+0040 | 1 |
| `=` | U+003D | 1 |
| `;` | U+003B | 1 |

### START target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `b` | U+0062 | 82 | 24.85% | yes | message_start=81, newline=1 |
| 2 | `c` | U+0063 | 38 | 11.52% | yes | message_start=36, newline=1, utf8_fallback=1 |
| 3 | `s` | U+0073 | 27 | 8.18% | yes | message_start=25, newline=1, utf8_fallback=1 |
| 4 | `a` | U+0061 | 22 | 6.67% |  | message_start=22 |
| 5 | `g` | U+0067 | 17 | 5.15% |  | message_start=17 |
| 6 | `t` | U+0074 | 16 | 4.85% |  | message_start=16 |
| 7 | `m` | U+006D | 14 | 4.24% |  | message_start=13, utf8_fallback=1 |
| 8 | `i` | U+0069 | 13 | 3.94% | yes | message_start=13 |
| 9 | `p` | U+0070 | 13 | 3.94% |  | message_start=13 |
| 10 | `r` | U+0072 | 11 | 3.33% |  | message_start=10, utf8_fallback=1 |
| 11 | `o` | U+006F | 9 | 2.73% |  | message_start=8, utf8_fallback=1 |
| 12 | `n` | U+006E | 9 | 2.73% |  | message_start=9 |
| 13 | `e` | U+0065 | 9 | 2.73% |  | message_start=7, utf8_fallback=2 |
| 14 | `q` | U+0071 | 8 | 2.42% |  | message_start=6, newline=2 |
| 15 | `d` | U+0064 | 7 | 2.12% |  | message_start=6, newline=1 |
| 16 | `SPACE` | U+0020 | 7 | 2.12% |  | utf8_fallback=7 |
| 17 | `h` | U+0068 | 6 | 1.82% |  | message_start=3, newline=2, utf8_fallback=1 |
| 18 | `v` | U+0076 | 4 | 1.21% |  | message_start=4 |
| 19 | `u` | U+0075 | 4 | 1.21% |  | message_start=4 |
| 20 | `f` | U+0066 | 3 | 0.91% |  | message_start=3 |
| 21 | `7` | U+0037 | 2 | 0.61% |  | message_start=2 |
| 22 | `6` | U+0036 | 2 | 0.61% |  | message_start=2 |
| 23 | `3` | U+0033 | 2 | 0.61% |  | message_start=2 |
| 24 | `l` | U+006C | 1 | 0.30% |  | message_start=1 |
| 25 | `x` | U+0078 | 1 | 0.30% |  | message_start=1 |
| 26 | `è` | U+00E8 | 1 | 0.30% |  | message_start=1 |
| 27 | `w` | U+0077 | 1 | 0.30% |  | utf8_fallback=1 |
| 28 | `4` | U+0034 | 1 | 0.30% |  | message_start=1 |

### AFTER_PUNCT target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 135 | 63.68% | yes |
| 2 | `i` | U+0069 | 9 | 4.25% | yes |
| 3 | `t` | U+0074 | 6 | 2.83% |  |
| 4 | `r` | U+0072 | 5 | 2.36% | yes |
| 5 | `a` | U+0061 | 4 | 1.89% | yes |
| 6 | `d` | U+0064 | 4 | 1.89% |  |
| 7 | `s` | U+0073 | 4 | 1.89% |  |
| 8 | `c` | U+0063 | 4 | 1.89% |  |
| 9 | `b` | U+0062 | 4 | 1.89% |  |
| 10 | `l` | U+006C | 4 | 1.89% |  |
| 11 | `v` | U+0076 | 3 | 1.42% |  |
| 12 | `m` | U+006D | 3 | 1.42% |  |
| 13 | `g` | U+0067 | 3 | 1.42% |  |
| 14 | `8` | U+0038 | 2 | 0.94% |  |
| 15 | `f` | U+0066 | 2 | 0.94% |  |
| 16 | `p` | U+0070 | 2 | 0.94% |  |
| 17 | `h` | U+0068 | 2 | 0.94% |  |
| 18 | `2` | U+0032 | 2 | 0.94% |  |
| 19 | `o` | U+006F | 2 | 0.94% |  |
| 20 | `è` | U+00E8 | 2 | 0.94% |  |
| 21 | `w` | U+0077 | 1 | 0.47% |  |
| 22 | `k` | U+006B | 1 | 0.47% |  |
| 23 | `0` | U+0030 | 1 | 0.47% |  |
| 24 | `4` | U+0034 | 1 | 0.47% |  |
| 25 | `5` | U+0035 | 1 | 0.47% |  |
| 26 | `q` | U+0071 | 1 | 0.47% |  |
| 27 | `e` | U+0065 | 1 | 0.47% |  |
| 28 | `y` | U+0079 | 1 | 0.47% |  |
| 29 | `6` | U+0036 | 1 | 0.47% |  |
| 30 | `1` | U+0031 | 1 | 0.47% |  |

## Bit cost breakdown — validation

| category | tokens | bits | share of total bits |
|---|---:|---:|---:|
| TOP-4 variable | 7149 | 20757 | 34.80% |
| Primary literal | 3957 | 27699 | 46.44% |
| Extension literal | 94 | 846 | 1.42% |
| SHIFT | 584 | 2920 | 4.90% |
| Punctuation | 365 | 2920 | 4.90% |
| UTF-8 fallback | 25 | 822 | 1.38% |
| Header | 307 | 3684 | 6.18% |

## UTF-8 fallback — validation

- Runs: `25`
- Unicode codepoints: `26`
- UTF-8 bytes: `59`
- Total fallback bits: `822`
- Share of total encoded bits: `1.38%`

| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 11 | U+002A | `*` | ASTERISK |
| 9 | U+2026 | `…` | HORIZONTAL ELLIPSIS |
| 1 | U+1F359 | `🍙` | RICE BALL |
| 1 | U+1F30C | `🌌` | MILKY WAY |
| 1 | U+1F1EE | `🇮` | REGIONAL INDICATOR SYMBOL LETTER I |
| 1 | U+1F1F9 | `🇹` | REGIONAL INDICATOR SYMBOL LETTER T |
| 1 | U+00B0 | `°` | DEGREE SIGN |
| 1 | U+2070 | `⁰` | SUPERSCRIPT ZERO |

## Most expensive TOP-4 misses — validation

Sorted by avoidable bit cost relative to a hypothetical 3-bit TOP-4 reference hit for the same target. SHIFT cost is excluded because it is paid in both cases.

| previous | next | tier | misses | literal bits | extra vs TOP-4 |
|---|---|---|---:|---:|---:|
| `SPACE` U+0020 | `m` U+006D | primary | 115 | 7 | 460 |
| `SPACE` U+0020 | `p` U+0070 | primary | 113 | 7 | 452 |
| `SPACE` U+0020 | `t` U+0074 | primary | 90 | 7 | 360 |
| `SPACE` U+0020 | `i` U+0069 | primary | 87 | 7 | 348 |
| `SPACE` U+0020 | `r` U+0072 | primary | 82 | 7 | 328 |
| `t` U+0074 | `a` U+0061 | primary | 78 | 7 | 312 |
| `a` U+0061 | `t` U+0074 | primary | 73 | 7 | 292 |
| `SPACE` U+0020 | `b` U+0062 | primary | 60 | 7 | 240 |
| `SPACE` U+0020 | `h` U+0068 | primary | 59 | 7 | 236 |
| `SPACE` U+0020 | `l` U+006C | primary | 58 | 7 | 232 |
| `r` U+0072 | `n` U+006E | primary | 55 | 7 | 220 |
| `t` U+0074 | `r` U+0072 | primary | 54 | 7 | 216 |
| `i` U+0069 | `c` U+0063 | primary | 52 | 7 | 208 |
| `s` U+0073 | `o` U+006F | primary | 51 | 7 | 204 |
| `SPACE` U+0020 | `u` U+0075 | primary | 47 | 7 | 188 |
| `SPACE` U+0020 | `v` U+0076 | primary | 47 | 7 | 188 |
| `i` U+0069 | `e` U+0065 | primary | 47 | 7 | 188 |
| `o` U+006F | `l` U+006C | primary | 47 | 7 | 188 |
| `a` U+0061 | `s` U+0073 | primary | 46 | 7 | 184 |
| `i` U+0069 | `l` U+006C | primary | 46 | 7 | 184 |
| `o` U+006F | `m` U+006D | primary | 46 | 7 | 184 |
| `SPACE` U+0020 | `n` U+006E | primary | 42 | 7 | 168 |
| `l` U+006C | `l` U+006C | primary | 42 | 7 | 168 |
| `SPACE` U+0020 | `e` U+0065 | primary | 41 | 7 | 164 |
| `n` U+006E | `g` U+0067 | primary | 40 | 7 | 160 |
| `a` U+0061 | `o` U+006F | primary | 39 | 7 | 156 |
| `c` U+0063 | `a` U+0061 | primary | 39 | 7 | 156 |
| `e` U+0065 | `l` U+006C | primary | 39 | 7 | 156 |
| `e` U+0065 | `t` U+0074 | primary | 38 | 7 | 152 |
| `n` U+006E | `e` U+0065 | primary | 38 | 7 | 152 |
| `t` U+0074 | `u` U+0075 | primary | 37 | 7 | 148 |
| `SPACE` U+0020 | `g` U+0067 | primary | 36 | 7 | 144 |
| `SPACE` U+0020 | `q` U+0071 | primary | 36 | 7 | 144 |
| `l` U+006C | `t` U+0074 | primary | 35 | 7 | 140 |
| `n` U+006E | `d` U+0064 | primary | 35 | 7 | 140 |
| `o` U+006F | `v` U+0076 | primary | 35 | 7 | 140 |
| `s` U+0073 | `s` U+0073 | primary | 35 | 7 | 140 |
| `e` U+0065 | `v` U+0076 | primary | 34 | 7 | 136 |
| `l` U+006C | `o` U+006F | primary | 33 | 7 | 132 |
| `SPACE` U+0020 | `f` U+0066 | primary | 31 | 7 | 124 |

## Unsupported symbols in validation

These symbols were encoded losslessly through UTF8_RUN during validation.
| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 11 | U+002A | `*` | ASTERISK |
| 9 | U+2026 | `…` | HORIZONTAL ELLIPSIS |
| 1 | U+1F359 | `🍙` | RICE BALL |
| 1 | U+1F30C | `🌌` | MILKY WAY |
| 1 | U+1F1EE | `🇮` | REGIONAL INDICATOR SYMBOL LETTER I |
| 1 | U+1F1F9 | `🇹` | REGIONAL INDICATOR SYMBOL LETTER T |
| 1 | U+00B0 | `°` | DEGREE SIGN |
| 1 | U+2070 | `⁰` | SUPERSCRIPT ZERO |

## Input files

### Train
- `corpora\it\mcotxt_it_dataset_clean.jsonl`
