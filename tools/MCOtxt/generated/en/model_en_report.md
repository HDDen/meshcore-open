# MCOtxt v1 model report — EN

## Build

- Language wire ID: `0`
- Unicode database: `15.1.0`
- Primary selection: `literal-savings`
- Canonical language symbols: `37`
- Primary: `31`
- Extension: `6`
- Total model symbols: `37`
- Prediction contexts: `START`, `AFTER_PUNCT`, `SYMBOL(previous)`
- Punctuation table: built-in MCOtxt v1 fallback; **not verified against punctuation.dart in this run**

## Training corpus

- Files: `1`
- Messages: `2243`
- UTF-8 bytes (message payloads): `79410`
- Normalized codepoints: `79249`
- Language symbols: `76846`
- Uppercase mapped: `3379`
- Punctuation: `2331`
- Unsupported: `72`
- Training TOP-4 hit rate: `59.99%`

## Validation

- Source: `deterministic SHA-256 hold-out (20.0%)`
- Explicit validation files: `0`
- Messages: `548`
- Original UTF-8 bytes: `19151`
- Normalized codepoints: `19132`
- Output codepoints (supported + punctuation): `19128`
- Skipped unsupported: `4`
- Language symbols: `18518`
- TOP-4 hits: `11089` (`59.88%`)
- Primary literals: `7364`
- Extension literals: `65`
- SHIFT tokens: `808`
- Punctuation tokens: `610`
- Token bits: `94320`
- Header bits (9/message): `4932`
- Total bits: `99252`
- Bits/output-char, tokens only: `4.9310`
- Bits/output-char, incl. per-message header: `5.1888`
- UTF-8 bytes of the same decoded/supported text: `19142`
- Compression ratio vs same decoded UTF-8: `1.5429x`

> Validation here is single-language model evaluation. It includes real MCOtxt v1 TOP-4 / literal / SHIFT / punctuation costs and a 9-bit header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.

## Symbol index table

| idx | tier | symbol | codepoint | train count |
|---:|---|---|---|---:|
| 0 | primary | `SPACE` | U+0020 | 12742 |
| 1 | primary | `o` | U+006F | 6003 |
| 2 | primary | `d` | U+0064 | 2014 |
| 3 | primary | `a` | U+0061 | 4470 |
| 4 | primary | `i` | U+0069 | 4411 |
| 5 | primary | `l` | U+006C | 2695 |
| 6 | primary | `r` | U+0072 | 3673 |
| 7 | primary | `m` | U+006D | 1954 |
| 8 | primary | `y` | U+0079 | 1556 |
| 9 | primary | `t` | U+0074 | 5371 |
| 10 | primary | `c` | U+0063 | 1462 |
| 11 | primary | `p` | U+0070 | 1398 |
| 12 | primary | `w` | U+0077 | 1279 |
| 13 | primary | `s` | U+0073 | 3870 |
| 14 | primary | `f` | U+0066 | 1149 |
| 15 | primary | `g` | U+0067 | 2116 |
| 16 | primary | `h` | U+0068 | 3233 |
| 17 | primary | `b` | U+0062 | 1001 |
| 18 | primary | `n` | U+006E | 4942 |
| 19 | primary | `e` | U+0065 | 6975 |
| 20 | primary | `k` | U+006B | 743 |
| 21 | primary | `u` | U+0075 | 1650 |
| 22 | primary | `v` | U+0076 | 697 |
| 23 | primary | `x` | U+0078 | 202 |
| 24 | primary | `1` | U+0031 | 188 |
| 25 | primary | `j` | U+006A | 124 |
| 26 | primary | `3` | U+0033 | 104 |
| 27 | primary | `2` | U+0032 | 131 |
| 28 | primary | `8` | U+0038 | 83 |
| 29 | primary | `4` | U+0034 | 99 |
| 30 | primary | `z` | U+007A | 77 |
| 31 | extension | `5` | U+0035 | 89 |
| 32 | extension | `q` | U+0071 | 47 |
| 33 | extension | `6` | U+0036 | 72 |
| 34 | extension | `7` | U+0037 | 42 |
| 35 | extension | `9` | U+0039 | 52 |
| 36 | extension | `0` | U+0030 | 132 |

