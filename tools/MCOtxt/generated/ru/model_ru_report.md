# MCOtxt v1 model report — RU

## Build

- Language wire ID: `1`
- Unicode database: `15.1.0`
- Primary selection: `literal-savings`
- Canonical language symbols: `44`
- Primary: `32`
- Extension: `12`
- Total model symbols: `44`
- Prediction contexts: `START`, `AFTER_PUNCT`, `SYMBOL(previous)`
- Punctuation table: built-in MCOtxt v1 fallback; **not verified against punctuation.dart in this run**

## Training corpus

- Files: `2`
- Messages: `23121`
- UTF-8 bytes (message payloads): `1405541`
- Normalized codepoints: `788960`
- Language symbols: `738297`
- Uppercase mapped: `30602`
- Punctuation: `30815`
- Unsupported: `19848`
- Training TOP-4 hit rate: `57.10%`

## Validation

- Source: `deterministic SHA-256 hold-out (20.0%)`
- Explicit validation files: `0`
- Messages: `5626`
- Original UTF-8 bytes: `361814`
- Normalized codepoints: `203395`
- Output codepoints: `203395`
- Skipped unsupported: `0`
- UTF-8 fallback runs: `1537`
- UTF-8 fallback codepoints: `5381`
- UTF-8 fallback bytes: `5509`
- UTF-8 fallback bits: `65590`
- Language symbols: `190004`
- TOP-4 hits: `108374` (`57.04%`)
- Primary literals: `79501`
- Extension literals: `2129`
- SHIFT tokens: `7532`
- Punctuation tokens: `8010`
- Token bits: `1057981`
- Header bits (9/message): `50634`
- Total bits: `1108615`
- Bits/output-char, tokens only: `5.2016`
- Bits/output-char, incl. per-message header: `5.4506`
- UTF-8 bytes of the same decoded/supported text: `361814`
- Compression ratio vs same decoded UTF-8: `2.6109x`

> Validation here is single-language model evaluation. It includes real MCOtxt v1 variable TOP-4 / literal / SHIFT / punctuation / UTF8_RUN costs and a 9-bit normal MCOtxt header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.

## TOP-4 rank diagnostics — validation

| rank | hits | share of TOP-4 hits |
|---:|---:|---:|
| 0 | 46629 | 43.03% |
| 1 | 25255 | 23.30% |
| 2 | 20124 | 18.57% |
| 3 | 16366 | 15.10% |

> Variable TOP-4 is enabled in v1: rank 0 = 2 bits, rank 1 = 3 bits, ranks 2/3 = 4 bits. The table above shows the observed rank distribution.

## Final encoder candidate simulation — validation

This section simulates the final message-level selector between optimized normal MCOtxt (precomputed CAPS/SHIFT plan + fallback-only UTF8_RUN) and whole-message RAW_UTF8. It is intentionally separate from the model-only metrics above so TOP-4/model quality remains comparable between builds.

- Optimized MCOtxt candidate bits: `1107353`
- Optimized MCOtxt candidate packed bytes: `140931`
- RAW_UTF8 candidate bits: `2984528`
- RAW_UTF8 candidate packed bytes: `373066`
- Selected MCOtxt messages: `5618`
- Selected RAW_UTF8 messages: `8`
- Optimized CAPS_MODE toggles in MCOtxt candidates: `88`
- Optimized one-symbol SHIFTs in MCOtxt candidates: `7244`
- Optimized fallback UTF8_RUNs in MCOtxt candidates: `1537`
- Final selected bits: `1107153`
- Final selected packed bytes: `140902`
- Savings vs optimized MCOtxt: `29` bytes
- Selected ratio vs normalized UTF-8: `2.6144x`

> RAW_UTF8 simulation uses a `16`-bit byte-aligned message-mode header, matching the current Python A/B reference benchmark.

## Symbol index table

