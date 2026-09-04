# MCOtxt v1 model report — FR

## Build

- Language wire ID: `2`
- Unicode database: `15.1.0`
- Primary selection: `literal-savings`
- Canonical language symbols: `53`
- Primary: `32`
- Extension: `21`
- Total model symbols: `53`
- Prediction contexts: `START`, `AFTER_PUNCT`, `SYMBOL(previous)`
- Punctuation table: built-in MCOtxt v1 fallback; **not verified against punctuation.dart in this run**

## Training corpus

- Files: `1`
- Messages: `1221`
- UTF-8 bytes (message payloads): `39192`
- Normalized codepoints: `38154`
- Language symbols: `36579`
- Uppercase mapped: `1674`
- Punctuation: `1521`
- Unsupported: `54`
- Training TOP-4 hit rate: `60.15%`

## Validation

- Source: `deterministic SHA-256 hold-out (20.0%)`
- Explicit validation files: `0`
- Messages: `299`
- Original UTF-8 bytes: `9666`
- Normalized codepoints: `9429`
- Output codepoints: `9429`
- Skipped unsupported: `0`
- UTF-8 fallback runs: `16`
- UTF-8 fallback codepoints: `16`
- UTF-8 fallback bytes: `29`
- UTF-8 fallback bits: `456`
- Language symbols: `8971`
- TOP-4 hits: `5363` (`59.78%`)
- Primary literals: `3473`
- Extension literals: `135`
- SHIFT tokens: `416`
- Punctuation tokens: `442`
- Token bits: `46957`
- Header bits (12/message): `3588`
- Total bits: `50545`
- Bits/output-char, tokens only: `4.9801`
- Bits/output-char, incl. per-message header: `5.3606`
- UTF-8 bytes of the same decoded/supported text: `9666`
- Compression ratio vs same decoded UTF-8: `1.5299x`

> Validation here is single-language model evaluation. It includes real MCOtxt v1 variable TOP-4 / literal / SHIFT / punctuation / UTF8_RUN costs and a 12-bit normal MCOtxt header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.

## TOP-4 rank diagnostics — validation

| rank | hits | share of TOP-4 hits |
|---:|---:|---:|
| 0 | 2374 | 44.27% |
| 1 | 1345 | 25.08% |
| 2 | 909 | 16.95% |
| 3 | 735 | 13.71% |

> Variable TOP-4 is enabled in v1: rank 0 = 2 bits, rank 1 = 3 bits, ranks 2/3 = 4 bits. The table above shows the observed rank distribution.

## Final encoder candidate simulation — validation

This section simulates the final message-level selector between optimized normal MCOtxt (precomputed CAPS/SHIFT plan + fallback-only UTF8_RUN) and whole-message RAW_UTF8. It is intentionally separate from the model-only metrics above so TOP-4/model quality remains comparable between builds.

- Optimized MCOtxt candidate bits: `50208`
- Optimized MCOtxt candidate packed bytes: `6411`
- RAW_UTF8 candidate bits: `82112`
- RAW_UTF8 candidate packed bytes: `10264`
- Selected MCOtxt messages: `298`
- Selected RAW_UTF8 messages: `1`
- Optimized CAPS_MODE toggles in MCOtxt candidates: `31`
- Optimized one-symbol SHIFTs in MCOtxt candidates: `298`
- Optimized fallback UTF8_RUNs in MCOtxt candidates: `16`
- Final selected bits: `50190`
- Final selected packed bytes: `6408`
- Savings vs optimized MCOtxt: `3` bytes
- Selected ratio vs normalized UTF-8: `1.5407x`

> RAW_UTF8 simulation uses a `16`-bit byte-aligned message-mode header, matching the current Python A/B reference benchmark.

## Symbol index table