## START TOP-4

- `0` → index `16` → U+0068 'h' LATIN SMALL LETTER H
- `1` → index `7` → U+006D 'm' LATIN SMALL LETTER M
- `2` → index `9` → U+0074 't' LATIN SMALL LETTER T
- `3` → index `4` → U+0069 'i' LATIN SMALL LETTER I

## AFTER_PUNCT TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `13` → U+0073 's' LATIN SMALL LETTER S
- `2` → index `9` → U+0074 't' LATIN SMALL LETTER T
- `3` → index `7` → U+006D 'm' LATIN SMALL LETTER M

## Prediction-context diagnostics

### Message begins with — training

| class | messages |
|---|---:|
| `language_symbol` | 2206 |
| `punctuation` | 31 |
| `unsupported` | 6 |

### Why a language symbol used START — training

| reason | transitions |
|---|---:|
| `message_start` | 2211 |

### START target frequencies — training

| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `h` | U+0068 | 229 | 10.36% | yes | message_start=229 |
| 2 | `m` | U+006D | 225 | 10.18% | yes | message_start=225 |
| 3 | `t` | U+0074 | 217 | 9.81% | yes | message_start=217 |
| 4 | `i` | U+0069 | 215 | 9.72% | yes | message_start=215 |
| 5 | `g` | U+0067 | 174 | 7.87% |  | message_start=174 |
| 6 | `a` | U+0061 | 147 | 6.65% |  | message_start=147 |
| 7 | `w` | U+0077 | 120 | 5.43% |  | message_start=120 |
| 8 | `y` | U+0079 | 106 | 4.79% |  | message_start=106 |
| 9 | `e` | U+0065 | 94 | 4.25% |  | message_start=94 |
| 10 | `r` | U+0072 | 87 | 3.93% |  | message_start=87 |
| 11 | `s` | U+0073 | 74 | 3.35% |  | message_start=74 |
| 12 | `n` | U+006E | 72 | 3.26% |  | message_start=72 |
| 13 | `o` | U+006F | 49 | 2.22% |  | message_start=49 |
| 14 | `c` | U+0063 | 44 | 1.99% |  | message_start=44 |
| 15 | `1` | U+0031 | 43 | 1.94% |  | message_start=43 |
| 16 | `b` | U+0062 | 42 | 1.90% |  | message_start=42 |
| 17 | `l` | U+006C | 40 | 1.81% |  | message_start=40 |
| 18 | `d` | U+0064 | 37 | 1.67% |  | message_start=37 |
| 19 | `f` | U+0066 | 34 | 1.54% |  | message_start=34 |
| 20 | `p` | U+0070 | 28 | 1.27% |  | message_start=28 |
| 21 | `2` | U+0032 | 28 | 1.27% |  | message_start=28 |
| 22 | `j` | U+006A | 14 | 0.63% |  | message_start=14 |
| 23 | `3` | U+0033 | 12 | 0.54% |  | message_start=12 |
| 24 | `k` | U+006B | 11 | 0.50% |  | message_start=11 |
| 25 | `5` | U+0035 | 9 | 0.41% |  | message_start=9 |
| 26 | `8` | U+0038 | 9 | 0.41% |  | message_start=9 |
| 27 | `v` | U+0076 | 8 | 0.36% |  | message_start=8 |
| 28 | `4` | U+0034 | 7 | 0.32% |  | message_start=7 |
| 29 | `9` | U+0039 | 7 | 0.32% |  | message_start=7 |
| 30 | `7` | U+0037 | 7 | 0.32% |  | message_start=7 |

### AFTER_PUNCT target frequencies — training

| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 871 | 56.78% | yes |
| 2 | `s` | U+0073 | 164 | 10.69% | yes |
| 3 | `t` | U+0074 | 109 | 7.11% | yes |
| 4 | `m` | U+006D | 73 | 4.76% | yes |
| 5 | `r` | U+0072 | 34 | 2.22% |  |
| 6 | `v` | U+0076 | 29 | 1.89% |  |
| 7 | `l` | U+006C | 24 | 1.56% |  |
| 8 | `d` | U+0064 | 21 | 1.37% |  |
| 9 | `n` | U+006E | 18 | 1.17% |  |
| 10 | `c` | U+0063 | 15 | 0.98% |  |
| 11 | `i` | U+0069 | 15 | 0.98% |  |
| 12 | `a` | U+0061 | 14 | 0.91% |  |
| 13 | `p` | U+0070 | 13 | 0.85% |  |
| 14 | `1` | U+0031 | 11 | 0.72% |  |
| 15 | `2` | U+0032 | 11 | 0.72% |  |
| 16 | `e` | U+0065 | 10 | 0.65% |  |
| 17 | `b` | U+0062 | 10 | 0.65% |  |
| 18 | `u` | U+0075 | 10 | 0.65% |  |
| 19 | `8` | U+0038 | 9 | 0.59% |  |
| 20 | `5` | U+0035 | 8 | 0.52% |  |
| 21 | `o` | U+006F | 8 | 0.52% |  |
| 22 | `0` | U+0030 | 7 | 0.46% |  |
| 23 | `g` | U+0067 | 7 | 0.46% |  |
| 24 | `w` | U+0077 | 7 | 0.46% |  |
| 25 | `3` | U+0033 | 6 | 0.39% |  |
| 26 | `7` | U+0037 | 5 | 0.33% |  |
| 27 | `f` | U+0066 | 5 | 0.33% |  |
| 28 | `h` | U+0068 | 4 | 0.26% |  |
| 29 | `4` | U+0034 | 4 | 0.26% |  |
| 30 | `6` | U+0036 | 3 | 0.20% |  |

### Ordinary punctuation that led to AFTER_PUNCT — training

| punctuation | codepoint | following language contexts |
|---|---|---:|
| `,` | U+002C | 445 |
| `'` | U+0027 | 361 |
| `.` | U+002E | 334 |
| `/` | U+002F | 57 |
| `-` | U+002D | 53 |
| `?` | U+003F | 49 |
| `!` | U+0021 | 48 |
| `:` | U+003A | 36 |
| `’` | U+2019 | 32 |
| `@` | U+0040 | 17 |
| `(` | U+0028 | 17 |
| `\` | U+005C | 15 |
| `#` | U+0023 | 15 |
| `"` | U+0022 | 11 |
| `%` | U+0025 | 11 |
| `)` | U+0029 | 8 |
| `+` | U+002B | 7 |
| `&` | U+0026 | 5 |
| `_` | U+005F | 4 |
| `;` | U+003B | 3 |
| `=` | U+003D | 3 |
| `“` | U+201C | 1 |
| `[` | U+005B | 1 |
| `]` | U+005D | 1 |