| idx | tier | symbol | codepoint | train count |
|---:|---|---|---|---:|
| 0 | primary | `SPACE` | U+0020 | 112631 |
| 1 | primary | `с` | U+0441 | 30664 |
| 2 | primary | `м` | U+043C | 18327 |
| 3 | primary | `у` | U+0443 | 17923 |
| 4 | primary | `р` | U+0440 | 30094 |
| 5 | primary | `к` | U+043A | 22181 |
| 6 | primary | `е` | U+0435 | 53184 |
| 7 | primary | `л` | U+043B | 22959 |
| 8 | primary | `н` | U+043D | 40882 |
| 9 | primary | `и` | U+0438 | 38001 |
| 10 | primary | `я` | U+044F | 12671 |
| 11 | primary | `т` | U+0442 | 46333 |
| 12 | primary | `б` | U+0431 | 11610 |
| 13 | primary | `д` | U+0434 | 20512 |
| 14 | primary | `в` | U+0432 | 23889 |
| 15 | primary | `г` | U+0433 | 10045 |
| 16 | primary | `ч` | U+0447 | 9791 |
| 17 | primary | `а` | U+0430 | 51336 |
| 18 | primary | `з` | U+0437 | 8885 |
| 19 | primary | `о` | U+043E | 67729 |
| 20 | primary | `ы` | U+044B | 9052 |
| 21 | primary | `п` | U+043F | 21677 |
| 22 | primary | `й` | U+0439 | 6726 |
| 23 | primary | `х` | U+0445 | 5383 |
| 24 | primary | `ж` | U+0436 | 6235 |
| 25 | primary | `ш` | U+0448 | 5698 |
| 26 | primary | `ю` | U+044E | 4107 |
| 27 | primary | `ь` | U+044C | 11357 |
| 28 | primary | `э` | U+044D | 2360 |
| 29 | primary | `щ` | U+0449 | 2175 |
| 30 | primary | `ц` | U+0446 | 1469 |
| 31 | primary | `ф` | U+0444 | 1369 |
| 32 | extension | `1` | U+0031 | 1774 |
| 33 | extension | `2` | U+0032 | 1411 |
| 34 | extension | `3` | U+0033 | 1177 |
| 35 | extension | `ё` | U+0451 | 1159 |
| 36 | extension | `4` | U+0034 | 1005 |
| 37 | extension | `5` | U+0035 | 904 |
| 38 | extension | `8` | U+0038 | 522 |
| 39 | extension | `7` | U+0037 | 533 |
| 40 | extension | `6` | U+0036 | 569 |
| 41 | extension | `9` | U+0039 | 421 |
| 42 | extension | `0` | U+0030 | 1472 |
| 43 | extension | `ъ` | U+044A | 95 |

## START TOP-4

- `0` → index `21` → U+043F 'п' CYRILLIC SMALL LETTER PE
- `1` → index `8` → U+043D 'н' CYRILLIC SMALL LETTER EN
- `2` → index `0` → U+0020 'SPACE' SPACE
- `3` → index `13` → U+0434 'д' CYRILLIC SMALL LETTER DE

## AFTER_PUNCT TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `11` → U+0442 'т' CYRILLIC SMALL LETTER TE
- `2` → index `32` → U+0031 '1' DIGIT ONE
- `3` → index `5` → U+043A 'к' CYRILLIC SMALL LETTER KA

## Prediction-context diagnostics

### Message begins with — training

| class | messages |
|---|---:|
| `language_symbol` | 22434 |
| `foreign_language` | 369 |
| `punctuation` | 214 |
| `unsupported` | 104 |

### Why a language symbol used START — training

| reason | transitions |
|---|---:|
| `message_start` | 22434 |
| `utf8_fallback` | 3427 |

### START target frequencies — training

| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `п` | U+043F | 3461 | 13.38% | yes | message_start=3427, utf8_fallback=34 |
| 2 | `н` | U+043D | 2244 | 8.68% | yes | message_start=2209, utf8_fallback=35 |
| 3 | `SPACE` | U+0020 | 2126 | 8.22% | yes | utf8_fallback=2126 |
| 4 | `д` | U+0434 | 1957 | 7.57% | yes | message_start=1935, utf8_fallback=22 |
| 5 | `в` | U+0432 | 1937 | 7.49% |  | message_start=1903, utf8_fallback=34 |
| 6 | `с` | U+0441 | 1418 | 5.48% |  | message_start=1403, utf8_fallback=15 |
| 7 | `а` | U+0430 | 1401 | 5.42% |  | message_start=1385, utf8_fallback=16 |
| 8 | `т` | U+0442 | 1372 | 5.31% |  | message_start=1347, utf8_fallback=25 |
| 9 | `к` | U+043A | 1040 | 4.02% |  | message_start=1017, utf8_fallback=23 |
| 10 | `о` | U+043E | 864 | 3.34% |  | message_start=854, utf8_fallback=10 |
| 11 | `у` | U+0443 | 859 | 3.32% |  | message_start=848, utf8_fallback=11 |
| 12 | `я` | U+044F | 784 | 3.03% |  | message_start=775, utf8_fallback=9 |
| 13 | `м` | U+043C | 732 | 2.83% |  | message_start=713, utf8_fallback=19 |
| 14 | `и` | U+0438 | 604 | 2.34% |  | message_start=594, utf8_fallback=10 |
| 15 | `ч` | U+0447 | 493 | 1.91% |  | message_start=487, utf8_fallback=6 |
| 16 | `е` | U+0435 | 462 | 1.79% |  | message_start=456, utf8_fallback=6 |
| 17 | `э` | U+044D | 453 | 1.75% |  | message_start=448, utf8_fallback=5 |
| 18 | `з` | U+0437 | 439 | 1.70% |  | message_start=421, utf8_fallback=18 |
| 19 | `б` | U+0431 | 389 | 1.50% |  | message_start=383, utf8_fallback=6 |
| 20 | `р` | U+0440 | 373 | 1.44% |  | message_start=363, utf8_fallback=10 |
| 21 | `4` | U+0034 | 291 | 1.13% |  | message_start=63, utf8_fallback=228 |
| 22 | `х` | U+0445 | 277 | 1.07% |  | message_start=273, utf8_fallback=4 |
| 23 | `3` | U+0033 | 274 | 1.06% |  | message_start=92, utf8_fallback=182 |
| 24 | `1` | U+0031 | 262 | 1.01% |  | message_start=118, utf8_fallback=144 |
| 25 | `г` | U+0433 | 248 | 0.96% |  | message_start=244, utf8_fallback=4 |
| 26 | `2` | U+0032 | 229 | 0.89% |  | message_start=113, utf8_fallback=116 |
| 27 | `л` | U+043B | 165 | 0.64% |  | message_start=154, utf8_fallback=11 |
| 28 | `5` | U+0035 | 118 | 0.46% |  | message_start=37, utf8_fallback=81 |
| 29 | `ж` | U+0436 | 85 | 0.33% |  | message_start=84, utf8_fallback=1 |
| 30 | `ш` | U+0448 | 78 | 0.30% |  | message_start=72, utf8_fallback=6 |

