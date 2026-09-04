# MCOtxt v1 model report — DE

## Build

- Language wire ID: `3`
- Unicode database: `15.1.0`
- Primary selection: `literal-savings`
- Canonical language symbols: `41`
- Primary: `32`
- Extension: `9`
- Total model symbols: `41`
- Prediction contexts: `START`, `AFTER_PUNCT`, `SYMBOL(previous)`
- Punctuation table: built-in MCOtxt v1 fallback; **not verified against punctuation.dart in this run**

## Training corpus

- Files: `1`
- Messages: `2028`
- UTF-8 bytes (message payloads): `64820`
- Normalized codepoints: `63874`
- Language symbols: `61594`
- Uppercase mapped: `4432`
- Punctuation: `2205`
- Unsupported: `75`
- Training TOP-4 hit rate: `62.80%`

## Validation

- Source: `deterministic SHA-256 hold-out (20.0%)`
- Explicit validation files: `0`
- Messages: `585`
- Original UTF-8 bytes: `16878`
- Normalized codepoints: `16712`
- Output codepoints: `16712`
- Skipped unsupported: `0`
- UTF-8 fallback runs: `5`
- UTF-8 fallback codepoints: `6`
- UTF-8 fallback bytes: `6`
- UTF-8 fallback bits: `118`
- Language symbols: `16127`
- TOP-4 hits: `10049` (`62.31%`)
- Primary literals: `5928`
- Extension literals: `150`
- SHIFT tokens: `1150`
- Punctuation tokens: `579`
- Token bits: `82470`
- Header bits (12/message): `7020`
- Total bits: `89490`
- Bits/output-char, tokens only: `4.9348`
- Bits/output-char, incl. per-message header: `5.3548`
- UTF-8 bytes of the same decoded/supported text: `16878`
- Compression ratio vs same decoded UTF-8: `1.5088x`

> Validation here is single-language model evaluation. It includes real MCOtxt v1 variable TOP-4 / literal / SHIFT / punctuation / UTF8_RUN costs and a 12-bit normal MCOtxt header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.

## TOP-4 rank diagnostics — validation

| rank | hits | share of TOP-4 hits |
|---:|---:|---:|
| 0 | 4260 | 42.39% |
| 1 | 2552 | 25.40% |
| 2 | 1838 | 18.29% |
| 3 | 1399 | 13.92% |

> Variable TOP-4 is enabled in v1: rank 0 = 2 bits, rank 1 = 3 bits, ranks 2/3 = 4 bits. The table above shows the observed rank distribution.

## Final encoder candidate simulation — validation

This section simulates the final message-level selector between optimized normal MCOtxt (precomputed CAPS/SHIFT plan + fallback-only UTF8_RUN) and whole-message RAW_UTF8. It is intentionally separate from the model-only metrics above so TOP-4/model quality remains comparable between builds.

- Optimized MCOtxt candidate bits: `89258`
- Optimized MCOtxt candidate packed bytes: `11381`
- RAW_UTF8 candidate bits: `144384`
- RAW_UTF8 candidate packed bytes: `18048`
- Selected MCOtxt messages: `583`
- Selected RAW_UTF8 messages: `2`
- Optimized CAPS_MODE toggles in MCOtxt candidates: `29`
- Optimized one-symbol SHIFTs in MCOtxt candidates: `1066`
- Optimized fallback UTF8_RUNs in MCOtxt candidates: `5`
- Final selected bits: `89253`
- Final selected packed bytes: `11379`
- Savings vs optimized MCOtxt: `2` bytes
- Selected ratio vs normalized UTF-8: `1.5128x`

> RAW_UTF8 simulation uses a `16`-bit byte-aligned message-mode header, matching the current Python A/B reference benchmark.

## Symbol index table