### START target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `m` | U+006D | 59 | 10.93% | yes | message_start=59 |
| 2 | `h` | U+0068 | 59 | 10.93% | yes | message_start=59 |
| 3 | `i` | U+0069 | 59 | 10.93% | yes | message_start=59 |
| 4 | `g` | U+0067 | 43 | 7.96% |  | message_start=43 |
| 5 | `a` | U+0061 | 35 | 6.48% |  | message_start=35 |
| 6 | `t` | U+0074 | 35 | 6.48% | yes | message_start=35 |
| 7 | `e` | U+0065 | 35 | 6.48% |  | message_start=35 |
| 8 | `r` | U+0072 | 34 | 6.30% |  | message_start=34 |
| 9 | `y` | U+0079 | 23 | 4.26% |  | message_start=23 |
| 10 | `n` | U+006E | 21 | 3.89% |  | message_start=21 |
| 11 | `w` | U+0077 | 20 | 3.70% |  | message_start=20 |
| 12 | `c` | U+0063 | 19 | 3.52% |  | message_start=19 |
| 13 | `s` | U+0073 | 16 | 2.96% |  | message_start=16 |
| 14 | `1` | U+0031 | 12 | 2.22% |  | message_start=12 |
| 15 | `b` | U+0062 | 11 | 2.04% |  | message_start=11 |
| 16 | `d` | U+0064 | 10 | 1.85% |  | message_start=10 |
| 17 | `o` | U+006F | 8 | 1.48% |  | message_start=8 |
| 18 | `2` | U+0032 | 7 | 1.30% |  | message_start=7 |
| 19 | `l` | U+006C | 7 | 1.30% |  | message_start=7 |
| 20 | `p` | U+0070 | 4 | 0.74% |  | message_start=4 |
| 21 | `f` | U+0066 | 3 | 0.56% |  | message_start=3 |
| 22 | `j` | U+006A | 3 | 0.56% |  | message_start=3 |
| 23 | `8` | U+0038 | 3 | 0.56% |  | message_start=3 |
| 24 | `7` | U+0037 | 3 | 0.56% |  | message_start=3 |
| 25 | `3` | U+0033 | 3 | 0.56% |  | message_start=3 |
| 26 | `4` | U+0034 | 2 | 0.37% |  | message_start=2 |
| 27 | `k` | U+006B | 1 | 0.19% |  | message_start=1 |
| 28 | `u` | U+0075 | 1 | 0.19% |  | message_start=1 |
| 29 | `v` | U+0076 | 1 | 0.19% |  | message_start=1 |
| 30 | `9` | U+0039 | 1 | 0.19% |  | message_start=1 |

### AFTER_PUNCT target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 232 | 53.70% | yes |
| 2 | `s` | U+0073 | 35 | 8.10% | yes |
| 3 | `m` | U+006D | 27 | 6.25% | yes |
| 4 | `t` | U+0074 | 26 | 6.02% | yes |
| 5 | `r` | U+0072 | 11 | 2.55% |  |
| 6 | `n` | U+006E | 11 | 2.55% |  |
| 7 | `i` | U+0069 | 9 | 2.08% |  |
| 8 | `d` | U+0064 | 7 | 1.62% |  |
| 9 | `1` | U+0031 | 7 | 1.62% |  |
| 10 | `l` | U+006C | 6 | 1.39% |  |
| 11 | `v` | U+0076 | 6 | 1.39% |  |
| 12 | `a` | U+0061 | 5 | 1.16% |  |
| 13 | `p` | U+0070 | 5 | 1.16% |  |
| 14 | `5` | U+0035 | 5 | 1.16% |  |
| 15 | `b` | U+0062 | 4 | 0.93% |  |
| 16 | `y` | U+0079 | 4 | 0.93% |  |
| 17 | `g` | U+0067 | 4 | 0.93% |  |
| 18 | `8` | U+0038 | 3 | 0.69% |  |
| 19 | `f` | U+0066 | 3 | 0.69% |  |
| 20 | `o` | U+006F | 3 | 0.69% |  |
| 21 | `0` | U+0030 | 3 | 0.69% |  |
| 22 | `3` | U+0033 | 2 | 0.46% |  |
| 23 | `e` | U+0065 | 2 | 0.46% |  |
| 24 | `u` | U+0075 | 2 | 0.46% |  |
| 25 | `c` | U+0063 | 2 | 0.46% |  |
| 26 | `j` | U+006A | 2 | 0.46% |  |
| 27 | `4` | U+0034 | 2 | 0.46% |  |
| 28 | `9` | U+0039 | 1 | 0.23% |  |
| 29 | `7` | U+0037 | 1 | 0.23% |  |
| 30 | `w` | U+0077 | 1 | 0.23% |  |

## Bit cost breakdown — validation

| category | tokens | bits | share of total bits |
|---|---:|---:|---:|
| TOP-4 | 11089 | 33267 | 33.52% |
| Primary literal | 7364 | 51548 | 51.94% |
| Extension literal | 65 | 585 | 0.59% |
| SHIFT | 808 | 4040 | 4.07% |
| Punctuation | 610 | 4880 | 4.92% |
| Header | 548 | 4932 | 4.97% |

## Most expensive TOP-4 misses — validation

Sorted by avoidable bit cost relative to a hypothetical TOP-4 hit for the same target. SHIFT cost is excluded because it is paid in both cases.