### AFTER_PUNCT target frequencies — training

| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 12978 | 81.55% | yes |
| 2 | `т` | U+0442 | 426 | 2.68% | yes |
| 3 | `1` | U+0031 | 258 | 1.62% | yes |
| 4 | `к` | U+043A | 173 | 1.09% | yes |
| 5 | `с` | U+0441 | 164 | 1.03% |  |
| 6 | `н` | U+043D | 137 | 0.86% |  |
| 7 | `п` | U+043F | 133 | 0.84% |  |
| 8 | `3` | U+0033 | 123 | 0.77% |  |
| 9 | `2` | U+0032 | 119 | 0.75% |  |
| 10 | `5` | U+0035 | 113 | 0.71% |  |
| 11 | `в` | U+0432 | 95 | 0.60% |  |
| 12 | `4` | U+0034 | 92 | 0.58% |  |
| 13 | `0` | U+0030 | 84 | 0.53% |  |
| 14 | `м` | U+043C | 81 | 0.51% |  |
| 15 | `з` | U+0437 | 80 | 0.50% |  |
| 16 | `7` | U+0037 | 78 | 0.49% |  |
| 17 | `9` | U+0039 | 67 | 0.42% |  |
| 18 | `о` | U+043E | 65 | 0.41% |  |
| 19 | `8` | U+0038 | 61 | 0.38% |  |
| 20 | `д` | U+0434 | 54 | 0.34% |  |
| 21 | `а` | U+0430 | 53 | 0.33% |  |
| 22 | `6` | U+0036 | 51 | 0.32% |  |
| 23 | `л` | U+043B | 49 | 0.31% |  |
| 24 | `р` | U+0440 | 48 | 0.30% |  |
| 25 | `и` | U+0438 | 45 | 0.28% |  |
| 26 | `ч` | U+0447 | 39 | 0.25% |  |
| 27 | `х` | U+0445 | 37 | 0.23% |  |
| 28 | `е` | U+0435 | 36 | 0.23% |  |
| 29 | `б` | U+0431 | 35 | 0.22% |  |
| 30 | `я` | U+044F | 35 | 0.22% |  |

### Ordinary punctuation that led to AFTER_PUNCT — training