| idx | tier | symbol | codepoint | train count |
|---:|---|---|---|---:|
| 0 | primary | `SPACE` | U+0020 | 8799 |
| 1 | primary | `s` | U+0073 | 3137 |
| 2 | primary | `t` | U+0074 | 3198 |
| 3 | primary | `b` | U+0062 | 1320 |
| 4 | primary | `h` | U+0068 | 2920 |
| 5 | primary | `o` | U+006F | 2062 |
| 6 | primary | `g` | U+0067 | 1668 |
| 7 | primary | `l` | U+006C | 1875 |
| 8 | primary | `i` | U+0069 | 3678 |
| 9 | primary | `m` | U+006D | 2007 |
| 10 | primary | `n` | U+006E | 5077 |
| 11 | primary | `r` | U+0072 | 3126 |
| 12 | primary | `u` | U+0075 | 2065 |
| 13 | primary | `w` | U+0077 | 799 |
| 14 | primary | `k` | U+006B | 828 |
| 15 | primary | `f` | U+0066 | 704 |
| 16 | primary | `e` | U+0065 | 7164 |
| 17 | primary | `c` | U+0063 | 1765 |
| 18 | primary | `a` | U+0061 | 3613 |
| 19 | primary | `d` | U+0064 | 2068 |
| 20 | primary | `z` | U+007A | 412 |
| 21 | primary | `p` | U+0070 | 670 |
| 22 | primary | `ü` | U+00FC | 368 |
| 23 | primary | `v` | U+0076 | 297 |
| 24 | primary | `j` | U+006A | 247 |
| 25 | primary | `ö` | U+00F6 | 158 |
| 26 | primary | `ä` | U+00E4 | 154 |
| 27 | primary | `1` | U+0031 | 199 |
| 28 | primary | `3` | U+0033 | 150 |
| 29 | primary | `2` | U+0032 | 123 |
| 30 | primary | `y` | U+0079 | 97 |
| 31 | primary | `5` | U+0035 | 81 |
| 32 | extension | `9` | U+0039 | 81 |
| 33 | extension | `4` | U+0034 | 79 |
| 34 | extension | `6` | U+0036 | 95 |
| 35 | extension | `7` | U+0037 | 91 |
| 36 | extension | `8` | U+0038 | 74 |
| 37 | extension | `ß` | U+00DF | 148 |
| 38 | extension | `x` | U+0078 | 43 |
| 39 | extension | `0` | U+0030 | 125 |
| 40 | extension | `q` | U+0071 | 29 |

## START TOP-4

- `0` → index `6` → U+0067 'g' LATIN SMALL LETTER G
- `1` → index `9` → U+006D 'm' LATIN SMALL LETTER M
- `2` → index `4` → U+0068 'h' LATIN SMALL LETTER H
- `3` → index `19` → U+0064 'd' LATIN SMALL LETTER D

## AFTER_PUNCT TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `3` → U+0062 'b' LATIN SMALL LETTER B
- `2` → index `19` → U+0064 'd' LATIN SMALL LETTER D
- `3` → index `18` → U+0061 'a' LATIN SMALL LETTER A

## Prediction-context diagnostics

### Message begins with — training

| class | messages |
|---|---:|
| `language_symbol` | 1989 |
| `punctuation` | 32 |
| `unsupported` | 7 |

### Why a language symbol used START — training

| reason | transitions |
|---|---:|
| `message_start` | 1989 |
| `newline` | 52 |
| `utf8_fallback` | 37 |

### START target frequencies — training

| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `g` | U+0067 | 333 | 16.03% | yes | message_start=323, newline=7, utf8_fallback=3 |
| 2 | `m` | U+006D | 281 | 13.52% | yes | message_start=280, utf8_fallback=1 |
| 3 | `h` | U+0068 | 215 | 10.35% | yes | message_start=209, newline=5, utf8_fallback=1 |
| 4 | `d` | U+0064 | 123 | 5.92% | yes | message_start=119, newline=3, utf8_fallback=1 |
| 5 | `i` | U+0069 | 106 | 5.10% |  | message_start=100, newline=5, utf8_fallback=1 |
| 6 | `s` | U+0073 | 105 | 5.05% |  | message_start=98, newline=3, utf8_fallback=4 |
| 7 | `a` | U+0061 | 96 | 4.62% |  | message_start=87, newline=9 |
| 8 | `j` | U+006A | 95 | 4.57% |  | message_start=95 |
| 9 | `w` | U+0077 | 94 | 4.52% |  | message_start=91, newline=3 |
| 10 | `n` | U+006E | 78 | 3.75% |  | message_start=72, newline=4, utf8_fallback=2 |
| 11 | `t` | U+0074 | 66 | 3.18% |  | message_start=64, utf8_fallback=2 |
| 12 | `b` | U+0062 | 60 | 2.89% |  | message_start=59, newline=1 |
| 13 | `o` | U+006F | 52 | 2.50% |  | message_start=52 |
| 14 | `k` | U+006B | 52 | 2.50% |  | message_start=52 |
| 15 | `e` | U+0065 | 42 | 2.02% |  | message_start=41, newline=1 |
| 16 | `u` | U+0075 | 34 | 1.64% |  | message_start=33, newline=1 |
| 17 | `1` | U+0031 | 24 | 1.15% |  | message_start=22, newline=1, utf8_fallback=1 |
| 18 | `f` | U+0066 | 22 | 1.06% |  | message_start=21, newline=1 |
| 19 | `v` | U+0076 | 22 | 1.06% |  | message_start=19, newline=3 |
| 20 | `l` | U+006C | 19 | 0.91% |  | message_start=18, newline=1 |
| 21 | `p` | U+0070 | 18 | 0.87% |  | message_start=17, newline=1 |
| 22 | `r` | U+0072 | 17 | 0.82% |  | message_start=15, newline=2 |
| 23 | `SPACE` | U+0020 | 17 | 0.82% |  | utf8_fallback=17 |
| 24 | `3` | U+0033 | 15 | 0.72% |  | message_start=15 |
| 25 | `c` | U+0063 | 14 | 0.67% |  | message_start=10, utf8_fallback=4 |
| 26 | `9` | U+0039 | 10 | 0.48% |  | message_start=10 |
| 27 | `4` | U+0034 | 10 | 0.48% |  | message_start=10 |
| 28 | `7` | U+0037 | 9 | 0.43% |  | message_start=8, newline=1 |
| 29 | `6` | U+0036 | 9 | 0.43% |  | message_start=9 |
| 30 | `2` | U+0032 | 9 | 0.43% |  | message_start=9 |

### AFTER_PUNCT target frequencies — training

| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 760 | 62.45% | yes |
| 2 | `b` | U+0062 | 50 | 4.11% | yes |
| 3 | `d` | U+0064 | 45 | 3.70% | yes |
| 4 | `a` | U+0061 | 36 | 2.96% | yes |
| 5 | `m` | U+006D | 34 | 2.79% |  |
| 6 | `s` | U+0073 | 29 | 2.38% |  |
| 7 | `t` | U+0074 | 25 | 2.05% |  |
| 8 | `w` | U+0077 | 17 | 1.40% |  |
| 9 | `h` | U+0068 | 16 | 1.31% |  |
| 10 | `e` | U+0065 | 15 | 1.23% |  |
| 11 | `n` | U+006E | 14 | 1.15% |  |
| 12 | `r` | U+0072 | 12 | 0.99% |  |
| 13 | `1` | U+0031 | 12 | 0.99% |  |
| 14 | `p` | U+0070 | 11 | 0.90% |  |
| 15 | `k` | U+006B | 11 | 0.90% |  |
| 16 | `c` | U+0063 | 10 | 0.82% |  |
| 17 | `0` | U+0030 | 10 | 0.82% |  |
| 18 | `g` | U+0067 | 10 | 0.82% |  |
| 19 | `3` | U+0033 | 9 | 0.74% |  |
| 20 | `5` | U+0035 | 9 | 0.74% |  |
| 21 | `o` | U+006F | 9 | 0.74% |  |
| 22 | `v` | U+0076 | 8 | 0.66% |  |
| 23 | `2` | U+0032 | 7 | 0.58% |  |
| 24 | `f` | U+0066 | 7 | 0.58% |  |
| 25 | `8` | U+0038 | 7 | 0.58% |  |
| 26 | `9` | U+0039 | 7 | 0.58% |  |
| 27 | `7` | U+0037 | 7 | 0.58% |  |
| 28 | `l` | U+006C | 6 | 0.49% |  |
| 29 | `4` | U+0034 | 5 | 0.41% |  |
| 30 | `i` | U+0069 | 5 | 0.41% |  |