| previous | next | tier | misses | literal bits | extra vs TOP-4 |
|---|---|---|---:|---:|---:|
| `SPACE` U+0020 | `h` U+0068 | primary | 161 | 7 | 644 |
| `SPACE` U+0020 | `m` U+006D | primary | 158 | 7 | 632 |
| `SPACE` U+0020 | `w` U+0077 | primary | 148 | 7 | 592 |
| `SPACE` U+0020 | `o` U+006F | primary | 140 | 7 | 560 |
| `SPACE` U+0020 | `b` U+0062 | primary | 136 | 7 | 544 |
| `SPACE` U+0020 | `d` U+0064 | primary | 123 | 7 | 492 |
| `SPACE` U+0020 | `f` U+0066 | primary | 122 | 7 | 488 |
| `SPACE` U+0020 | `c` U+0063 | primary | 114 | 7 | 456 |
| `SPACE` U+0020 | `r` U+0072 | primary | 106 | 7 | 424 |
| `o` U+006F | `o` U+006F | primary | 105 | 7 | 420 |
| `n` U+006E | `o` U+006F | primary | 104 | 7 | 416 |
| `e` U+0065 | `a` U+0061 | primary | 103 | 7 | 412 |
| `n` U+006E | `d` U+0064 | primary | 102 | 7 | 408 |
| `SPACE` U+0020 | `n` U+006E | primary | 97 | 7 | 388 |
| `SPACE` U+0020 | `l` U+006C | primary | 96 | 7 | 384 |
| `a` U+0061 | `r` U+0072 | primary | 95 | 7 | 380 |
| `e` U+0065 | `d` U+0064 | primary | 91 | 7 | 364 |
| `SPACE` U+0020 | `p` U+0070 | primary | 88 | 7 | 352 |
| `t` U+0074 | `i` U+0069 | primary | 86 | 7 | 344 |
| `o` U+006F | `m` U+006D | primary | 83 | 7 | 332 |
| `o` U+006F | `p` U+0070 | primary | 83 | 7 | 332 |
| `n` U+006E | `t` U+0074 | primary | 79 | 7 | 316 |
| `o` U+006F | `w` U+0077 | primary | 71 | 7 | 284 |
| `SPACE` U+0020 | `g` U+0067 | primary | 70 | 7 | 280 |
| `e` U+0065 | `e` U+0065 | primary | 69 | 7 | 276 |
| `o` U+006F | `t` U+0074 | primary | 69 | 7 | 276 |
| `e` U+0065 | `t` U+0074 | primary | 67 | 7 | 268 |
| `a` U+0061 | `s` U+0073 | primary | 65 | 7 | 260 |
| `SPACE` U+0020 | `y` U+0079 | primary | 64 | 7 | 256 |
| `o` U+006F | `d` U+0064 | primary | 64 | 7 | 256 |
| `e` U+0065 | `l` U+006C | primary | 63 | 7 | 252 |
| `e` U+0065 | `v` U+0076 | primary | 62 | 7 | 248 |
| `l` U+006C | `i` U+0069 | primary | 62 | 7 | 248 |
| `SPACE` U+0020 | `e` U+0065 | primary | 58 | 7 | 232 |
| `h` U+0068 | `SPACE` U+0020 | primary | 57 | 7 | 228 |
| `i` U+0069 | `g` U+0067 | primary | 55 | 7 | 220 |
| `a` U+0061 | `m` U+006D | primary | 54 | 7 | 216 |
| `r` U+0072 | `a` U+0061 | primary | 53 | 7 | 212 |
| `r` U+0072 | `i` U+0069 | primary | 49 | 7 | 196 |
| `h` U+0068 | `t` U+0074 | primary | 47 | 7 | 188 |

## Unsupported symbols in validation

| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 2 | U+2026 | `…` | HORIZONTAL ELLIPSIS |
| 1 | U+002A | `*` | ASTERISK |
| 1 | U+00B0 | `°` | DEGREE SIGN |

## Input files

### Train
- `corpora\en\meshcoretel-en.jsonl`