| idx | tier | symbol | codepoint | train count |
|---:|---|---|---|---:|
| 0 | primary | `SPACE` | U+0020 | 6141 |
| 1 | primary | `u` | U+0075 | 1831 |
| 2 | primary | `t` | U+0074 | 1969 |
| 3 | primary | `c` | U+0063 | 994 |
| 4 | primary | `m` | U+006D | 864 |
| 5 | primary | `r` | U+0072 | 1986 |
| 6 | primary | `l` | U+006C | 1404 |
| 7 | primary | `o` | U+006F | 2073 |
| 8 | primary | `i` | U+0069 | 2031 |
| 9 | primary | `e` | U+0065 | 4099 |
| 10 | primary | `a` | U+0061 | 2202 |
| 11 | primary | `s` | U+0073 | 2460 |
| 12 | primary | `n` | U+006E | 2088 |
| 13 | primary | `v` | U+0076 | 461 |
| 14 | primary | `p` | U+0070 | 984 |
| 15 | primary | `é` | U+00E9 | 385 |
| 16 | primary | `j` | U+006A | 352 |
| 17 | primary | `b` | U+0062 | 517 |
| 18 | primary | `d` | U+0064 | 841 |
| 19 | primary | `g` | U+0067 | 334 |
| 20 | primary | `h` | U+0068 | 462 |
| 21 | primary | `f` | U+0066 | 310 |
| 22 | primary | `q` | U+0071 | 257 |
| 23 | primary | `y` | U+0079 | 145 |
| 24 | primary | `ç` | U+00E7 | 135 |
| 25 | primary | `à` | U+00E0 | 118 |
| 26 | primary | `k` | U+006B | 96 |
| 27 | primary | `2` | U+0032 | 92 |
| 28 | primary | `x` | U+0078 | 85 |
| 29 | primary | `1` | U+0031 | 107 |
| 30 | primary | `5` | U+0035 | 80 |
| 31 | primary | `z` | U+007A | 79 |
| 32 | extension | `4` | U+0034 | 78 |
| 33 | extension | `w` | U+0077 | 46 |
| 34 | extension | `3` | U+0033 | 92 |
| 35 | extension | `7` | U+0037 | 60 |
| 36 | extension | `6` | U+0036 | 57 |
| 37 | extension | `è` | U+00E8 | 44 |
| 38 | extension | `0` | U+0030 | 69 |
| 39 | extension | `8` | U+0038 | 40 |
| 40 | extension | `ê` | U+00EA | 29 |
| 41 | extension | `9` | U+0039 | 47 |
| 42 | extension | `ô` | U+00F4 | 11 |
| 43 | extension | `î` | U+00EE | 7 |
| 44 | extension | `ù` | U+00F9 | 7 |
| 45 | extension | `û` | U+00FB | 4 |
| 46 | extension | `ü` | U+00FC | 4 |
| 47 | extension | `ë` | U+00EB | 1 |
| 48 | extension | `œ` | U+0153 | 1 |
| 49 | extension | `â` | U+00E2 | 0 |
| 50 | extension | `æ` | U+00E6 | 0 |
| 51 | extension | `ï` | U+00EF | 0 |
| 52 | extension | `ÿ` | U+00FF | 0 |

## START TOP-4

- `0` → index `17` → U+0062 'b' LATIN SMALL LETTER B
- `1` → index `11` → U+0073 's' LATIN SMALL LETTER S
- `2` → index `2` → U+0074 't' LATIN SMALL LETTER T
- `3` → index `3` → U+0063 'c' LATIN SMALL LETTER C

## AFTER_PUNCT TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `10` → U+0061 'a' LATIN SMALL LETTER A
- `2` → index `9` → U+0065 'e' LATIN SMALL LETTER E
- `3` → index `12` → U+006E 'n' LATIN SMALL LETTER N

## Prediction-context diagnostics

### Message begins with — training

| class | messages |
|---|---:|
| `language_symbol` | 1170 |
| `punctuation` | 49 |
| `unsupported` | 2 |

### Why a language symbol used START — training

| reason | transitions |
|---|---:|
| `message_start` | 1170 |
| `utf8_fallback` | 31 |

### START target frequencies — training

| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `b` | U+0062 | 169 | 14.07% | yes | message_start=168, utf8_fallback=1 |
| 2 | `s` | U+0073 | 103 | 8.58% | yes | message_start=103 |
| 3 | `t` | U+0074 | 94 | 7.83% | yes | message_start=94 |
| 4 | `c` | U+0063 | 89 | 7.41% | yes | message_start=88, utf8_fallback=1 |
| 5 | `h` | U+0068 | 79 | 6.58% |  | message_start=79 |
| 6 | `o` | U+006F | 78 | 6.49% |  | message_start=78 |
| 7 | `p` | U+0070 | 74 | 6.16% |  | message_start=74 |
| 8 | `j` | U+006A | 72 | 6.00% |  | message_start=72 |
| 9 | `m` | U+006D | 58 | 4.83% |  | message_start=56, utf8_fallback=2 |
| 10 | `a` | U+0061 | 43 | 3.58% |  | message_start=43 |
| 11 | `e` | U+0065 | 39 | 3.25% |  | message_start=35, utf8_fallback=4 |
| 12 | `r` | U+0072 | 38 | 3.16% |  | message_start=35, utf8_fallback=3 |
| 13 | `l` | U+006C | 32 | 2.66% |  | message_start=31, utf8_fallback=1 |
| 14 | `i` | U+0069 | 27 | 2.25% |  | message_start=27 |
| 15 | `d` | U+0064 | 24 | 2.00% |  | message_start=24 |
| 16 | `n` | U+006E | 22 | 1.83% |  | message_start=22 |
| 17 | `f` | U+0066 | 18 | 1.50% |  | message_start=18 |
| 18 | `ç` | U+00E7 | 17 | 1.42% |  | message_start=17 |
| 19 | `SPACE` | U+0020 | 16 | 1.33% |  | utf8_fallback=16 |
| 20 | `q` | U+0071 | 13 | 1.08% |  | message_start=13 |
| 21 | `y` | U+0079 | 13 | 1.08% |  | message_start=13 |
| 22 | `u` | U+0075 | 12 | 1.00% |  | message_start=11, utf8_fallback=1 |
| 23 | `g` | U+0067 | 11 | 0.92% |  | message_start=11 |
| 24 | `v` | U+0076 | 11 | 0.92% |  | message_start=10, utf8_fallback=1 |
| 25 | `w` | U+0077 | 10 | 0.83% |  | message_start=10 |
| 26 | `1` | U+0031 | 6 | 0.50% |  | message_start=6 |
| 27 | `k` | U+006B | 5 | 0.42% |  | message_start=5 |
| 28 | `4` | U+0034 | 5 | 0.42% |  | message_start=4, utf8_fallback=1 |
| 29 | `7` | U+0037 | 4 | 0.33% |  | message_start=4 |
| 30 | `6` | U+0036 | 4 | 0.33% |  | message_start=4 |

### AFTER_PUNCT target frequencies — training

| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 434 | 44.79% | yes |
| 2 | `a` | U+0061 | 120 | 12.38% | yes |
| 3 | `e` | U+0065 | 108 | 11.15% | yes |
| 4 | `n` | U+006E | 40 | 4.13% | yes |
| 5 | `o` | U+006F | 24 | 2.48% |  |
| 6 | `i` | U+0069 | 22 | 2.27% |  |
| 7 | `u` | U+0075 | 18 | 1.86% |  |
| 8 | `h` | U+0068 | 16 | 1.65% |  |
| 9 | `é` | U+00E9 | 16 | 1.65% |  |
| 10 | `m` | U+006D | 16 | 1.65% |  |
| 11 | `b` | U+0062 | 14 | 1.44% |  |
| 12 | `f` | U+0066 | 13 | 1.34% |  |
| 13 | `c` | U+0063 | 11 | 1.14% |  |
| 14 | `5` | U+0035 | 11 | 1.14% |  |
| 15 | `s` | U+0073 | 10 | 1.03% |  |
| 16 | `1` | U+0031 | 9 | 0.93% |  |
| 17 | `2` | U+0032 | 9 | 0.93% |  |
| 18 | `d` | U+0064 | 8 | 0.83% |  |
| 19 | `8` | U+0038 | 7 | 0.72% |  |
| 20 | `3` | U+0033 | 5 | 0.52% |  |
| 21 | `r` | U+0072 | 5 | 0.52% |  |
| 22 | `y` | U+0079 | 5 | 0.52% |  |
| 23 | `j` | U+006A | 5 | 0.52% |  |
| 24 | `0` | U+0030 | 5 | 0.52% |  |
| 25 | `l` | U+006C | 4 | 0.41% |  |
| 26 | `v` | U+0076 | 4 | 0.41% |  |
| 27 | `t` | U+0074 | 4 | 0.41% |  |
| 28 | `g` | U+0067 | 4 | 0.41% |  |
| 29 | `p` | U+0070 | 3 | 0.31% |  |
| 30 | `6` | U+0036 | 3 | 0.31% |  |