### Ordinary punctuation that led to AFTER_PUNCT — training

| punctuation | codepoint | following language contexts |
|---|---|---:|
| `,` | U+002C | 353 |
| `.` | U+002E | 307 |
| `-` | U+002D | 164 |
| `?` | U+003F | 61 |
| `/` | U+002F | 50 |
| `#` | U+0023 | 43 |
| `:` | U+003A | 41 |
| `!` | U+0021 | 38 |
| `"` | U+0022 | 29 |
| `(` | U+0028 | 27 |
| `[` | U+005B | 18 |
| `@` | U+0040 | 18 |
| `'` | U+0027 | 16 |
| `)` | U+0029 | 14 |
| `]` | U+005D | 14 |
| `&` | U+0026 | 6 |
| `;` | U+003B | 4 |
| `„` | U+201E | 3 |
| `+` | U+002B | 3 |
| `=` | U+003D | 2 |
| `‘` | U+2018 | 2 |
| `’` | U+2019 | 1 |
| `«` | U+00AB | 1 |
| `»` | U+00BB | 1 |
| `“` | U+201C | 1 |

### START target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `m` | U+006D | 107 | 17.83% | yes | message_start=107 |
| 2 | `h` | U+0068 | 100 | 16.67% | yes | message_start=98, newline=2 |
| 3 | `g` | U+0067 | 73 | 12.17% | yes | message_start=70, newline=3 |
| 4 | `d` | U+0064 | 37 | 6.17% | yes | message_start=35, newline=2 |
| 5 | `w` | U+0077 | 30 | 5.00% |  | message_start=29, newline=1 |
| 6 | `i` | U+0069 | 28 | 4.67% |  | message_start=27, newline=1 |
| 7 | `s` | U+0073 | 25 | 4.17% |  | message_start=24, utf8_fallback=1 |
| 8 | `j` | U+006A | 25 | 4.17% |  | message_start=24, newline=1 |
| 9 | `e` | U+0065 | 19 | 3.17% |  | message_start=19 |
| 10 | `a` | U+0061 | 18 | 3.00% |  | message_start=17, newline=1 |
| 11 | `n` | U+006E | 18 | 3.00% |  | message_start=17, newline=1 |
| 12 | `1` | U+0031 | 15 | 2.50% |  | message_start=15 |
| 13 | `o` | U+006F | 14 | 2.33% |  | message_start=13, newline=1 |
| 14 | `b` | U+0062 | 11 | 1.83% |  | message_start=9, newline=2 |
| 15 | `f` | U+0066 | 11 | 1.83% |  | message_start=11 |
| 16 | `k` | U+006B | 10 | 1.67% |  | message_start=10 |
| 17 | `p` | U+0070 | 7 | 1.17% |  | message_start=7 |
| 18 | `t` | U+0074 | 7 | 1.17% |  | message_start=7 |
| 19 | `r` | U+0072 | 6 | 1.00% |  | message_start=4, newline=2 |
| 20 | `v` | U+0076 | 5 | 0.83% |  | message_start=4, newline=1 |
| 21 | `c` | U+0063 | 5 | 0.83% |  | message_start=4, utf8_fallback=1 |
| 22 | `8` | U+0038 | 4 | 0.67% |  | message_start=4 |
| 23 | `4` | U+0034 | 4 | 0.67% |  | message_start=3, utf8_fallback=1 |
| 24 | `7` | U+0037 | 3 | 0.50% |  | message_start=3 |
| 25 | `3` | U+0033 | 3 | 0.50% |  | message_start=3 |
| 26 | `z` | U+007A | 3 | 0.50% |  | message_start=3 |
| 27 | `6` | U+0036 | 2 | 0.33% |  | message_start=2 |
| 28 | `u` | U+0075 | 2 | 0.33% |  | message_start=2 |
| 29 | `2` | U+0032 | 2 | 0.33% |  | message_start=2 |
| 30 | `5` | U+0035 | 1 | 0.17% |  | message_start=1 |