| punctuation | codepoint | following language contexts |
|---|---|---:|
| `,` | U+002C | 7222 |
| `.` | U+002E | 4044 |
| `-` | U+002D | 1886 |
| `?` | U+003F | 682 |
| `)` | U+0029 | 436 |
| `!` | U+0021 | 347 |
| `"` | U+0022 | 257 |
| `/` | U+002F | 216 |
| `:` | U+003A | 206 |
| `(` | U+0028 | 191 |
| `+` | U+002B | 142 |
| `%` | U+0025 | 56 |
| `]` | U+005D | 43 |
| `[` | U+005B | 35 |
| `«` | U+00AB | 32 |
| `=` | U+003D | 25 |
| `»` | U+00BB | 21 |
| `_` | U+005F | 16 |
| `—` | U+2014 | 16 |
| `#` | U+0023 | 11 |
| `'` | U+0027 | 10 |
| `\` | U+005C | 7 |
| `;` | U+003B | 6 |
| `@` | U+0040 | 4 |
| `&` | U+0026 | 4 |

### START target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `п` | U+043F | 681 | 10.69% | yes | message_start=674, utf8_fallback=7 |
| 2 | `SPACE` | U+0020 | 586 | 9.20% | yes | utf8_fallback=586 |
| 3 | `н` | U+043D | 567 | 8.90% | yes | message_start=554, utf8_fallback=13 |
| 4 | `д` | U+0434 | 548 | 8.60% | yes | message_start=548 |
| 5 | `в` | U+0432 | 473 | 7.42% |  | message_start=464, utf8_fallback=9 |
| 6 | `а` | U+0430 | 352 | 5.52% |  | message_start=348, utf8_fallback=4 |
| 7 | `с` | U+0441 | 338 | 5.30% |  | message_start=332, utf8_fallback=6 |
| 8 | `т` | U+0442 | 316 | 4.96% |  | message_start=310, utf8_fallback=6 |
| 9 | `к` | U+043A | 238 | 3.74% |  | message_start=235, utf8_fallback=3 |
| 10 | `о` | U+043E | 230 | 3.61% |  | message_start=229, utf8_fallback=1 |
| 11 | `у` | U+0443 | 228 | 3.58% |  | message_start=225, utf8_fallback=3 |
| 12 | `и` | U+0438 | 182 | 2.86% |  | message_start=176, utf8_fallback=6 |
| 13 | `я` | U+044F | 173 | 2.72% |  | message_start=173 |
| 14 | `м` | U+043C | 166 | 2.61% |  | message_start=159, utf8_fallback=7 |
| 15 | `ч` | U+0447 | 122 | 1.91% |  | message_start=120, utf8_fallback=2 |
| 16 | `р` | U+0440 | 108 | 1.69% |  | message_start=107, utf8_fallback=1 |
| 17 | `е` | U+0435 | 108 | 1.69% |  | message_start=106, utf8_fallback=2 |
| 18 | `э` | U+044D | 104 | 1.63% |  | message_start=103, utf8_fallback=1 |
| 19 | `з` | U+0437 | 97 | 1.52% |  | message_start=96, utf8_fallback=1 |
| 20 | `б` | U+0431 | 92 | 1.44% |  | message_start=91, utf8_fallback=1 |
| 21 | `1` | U+0031 | 87 | 1.37% |  | message_start=45, utf8_fallback=42 |
| 22 | `г` | U+0433 | 82 | 1.29% |  | message_start=80, utf8_fallback=2 |
| 23 | `4` | U+0034 | 81 | 1.27% |  | message_start=12, utf8_fallback=69 |
| 24 | `х` | U+0445 | 67 | 1.05% |  | message_start=67 |
| 25 | `2` | U+0032 | 66 | 1.04% |  | message_start=31, utf8_fallback=35 |
| 26 | `3` | U+0033 | 61 | 0.96% |  | message_start=20, utf8_fallback=41 |
| 27 | `л` | U+043B | 48 | 0.75% |  | message_start=48 |
| 28 | `5` | U+0035 | 27 | 0.42% |  | message_start=13, utf8_fallback=14 |
| 29 | `9` | U+0039 | 23 | 0.36% |  | message_start=7, utf8_fallback=16 |
| 30 | `0` | U+0030 | 22 | 0.35% |  | message_start=7, utf8_fallback=15 |

### AFTER_PUNCT target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 3521 | 83.38% | yes |
| 2 | `т` | U+0442 | 105 | 2.49% | yes |
| 3 | `1` | U+0031 | 60 | 1.42% | yes |
| 4 | `3` | U+0033 | 40 | 0.95% |  |
| 5 | `н` | U+043D | 36 | 0.85% |  |
| 6 | `с` | U+0441 | 36 | 0.85% |  |
| 7 | `п` | U+043F | 33 | 0.78% |  |
| 8 | `к` | U+043A | 28 | 0.66% | yes |
| 9 | `4` | U+0034 | 22 | 0.52% |  |
| 10 | `2` | U+0032 | 22 | 0.52% |  |
| 11 | `5` | U+0035 | 22 | 0.52% |  |
| 12 | `0` | U+0030 | 22 | 0.52% |  |
| 13 | `р` | U+0440 | 21 | 0.50% |  |
| 14 | `9` | U+0039 | 21 | 0.50% |  |
| 15 | `8` | U+0038 | 19 | 0.45% |  |
| 16 | `в` | U+0432 | 18 | 0.43% |  |
| 17 | `д` | U+0434 | 18 | 0.43% |  |
| 18 | `7` | U+0037 | 17 | 0.40% |  |
| 19 | `а` | U+0430 | 16 | 0.38% |  |
| 20 | `о` | U+043E | 15 | 0.36% |  |
| 21 | `б` | U+0431 | 13 | 0.31% |  |
| 22 | `з` | U+0437 | 13 | 0.31% |  |
| 23 | `г` | U+0433 | 12 | 0.28% |  |
| 24 | `м` | U+043C | 12 | 0.28% |  |
| 25 | `6` | U+0036 | 11 | 0.26% |  |
| 26 | `ч` | U+0447 | 10 | 0.24% |  |
| 27 | `е` | U+0435 | 9 | 0.21% |  |
| 28 | `х` | U+0445 | 9 | 0.21% |  |
| 29 | `у` | U+0443 | 6 | 0.14% |  |
| 30 | `л` | U+043B | 6 | 0.14% |  |

## Bit cost breakdown — validation

| category | tokens | bits | share of total bits |
|---|---:|---:|---:|
| TOP-4 variable | 108374 | 314983 | 28.41% |
| Primary literal | 79501 | 556507 | 50.20% |
| Extension literal | 2129 | 19161 | 1.73% |
| SHIFT | 7532 | 37660 | 3.40% |
| Punctuation | 8010 | 64080 | 5.78% |
| UTF-8 fallback | 1537 | 65590 | 5.92% |
| Header | 5626 | 50634 | 4.57% |

## UTF-8 fallback — validation

- Runs: `1537`
- Unicode codepoints: `5381`
- UTF-8 bytes: `5509`
- Total fallback bits: `65590`
- Share of total encoded bits: `5.92%`

| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 494 | U+0074 | `t` | LATIN SMALL LETTER T |
| 465 | U+0065 | `e` | LATIN SMALL LETTER E |
| 353 | U+0072 | `r` | LATIN SMALL LETTER R |
| 310 | U+0061 | `a` | LATIN SMALL LETTER A |
| 278 | U+006F | `o` | LATIN SMALL LETTER O |
| 277 | U+006E | `n` | LATIN SMALL LETTER N |
| 243 | U+0073 | `s` | LATIN SMALL LETTER S |
| 218 | U+0069 | `i` | LATIN SMALL LETTER I |
| 188 | U+0064 | `d` | LATIN SMALL LETTER D |
| 169 | U+006C | `l` | LATIN SMALL LETTER L |
| 167 | U+0063 | `c` | LATIN SMALL LETTER C |
| 159 | U+0070 | `p` | LATIN SMALL LETTER P |
| 146 | U+006D | `m` | LATIN SMALL LETTER M |
| 146 | U+0068 | `h` | LATIN SMALL LETTER H |
| 136 | U+0075 | `u` | LATIN SMALL LETTER U |
| 130 | U+0066 | `f` | LATIN SMALL LETTER F |
| 99 | U+0076 | `v` | LATIN SMALL LETTER V |
| 83 | U+006B | `k` | LATIN SMALL LETTER K |
| 79 | U+0067 | `g` | LATIN SMALL LETTER G |
| 78 | U+004D | `M` | LATIN CAPITAL LETTER M |
| 74 | U+0062 | `b` | LATIN SMALL LETTER B |
| 67 | U+0052 | `R` | LATIN CAPITAL LETTER R |
| 61 | U+0044 | `D` | LATIN CAPITAL LETTER D |
| 60 | U+0053 | `S` | LATIN CAPITAL LETTER S |
| 59 | U+0079 | `y` | LATIN SMALL LETTER Y |
| 57 | U+0077 | `w` | LATIN SMALL LETTER W |
| 50 | U+0041 | `A` | LATIN CAPITAL LETTER A |
| 48 | U+0054 | `T` | LATIN CAPITAL LETTER T |
| 45 | U+0050 | `P` | LATIN CAPITAL LETTER P |
| 38 | U+0043 | `C` | LATIN CAPITAL LETTER C |
| 38 | U+0047 | `G` | LATIN CAPITAL LETTER G |
| 38 | U+004B | `K` | LATIN CAPITAL LETTER K |
| 35 | U+0046 | `F` | LATIN CAPITAL LETTER F |
| 35 | U+0048 | `H` | LATIN CAPITAL LETTER H |
| 31 | U+0056 | `V` | LATIN CAPITAL LETTER V |
| 30 | U+0078 | `x` | LATIN SMALL LETTER X |
| 30 | U+004E | `N` | LATIN CAPITAL LETTER N |
| 28 | U+0045 | `E` | LATIN CAPITAL LETTER E |
| 26 | U+004F | `O` | LATIN CAPITAL LETTER O |
| 24 | U+0049 | `I` | LATIN CAPITAL LETTER I |
| 23 | U+2026 | `…` | HORIZONTAL ELLIPSIS |
| 22 | U+004C | `L` | LATIN CAPITAL LETTER L |
| 22 | U+007A | `z` | LATIN SMALL LETTER Z |
| 22 | U+0042 | `B` | LATIN CAPITAL LETTER B |
| 19 | U+0057 | `W` | LATIN CAPITAL LETTER W |
| 19 | U+0051 | `Q` | LATIN CAPITAL LETTER Q |
| 17 | U+002A | `*` | ASTERISK |
| 14 | U+0055 | `U` | LATIN CAPITAL LETTER U |
| 14 | U+00EB | `ë` | LATIN SMALL LETTER E WITH DIAERESIS |
| 12 | U+0071 | `q` | LATIN SMALL LETTER Q |
| 10 | U+0058 | `X` | LATIN CAPITAL LETTER X |
| 10 | U+0059 | `Y` | LATIN CAPITAL LETTER Y |
| 10 | U+00B0 | `°` | DEGREE SIGN |
| 9 | U+003E | `>` | GREATER-THAN SIGN |
| 8 | U+006A | `j` | LATIN SMALL LETTER J |
| 7 | U+005A | `Z` | LATIN CAPITAL LETTER Z |
| 7 | U+004A | `J` | LATIN CAPITAL LETTER J |
| 6 | U+007E | `~` | TILDE |
| 3 | U+003C | `<` | LESS-THAN SIGN |
| 3 | U+3064 | `つ` | HIRAGANA LETTER TU |
| 2 | U+00AF | `¯` | MACRON |
| 2 | U+2060 | `'\u2060'` | WORD JOINER |
| 2 | U+FF3C | `＼` | FULLWIDTH REVERSE SOLIDUS |
| 2 | U+FF0F | `／` | FULLWIDTH SOLIDUS |
| 1 | U+2248 | `≈` | ALMOST EQUAL TO |
| 1 | U+30C4 | `ツ` | KATAKANA LETTER TU |
| 1 | U+0532 | `Բ` | ARMENIAN CAPITAL LETTER BEN |
| 1 | U+0561 | `ա` | ARMENIAN SMALL LETTER AYB |
| 1 | U+0580 | `ր` | ARMENIAN SMALL LETTER REH |
| 1 | U+0587 | `և` | ARMENIAN SMALL LIGATURE ECH YIWN |
| 1 | U+0571 | `ձ` | ARMENIAN SMALL LETTER JA |
| 1 | U+0565 | `ե` | ARMENIAN SMALL LETTER ECH |
| 1 | U+0566 | `զ` | ARMENIAN SMALL LETTER ZA |
| 1 | U+3063 | `っ` | HIRAGANA LETTER SMALL TU |
| 1 | U+1559 | `ᕙ` | CANADIAN SYLLABICS FA |
| 1 | U+0300 | `̀` | COMBINING GRAVE ACCENT |
| 1 | U+15DC | `ᗜ` | CANADIAN SYLLABICS CARRIER THU |
| 1 | U+0301 | `́` | COMBINING ACUTE ACCENT |
| 1 | U+1557 | `ᕗ` | CANADIAN SYLLABICS FO |
| 1 | U+0F3C | `༼` | TIBETAN MARK ANG KHANG GYON |
| 1 | U+0F3D | `༽` | TIBETAN MARK ANG KHANG GYAS |
| 1 | U+30E9 | `ラ` | KATAKANA LETTER RA |
| 1 | U+30D6 | `ブ` | KATAKANA LETTER BU |
| 1 | U+30C6 | `テ` | KATAKANA LETTER TE |
| 1 | U+30B9 | `ス` | KATAKANA LETTER SU |
| 1 | U+30BF | `タ` | KATAKANA LETTER TA |
| 1 | U+30FC | `ー` | KATAKANA-HIRAGANA PROLONGED SOUND MARK |
| 1 | U+0101 | `ā` | LATIN SMALL LETTER A WITH MACRON |

## Most expensive TOP-4 misses — validation

Sorted by avoidable bit cost relative to a hypothetical 3-bit TOP-4 reference hit for the same target. SHIFT cost is excluded because it is paid in both cases.

| previous | next | tier | misses | literal bits | extra vs TOP-4 |
|---|---|---|---:|---:|---:|
| `SPACE` U+0020 | `т` U+0442 | primary | 1575 | 7 | 6300 |
| `SPACE` U+0020 | `д` U+0434 | primary | 1380 | 7 | 5520 |
| `SPACE` U+0020 | `к` U+043A | primary | 1378 | 7 | 5512 |
| `SPACE` U+0020 | `м` U+043C | primary | 1253 | 7 | 5012 |
| `т` U+0442 | `е` U+0435 | primary | 1193 | 7 | 4772 |
| `SPACE` U+0020 | `и` U+0438 | primary | 1172 | 7 | 4688 |
| `SPACE` U+0020 | `р` U+0440 | primary | 1120 | 7 | 4480 |
| `SPACE` U+0020 | `о` U+043E | primary | 1108 | 7 | 4432 |
| `о` U+043E | `б` U+0431 | primary | 1050 | 7 | 4200 |
| `SPACE` U+0020 | `б` U+0431 | primary | 976 | 7 | 3904 |
| `е` U+0435 | `с` U+0441 | primary | 851 | 7 | 3404 |
| `о` U+043E | `л` U+043B | primary | 840 | 7 | 3360 |
| `а` U+0430 | `с` U+0441 | primary | 833 | 7 | 3332 |
| `о` U+043E | `р` U+0440 | primary | 830 | 7 | 3320 |
| `о` U+043E | `с` U+0441 | primary | 825 | 7 | 3300 |
| `SPACE` U+0020 | `ч` U+0447 | primary | 817 | 7 | 3268 |
| `SPACE` U+0020 | `з` U+0437 | primary | 790 | 7 | 3160 |
| `SPACE` U+0020 | `у` U+0443 | primary | 762 | 7 | 3048 |
| `о` U+043E | `м` U+043C | primary | 761 | 7 | 3044 |
| `о` U+043E | `н` U+043D | primary | 738 | 7 | 2952 |
| `т` U+0442 | `р` U+0440 | primary | 736 | 7 | 2944 |
| `е` U+0435 | `м` U+043C | primary | 711 | 7 | 2844 |
| `о` U+043E | `г` U+0433 | primary | 689 | 7 | 2756 |
| `е` U+0435 | `л` U+043B | primary | 687 | 7 | 2748 |
| `а` U+0430 | `н` U+043D | primary | 653 | 7 | 2612 |
| `а` U+0430 | `в` U+0432 | primary | 644 | 7 | 2576 |
| `т` U+0442 | `и` U+0438 | primary | 596 | 7 | 2384 |
| `о` U+043E | `й` U+0439 | primary | 579 | 7 | 2316 |
| `н` U+043D | `у` U+0443 | primary | 577 | 7 | 2308 |
| `л` U+043B | `а` U+0430 | primary | 551 | 7 | 2204 |
| `а` U+0430 | `м` U+043C | primary | 547 | 7 | 2188 |
| `о` U+043E | `ж` U+0436 | primary | 529 | 7 | 2116 |
| `SPACE` U+0020 | `а` U+0430 | primary | 526 | 7 | 2104 |
| `с` U+0441 | `я` U+044F | primary | 525 | 7 | 2100 |
| `н` U+043D | `я` U+044F | primary | 522 | 7 | 2088 |
| `с` U+0441 | `к` U+043A | primary | 519 | 7 | 2076 |
| `в` U+0432 | `с` U+0441 | primary | 514 | 7 | 2056 |
| `л` U+043B | `SPACE` U+0020 | primary | 499 | 7 | 1996 |
| `SPACE` U+0020 | `е` U+0435 | primary | 498 | 7 | 1992 |
| `в` U+0432 | `и` U+0438 | primary | 497 | 7 | 1988 |

## Unsupported symbols in validation

These symbols were encoded losslessly through UTF8_RUN during validation.
| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 494 | U+0074 | `t` | LATIN SMALL LETTER T |
| 465 | U+0065 | `e` | LATIN SMALL LETTER E |
| 353 | U+0072 | `r` | LATIN SMALL LETTER R |
| 310 | U+0061 | `a` | LATIN SMALL LETTER A |
| 278 | U+006F | `o` | LATIN SMALL LETTER O |
| 277 | U+006E | `n` | LATIN SMALL LETTER N |
| 243 | U+0073 | `s` | LATIN SMALL LETTER S |
| 218 | U+0069 | `i` | LATIN SMALL LETTER I |
| 188 | U+0064 | `d` | LATIN SMALL LETTER D |
| 169 | U+006C | `l` | LATIN SMALL LETTER L |
| 167 | U+0063 | `c` | LATIN SMALL LETTER C |
| 159 | U+0070 | `p` | LATIN SMALL LETTER P |
| 146 | U+006D | `m` | LATIN SMALL LETTER M |
| 146 | U+0068 | `h` | LATIN SMALL LETTER H |
| 136 | U+0075 | `u` | LATIN SMALL LETTER U |
| 130 | U+0066 | `f` | LATIN SMALL LETTER F |
| 99 | U+0076 | `v` | LATIN SMALL LETTER V |
| 83 | U+006B | `k` | LATIN SMALL LETTER K |
| 79 | U+0067 | `g` | LATIN SMALL LETTER G |
| 78 | U+004D | `M` | LATIN CAPITAL LETTER M |
| 74 | U+0062 | `b` | LATIN SMALL LETTER B |
| 67 | U+0052 | `R` | LATIN CAPITAL LETTER R |
| 61 | U+0044 | `D` | LATIN CAPITAL LETTER D |
| 60 | U+0053 | `S` | LATIN CAPITAL LETTER S |
| 59 | U+0079 | `y` | LATIN SMALL LETTER Y |
| 57 | U+0077 | `w` | LATIN SMALL LETTER W |
| 50 | U+0041 | `A` | LATIN CAPITAL LETTER A |
| 48 | U+0054 | `T` | LATIN CAPITAL LETTER T |
| 45 | U+0050 | `P` | LATIN CAPITAL LETTER P |
| 38 | U+0043 | `C` | LATIN CAPITAL LETTER C |
| 38 | U+0047 | `G` | LATIN CAPITAL LETTER G |
| 38 | U+004B | `K` | LATIN CAPITAL LETTER K |
| 35 | U+0046 | `F` | LATIN CAPITAL LETTER F |
| 35 | U+0048 | `H` | LATIN CAPITAL LETTER H |
| 31 | U+0056 | `V` | LATIN CAPITAL LETTER V |
| 30 | U+0078 | `x` | LATIN SMALL LETTER X |
| 30 | U+004E | `N` | LATIN CAPITAL LETTER N |
| 28 | U+0045 | `E` | LATIN CAPITAL LETTER E |
| 26 | U+004F | `O` | LATIN CAPITAL LETTER O |
| 24 | U+0049 | `I` | LATIN CAPITAL LETTER I |
| 23 | U+2026 | `…` | HORIZONTAL ELLIPSIS |
| 22 | U+004C | `L` | LATIN CAPITAL LETTER L |
| 22 | U+007A | `z` | LATIN SMALL LETTER Z |
| 22 | U+0042 | `B` | LATIN CAPITAL LETTER B |
| 19 | U+0057 | `W` | LATIN CAPITAL LETTER W |
| 19 | U+0051 | `Q` | LATIN CAPITAL LETTER Q |
| 17 | U+002A | `*` | ASTERISK |
| 14 | U+0055 | `U` | LATIN CAPITAL LETTER U |
| 14 | U+00EB | `ë` | LATIN SMALL LETTER E WITH DIAERESIS |
| 12 | U+0071 | `q` | LATIN SMALL LETTER Q |
| 10 | U+0058 | `X` | LATIN CAPITAL LETTER X |
| 10 | U+0059 | `Y` | LATIN CAPITAL LETTER Y |
| 10 | U+00B0 | `°` | DEGREE SIGN |
| 9 | U+003E | `>` | GREATER-THAN SIGN |
| 8 | U+006A | `j` | LATIN SMALL LETTER J |
| 7 | U+005A | `Z` | LATIN CAPITAL LETTER Z |
| 7 | U+004A | `J` | LATIN CAPITAL LETTER J |
| 6 | U+007E | `~` | TILDE |
| 3 | U+003C | `<` | LESS-THAN SIGN |
| 3 | U+3064 | `つ` | HIRAGANA LETTER TU |
| 2 | U+00AF | `¯` | MACRON |
| 2 | U+2060 | `'\u2060'` | WORD JOINER |
| 2 | U+FF3C | `＼` | FULLWIDTH REVERSE SOLIDUS |
| 2 | U+FF0F | `／` | FULLWIDTH SOLIDUS |
| 1 | U+2248 | `≈` | ALMOST EQUAL TO |
| 1 | U+30C4 | `ツ` | KATAKANA LETTER TU |
| 1 | U+0532 | `Բ` | ARMENIAN CAPITAL LETTER BEN |
| 1 | U+0561 | `ա` | ARMENIAN SMALL LETTER AYB |
| 1 | U+0580 | `ր` | ARMENIAN SMALL LETTER REH |
| 1 | U+0587 | `և` | ARMENIAN SMALL LIGATURE ECH YIWN |
| 1 | U+0571 | `ձ` | ARMENIAN SMALL LETTER JA |
| 1 | U+0565 | `ե` | ARMENIAN SMALL LETTER ECH |
| 1 | U+0566 | `զ` | ARMENIAN SMALL LETTER ZA |
| 1 | U+3063 | `っ` | HIRAGANA LETTER SMALL TU |
| 1 | U+1559 | `ᕙ` | CANADIAN SYLLABICS FA |
| 1 | U+0300 | `̀` | COMBINING GRAVE ACCENT |
| 1 | U+15DC | `ᗜ` | CANADIAN SYLLABICS CARRIER THU |
| 1 | U+0301 | `́` | COMBINING ACUTE ACCENT |
| 1 | U+1557 | `ᕗ` | CANADIAN SYLLABICS FO |
| 1 | U+0F3C | `༼` | TIBETAN MARK ANG KHANG GYON |
| 1 | U+0F3D | `༽` | TIBETAN MARK ANG KHANG GYAS |
| 1 | U+30E9 | `ラ` | KATAKANA LETTER RA |
| 1 | U+30D6 | `ブ` | KATAKANA LETTER BU |
| 1 | U+30C6 | `テ` | KATAKANA LETTER TE |
| 1 | U+30B9 | `ス` | KATAKANA LETTER SU |
| 1 | U+30BF | `タ` | KATAKANA LETTER TA |
| 1 | U+30FC | `ー` | KATAKANA-HIRAGANA PROLONGED SOUND MARK |
| 1 | U+0101 | `ā` | LATIN SMALL LETTER A WITH MACRON |

## Input files

### Train
- `corpora\ru\meshcoretel-ru.jsonl`
- `corpora\ru\messages.jsonl`