### Ordinary punctuation that led to AFTER_PUNCT — training

| punctuation | codepoint | following language contexts |
|---|---|---:|
| `,` | U+002C | 242 |
| `'` | U+0027 | 202 |
| `.` | U+002E | 116 |
| `’` | U+2019 | 109 |
| `:` | U+003A | 67 |
| `-` | U+002D | 59 |
| `\` | U+005C | 38 |
| `!` | U+0021 | 31 |
| `/` | U+002F | 24 |
| `?` | U+003F | 15 |
| `(` | U+0028 | 13 |
| `[` | U+005B | 10 |
| `]` | U+005D | 7 |
| `#` | U+0023 | 7 |
| `"` | U+0022 | 6 |
| `@` | U+0040 | 6 |
| `»` | U+00BB | 6 |
| `+` | U+002B | 5 |
| `)` | U+0029 | 2 |
| `_` | U+005F | 2 |
| `;` | U+003B | 1 |
| `&` | U+0026 | 1 |

### START target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `b` | U+0062 | 55 | 18.33% | yes | message_start=55 |
| 2 | `c` | U+0063 | 22 | 7.33% | yes | message_start=22 |
| 3 | `o` | U+006F | 20 | 6.67% |  | message_start=20 |
| 4 | `r` | U+0072 | 19 | 6.33% |  | message_start=18, utf8_fallback=1 |
| 5 | `h` | U+0068 | 18 | 6.00% |  | message_start=18 |
| 6 | `s` | U+0073 | 15 | 5.00% | yes | message_start=15 |
| 7 | `t` | U+0074 | 15 | 5.00% | yes | message_start=15 |
| 8 | `p` | U+0070 | 15 | 5.00% |  | message_start=15 |
| 9 | `j` | U+006A | 12 | 4.00% |  | message_start=12 |
| 10 | `m` | U+006D | 11 | 3.67% |  | message_start=11 |
| 11 | `SPACE` | U+0020 | 11 | 3.67% |  | utf8_fallback=11 |
| 12 | `a` | U+0061 | 10 | 3.33% |  | message_start=10 |
| 13 | `l` | U+006C | 9 | 3.00% |  | message_start=9 |
| 14 | `e` | U+0065 | 9 | 3.00% |  | message_start=9 |
| 15 | `ç` | U+00E7 | 7 | 2.33% |  | message_start=7 |
| 16 | `d` | U+0064 | 6 | 2.00% |  | message_start=6 |
| 17 | `n` | U+006E | 6 | 2.00% |  | message_start=5, utf8_fallback=1 |
| 18 | `u` | U+0075 | 5 | 1.67% |  | message_start=4, utf8_fallback=1 |
| 19 | `i` | U+0069 | 5 | 1.67% |  | message_start=5 |
| 20 | `y` | U+0079 | 4 | 1.33% |  | message_start=4 |
| 21 | `v` | U+0076 | 4 | 1.33% |  | message_start=4 |
| 22 | `3` | U+0033 | 4 | 1.33% |  | message_start=4 |
| 23 | `7` | U+0037 | 3 | 1.00% |  | message_start=3 |
| 24 | `8` | U+0038 | 3 | 1.00% |  | message_start=3 |
| 25 | `f` | U+0066 | 3 | 1.00% |  | message_start=3 |
| 26 | `1` | U+0031 | 2 | 0.67% |  | message_start=2 |
| 27 | `2` | U+0032 | 1 | 0.33% |  | message_start=1 |
| 28 | `w` | U+0077 | 1 | 0.33% |  | message_start=1 |
| 29 | `à` | U+00E0 | 1 | 0.33% |  | message_start=1 |
| 30 | `q` | U+0071 | 1 | 0.33% |  | message_start=1 |

### AFTER_PUNCT target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 127 | 43.79% | yes |
| 2 | `e` | U+0065 | 29 | 10.00% | yes |
| 3 | `a` | U+0061 | 24 | 8.28% | yes |
| 4 | `n` | U+006E | 14 | 4.83% | yes |
| 5 | `b` | U+0062 | 8 | 2.76% |  |
| 6 | `h` | U+0068 | 7 | 2.41% |  |
| 7 | `i` | U+0069 | 6 | 2.07% |  |
| 8 | `m` | U+006D | 6 | 2.07% |  |
| 9 | `o` | U+006F | 6 | 2.07% |  |
| 10 | `9` | U+0039 | 6 | 2.07% |  |
| 11 | `0` | U+0030 | 5 | 1.72% |  |
| 12 | `4` | U+0034 | 5 | 1.72% |  |
| 13 | `u` | U+0075 | 5 | 1.72% |  |
| 14 | `s` | U+0073 | 4 | 1.38% |  |
| 15 | `c` | U+0063 | 4 | 1.38% |  |
| 16 | `p` | U+0070 | 4 | 1.38% |  |
| 17 | `5` | U+0035 | 4 | 1.38% |  |
| 18 | `f` | U+0066 | 4 | 1.38% |  |
| 19 | `t` | U+0074 | 4 | 1.38% |  |
| 20 | `8` | U+0038 | 3 | 1.03% |  |
| 21 | `2` | U+0032 | 2 | 0.69% |  |
| 22 | `y` | U+0079 | 2 | 0.69% |  |
| 23 | `r` | U+0072 | 2 | 0.69% |  |
| 24 | `j` | U+006A | 2 | 0.69% |  |
| 25 | `l` | U+006C | 1 | 0.34% |  |
| 26 | `d` | U+0064 | 1 | 0.34% |  |
| 27 | `q` | U+0071 | 1 | 0.34% |  |
| 28 | `à` | U+00E0 | 1 | 0.34% |  |
| 29 | `1` | U+0031 | 1 | 0.34% |  |
| 30 | `k` | U+006B | 1 | 0.34% |  |

## Bit cost breakdown — validation

| category | tokens | bits | share of total bits |
|---|---:|---:|---:|
| TOP-4 variable | 5363 | 15359 | 30.39% |
| Primary literal | 3473 | 24311 | 48.10% |
| Extension literal | 135 | 1215 | 2.40% |
| SHIFT | 416 | 2080 | 4.12% |
| Punctuation | 442 | 3536 | 7.00% |
| UTF-8 fallback | 16 | 456 | 0.90% |
| Header | 299 | 3588 | 7.10% |

## UTF-8 fallback — validation

- Runs: `16`
- Unicode codepoints: `16`
- UTF-8 bytes: `29`
- Total fallback bits: `456`
- Share of total encoded bits: `0.90%`

| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 8 | U+007C | `'|'` | VERTICAL LINE |
| 5 | U+2026 | `…` | HORIZONTAL ELLIPSIS |
| 2 | U+00E4 | `ä` | LATIN SMALL LETTER A WITH DIAERESIS |
| 1 | U+00F6 | `ö` | LATIN SMALL LETTER O WITH DIAERESIS |

## Most expensive TOP-4 misses — validation

Sorted by avoidable bit cost relative to a hypothetical 3-bit TOP-4 reference hit for the same target. SHIFT cost is excluded because it is paid in both cases.

| previous | next | tier | misses | literal bits | extra vs TOP-4 |
|---|---|---|---:|---:|---:|
| `SPACE` U+0020 | `m` U+006D | primary | 103 | 7 | 412 |
| `SPACE` U+0020 | `c` U+0063 | primary | 82 | 7 | 328 |
| `SPACE` U+0020 | `t` U+0074 | primary | 72 | 7 | 288 |
| `SPACE` U+0020 | `r` U+0072 | primary | 68 | 7 | 272 |
| `SPACE` U+0020 | `a` U+0061 | primary | 67 | 7 | 268 |
| `SPACE` U+0020 | `e` U+0065 | primary | 59 | 7 | 236 |
| `a` U+0061 | `u` U+0075 | primary | 51 | 7 | 204 |
| `SPACE` U+0020 | `b` U+0062 | primary | 44 | 7 | 176 |
| `SPACE` U+0020 | `j` U+006A | primary | 44 | 7 | 176 |
| `s` U+0073 | `u` U+0075 | primary | 43 | 7 | 172 |
| `u` U+0075 | `s` U+0073 | primary | 42 | 7 | 168 |
| `a` U+0061 | `r` U+0072 | primary | 40 | 7 | 160 |
| `SPACE` U+0020 | `n` U+006E | primary | 38 | 7 | 152 |
| `SPACE` U+0020 | `q` U+0071 | primary | 38 | 7 | 152 |
| `SPACE` U+0020 | `f` U+0066 | primary | 37 | 7 | 148 |
| `s` U+0073 | `s` U+0073 | primary | 37 | 7 | 148 |
| `e` U+0065 | `t` U+0074 | primary | 36 | 7 | 144 |
| `e` U+0065 | `u` U+0075 | primary | 36 | 7 | 144 |
| `n` U+006E | `n` U+006E | primary | 35 | 7 | 140 |
| `SPACE` U+0020 | `v` U+0076 | primary | 34 | 7 | 136 |
| `i` U+0069 | `e` U+0065 | primary | 34 | 7 | 136 |
| `u` U+0075 | `n` U+006E | primary | 34 | 7 | 136 |
| `s` U+0073 | `o` U+006F | primary | 32 | 7 | 128 |
| `SPACE` U+0020 | `o` U+006F | primary | 31 | 7 | 124 |
| `u` U+0075 | `e` U+0065 | primary | 31 | 7 | 124 |
| `i` U+0069 | `t` U+0074 | primary | 29 | 7 | 116 |
| `o` U+006F | `p` U+0070 | primary | 29 | 7 | 116 |
| `t` U+0074 | `r` U+0072 | primary | 29 | 7 | 116 |
| `SPACE` U+0020 | `u` U+0075 | primary | 28 | 7 | 112 |
| `i` U+0069 | `o` U+006F | primary | 28 | 7 | 112 |
| `n` U+006E | `o` U+006F | primary | 28 | 7 | 112 |
| `a` U+0061 | `l` U+006C | primary | 27 | 7 | 108 |
| `e` U+0065 | `ç` U+00E7 | primary | 27 | 7 | 108 |
| `l` U+006C | `u` U+0075 | primary | 27 | 7 | 108 |
| `o` U+006F | `m` U+006D | primary | 27 | 7 | 108 |
| `a` U+0061 | `g` U+0067 | primary | 26 | 7 | 104 |
| `a` U+0061 | `t` U+0074 | primary | 26 | 7 | 104 |
| `i` U+0069 | `l` U+006C | primary | 26 | 7 | 104 |
| `r` U+0072 | `s` U+0073 | primary | 26 | 7 | 104 |
| `r` U+0072 | `i` U+0069 | primary | 25 | 7 | 100 |

## Unsupported symbols in validation

These symbols were encoded losslessly through UTF8_RUN during validation.
| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 8 | U+007C | `'|'` | VERTICAL LINE |
| 5 | U+2026 | `…` | HORIZONTAL ELLIPSIS |
| 2 | U+00E4 | `ä` | LATIN SMALL LETTER A WITH DIAERESIS |
| 1 | U+00F6 | `ö` | LATIN SMALL LETTER O WITH DIAERESIS |

## Input files

### Train
- `corpora\fr\meshcoretel-fr.jsonl`