### AFTER_PUNCT target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 182 | 56.17% | yes |
| 2 | `b` | U+0062 | 16 | 4.94% | yes |
| 3 | `m` | U+006D | 15 | 4.63% |  |
| 4 | `d` | U+0064 | 14 | 4.32% | yes |
| 5 | `s` | U+0073 | 10 | 3.09% |  |
| 6 | `t` | U+0074 | 9 | 2.78% |  |
| 7 | `p` | U+0070 | 9 | 2.78% |  |
| 8 | `n` | U+006E | 7 | 2.16% |  |
| 9 | `a` | U+0061 | 7 | 2.16% | yes |
| 10 | `w` | U+0077 | 6 | 1.85% |  |
| 11 | `f` | U+0066 | 5 | 1.54% |  |
| 12 | `o` | U+006F | 5 | 1.54% |  |
| 13 | `k` | U+006B | 4 | 1.23% |  |
| 14 | `2` | U+0032 | 4 | 1.23% |  |
| 15 | `u` | U+0075 | 3 | 0.93% |  |
| 16 | `r` | U+0072 | 3 | 0.93% |  |
| 17 | `g` | U+0067 | 3 | 0.93% |  |
| 18 | `v` | U+0076 | 3 | 0.93% |  |
| 19 | `h` | U+0068 | 2 | 0.62% |  |
| 20 | `1` | U+0031 | 2 | 0.62% |  |
| 21 | `c` | U+0063 | 2 | 0.62% |  |
| 22 | `l` | U+006C | 2 | 0.62% |  |
| 23 | `7` | U+0037 | 2 | 0.62% |  |
| 24 | `e` | U+0065 | 1 | 0.31% |  |
| 25 | `q` | U+0071 | 1 | 0.31% |  |
| 26 | `i` | U+0069 | 1 | 0.31% |  |
| 27 | `j` | U+006A | 1 | 0.31% |  |
| 28 | `4` | U+0034 | 1 | 0.31% |  |
| 29 | `0` | U+0030 | 1 | 0.31% |  |
| 30 | `9` | U+0039 | 1 | 0.31% |  |

## Bit cost breakdown — validation

| category | tokens | bits | share of total bits |
|---|---:|---:|---:|
| TOP-4 variable | 10049 | 29124 | 32.54% |
| Primary literal | 5928 | 41496 | 46.37% |
| Extension literal | 150 | 1350 | 1.51% |
| SHIFT | 1150 | 5750 | 6.43% |
| Punctuation | 579 | 4632 | 5.18% |
| UTF-8 fallback | 5 | 118 | 0.13% |
| Header | 585 | 7020 | 7.84% |

## UTF-8 fallback — validation

- Runs: `5`
- Unicode codepoints: `6`
- UTF-8 bytes: `6`
- Total fallback bits: `118`
- Share of total encoded bits: `0.13%`

| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 4 | U+002A | `*` | ASTERISK |
| 1 | U+0060 | `'`'` | GRAVE ACCENT |
| 1 | U+003E | `>` | GREATER-THAN SIGN |

## Most expensive TOP-4 misses — validation

Sorted by avoidable bit cost relative to a hypothetical 3-bit TOP-4 reference hit for the same target. SHIFT cost is excluded because it is paid in both cases.

| previous | next | tier | misses | literal bits | extra vs TOP-4 |
|---|---|---|---:|---:|---:|
| `SPACE` U+0020 | `h` U+0068 | primary | 144 | 7 | 576 |
| `SPACE` U+0020 | `s` U+0073 | primary | 124 | 7 | 496 |
| `SPACE` U+0020 | `n` U+006E | primary | 121 | 7 | 484 |
| `e` U+0065 | `s` U+0073 | primary | 121 | 7 | 484 |
| `SPACE` U+0020 | `w` U+0077 | primary | 107 | 7 | 428 |
| `SPACE` U+0020 | `b` U+0062 | primary | 101 | 7 | 404 |
| `SPACE` U+0020 | `g` U+0067 | primary | 92 | 7 | 368 |
| `SPACE` U+0020 | `e` U+0065 | primary | 90 | 7 | 360 |
| `e` U+0065 | `l` U+006C | primary | 80 | 7 | 320 |
| `i` U+0069 | `s` U+0073 | primary | 80 | 7 | 320 |
| `a` U+0061 | `b` U+0062 | primary | 75 | 7 | 300 |
| `l` U+006C | `o` U+006F | primary | 75 | 7 | 300 |
| `SPACE` U+0020 | `k` U+006B | primary | 74 | 7 | 296 |
| `a` U+0061 | `s` U+0073 | primary | 74 | 7 | 296 |
| `h` U+0068 | `o` U+006F | primary | 67 | 7 | 268 |
| `n` U+006E | `n` U+006E | primary | 62 | 7 | 248 |
| `m` U+006D | `SPACE` U+0020 | primary | 61 | 7 | 244 |
| `n` U+006E | `i` U+0069 | primary | 61 | 7 | 244 |
| `SPACE` U+0020 | `f` U+0066 | primary | 60 | 7 | 240 |
| `SPACE` U+0020 | `u` U+0075 | primary | 59 | 7 | 236 |
| `m` U+006D | `m` U+006D | primary | 58 | 7 | 232 |
| `n` U+006E | `g` U+0067 | primary | 58 | 7 | 232 |
| `o` U+006F | `m` U+006D | primary | 56 | 7 | 224 |
| `e` U+0065 | `h` U+0068 | primary | 54 | 7 | 216 |
| `n` U+006E | `t` U+0074 | primary | 54 | 7 | 216 |
| `e` U+0065 | `m` U+006D | primary | 50 | 7 | 200 |
| `a` U+0061 | `t` U+0074 | primary | 49 | 7 | 196 |
| `e` U+0065 | `t` U+0074 | primary | 49 | 7 | 196 |
| `h` U+0068 | `i` U+0069 | primary | 49 | 7 | 196 |
| `SPACE` U+0020 | `r` U+0072 | primary | 47 | 7 | 188 |
| `a` U+0061 | `r` U+0072 | primary | 45 | 7 | 180 |
| `h` U+0068 | `l` U+006C | primary | 44 | 7 | 176 |
| `SPACE` U+0020 | `l` U+006C | primary | 43 | 7 | 172 |
| `u` U+0075 | `c` U+0063 | primary | 43 | 7 | 172 |
| `SPACE` U+0020 | `v` U+0076 | primary | 41 | 7 | 164 |
| `o` U+006F | `SPACE` U+0020 | primary | 41 | 7 | 164 |
| `s` U+0073 | `h` U+0068 | primary | 41 | 7 | 164 |
| `n` U+006E | `k` U+006B | primary | 40 | 7 | 160 |
| `i` U+0069 | `r` U+0072 | primary | 39 | 7 | 156 |
| `s` U+0073 | `s` U+0073 | primary | 39 | 7 | 156 |

## Unsupported symbols in validation

These symbols were encoded losslessly through UTF8_RUN during validation.
| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 4 | U+002A | `*` | ASTERISK |
| 1 | U+0060 | `'`'` | GRAVE ACCENT |
| 1 | U+003E | `>` | GREATER-THAN SIGN |

## Input files

### Train
- `corpora\de\mcotxt_de_dataset_clean_no_leading_mentions.jsonl`
