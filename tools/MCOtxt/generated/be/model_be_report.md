# MCOtxt v1 model report — BE

## Build

- Language wire ID: `6`
- Unicode database: `15.1.0`
- Primary selection: `literal-savings`
- Canonical language symbols: `43`
- Primary: `32`
- Extension: `11`
- Total model symbols: `43`
- Prediction contexts: `START`, `AFTER_PUNCT`, `SYMBOL(previous)`
- Punctuation table: built-in MCOtxt v1 fallback; **not verified against punctuation.dart in this run**

## Training corpus

- Files: `1`
- Messages: `441`
- UTF-8 bytes (message payloads): `35009`
- Normalized codepoints: `19873`
- Language symbols: `17161`
- Uppercase mapped: `454`
- Punctuation: `727`
- Unsupported: `1985`
- Training TOP-4 hit rate: `60.38%`

## Validation

- Source: `deterministic SHA-256 hold-out (20.0%)`
- Explicit validation files: `0`
- Messages: `105`
- Original UTF-8 bytes: `9787`
- Normalized codepoints: `5465`
- Output codepoints: `5465`
- Skipped unsupported: `0`
- UTF-8 fallback runs: `344`
- UTF-8 fallback codepoints: `456`
- UTF-8 fallback bytes: `779`
- UTF-8 fallback bits: `11048`
- Language symbols: `4858`
- TOP-4 hits: `2875` (`59.18%`)
- Primary literals: `1955`
- Extension literals: `28`
- SHIFT tokens: `104`
- Punctuation tokens: `151`
- Token bits: `35059`
- Header bits (12/message): `1260`
- Total bits: `36319`
- Bits/output-char, tokens only: `6.4152`
- Bits/output-char, incl. per-message header: `6.6457`
- UTF-8 bytes of the same decoded/supported text: `9787`
- Compression ratio vs same decoded UTF-8: `2.1558x`

> Validation here is single-language model evaluation. It includes real MCOtxt v1 variable TOP-4 / literal / SHIFT / punctuation / UTF8_RUN costs and a 12-bit normal MCOtxt header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.

## TOP-4 rank diagnostics — validation

| rank | hits | share of TOP-4 hits |
|---:|---:|---:|
| 0 | 1235 | 42.96% |
| 1 | 684 | 23.79% |
| 2 | 523 | 18.19% |
| 3 | 433 | 15.06% |

> Variable TOP-4 is enabled in v1: rank 0 = 2 bits, rank 1 = 3 bits, ranks 2/3 = 4 bits. The table above shows the observed rank distribution.

## Final encoder candidate simulation — validation

This section simulates the final message-level selector between optimized normal MCOtxt (precomputed CAPS/SHIFT plan + fallback-only UTF8_RUN) and whole-message RAW_UTF8. It is intentionally separate from the model-only metrics above so TOP-4/model quality remains comparable between builds.

- Optimized MCOtxt candidate bits: `36314`
- Optimized MCOtxt candidate packed bytes: `4584`
- RAW_UTF8 candidate bits: `79976`
- RAW_UTF8 candidate packed bytes: `9997`
- Selected MCOtxt messages: `105`
- Selected RAW_UTF8 messages: `0`
- Optimized CAPS_MODE toggles in MCOtxt candidates: `0`
- Optimized one-symbol SHIFTs in MCOtxt candidates: `104`
- Optimized fallback UTF8_RUNs in MCOtxt candidates: `344`
- Final selected bits: `36314`
- Final selected packed bytes: `4584`
- Savings vs optimized MCOtxt: `0` bytes
- Selected ratio vs normalized UTF-8: `2.1561x`

> RAW_UTF8 simulation uses a `16`-bit byte-aligned message-mode header, matching the current Python A/B reference benchmark.

## Symbol index table

| idx | tier | symbol | codepoint | train count |
|---:|---|---|---|---:|
| 0 | primary | `SPACE` | U+0020 | 2860 |
| 1 | primary | `к` | U+043A | 597 |
| 2 | primary | `л` | U+043B | 587 |
| 3 | primary | `м` | U+043C | 420 |
| 4 | primary | `с` | U+0441 | 774 |
| 5 | primary | `е` | U+0435 | 1260 |
| 6 | primary | `р` | U+0440 | 679 |
| 7 | primary | `в` | U+0432 | 589 |
| 8 | primary | `н` | U+043D | 1042 |
| 9 | primary | `я` | U+044F | 324 |
| 10 | primary | `д` | U+0434 | 423 |
| 11 | primary | `у` | U+0443 | 449 |
| 12 | primary | `т` | U+0442 | 1213 |
| 13 | primary | `ч` | U+0447 | 268 |
| 14 | primary | `о` | U+043E | 1716 |
| 15 | primary | `п` | U+043F | 507 |
| 16 | primary | `з` | U+0437 | 197 |
| 17 | primary | `ы` | U+044B | 198 |
| 18 | primary | `й` | U+0439 | 182 |
| 19 | primary | `г` | U+0433 | 153 |
| 20 | primary | `б` | U+0431 | 266 |
| 21 | primary | `ж` | U+0436 | 170 |
| 22 | primary | `а` | U+0430 | 1248 |
| 23 | primary | `ш` | U+0448 | 136 |
| 24 | primary | `ю` | U+044E | 113 |
| 25 | primary | `х` | U+0445 | 76 |
| 26 | primary | `ь` | U+044C | 319 |
| 27 | primary | `э` | U+044D | 52 |
| 28 | primary | `2` | U+0032 | 61 |
| 29 | primary | `ф` | U+0444 | 42 |
| 30 | primary | `ц` | U+0446 | 33 |
| 31 | primary | `1` | U+0031 | 28 |
| 32 | extension | `4` | U+0034 | 25 |
| 33 | extension | `ё` | U+0451 | 16 |
| 34 | extension | `3` | U+0033 | 14 |
| 35 | extension | `6` | U+0036 | 22 |
| 36 | extension | `8` | U+0038 | 17 |
| 37 | extension | `5` | U+0035 | 21 |
| 38 | extension | `7` | U+0037 | 20 |
| 39 | extension | `0` | U+0030 | 37 |
| 40 | extension | `9` | U+0039 | 7 |
| 41 | extension | `і` | U+0456 | 0 |
| 42 | extension | `ў` | U+045E | 0 |

## START TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `12` → U+0442 'т' CYRILLIC SMALL LETTER TE
- `2` → index `8` → U+043D 'н' CYRILLIC SMALL LETTER EN
- `3` → index `5` → U+0435 'е' CYRILLIC SMALL LETTER IE

## AFTER_PUNCT TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `12` → U+0442 'т' CYRILLIC SMALL LETTER TE
- `2` → index `28` → U+0032 '2' DIGIT TWO
- `3` → index `38` → U+0037 '7' DIGIT SEVEN

## Prediction-context diagnostics

### Message begins with — training

| class | messages |
|---|---:|
| `language_symbol` | 413 |
| `foreign_language` | 25 |
| `unsupported` | 2 |
| `punctuation` | 1 |

### Why a language symbol used START — training

| reason | transitions |
|---|---:|
| `utf8_fallback` | 1105 |
| `message_start` | 413 |
| `newline` | 18 |

### START target frequencies — training

| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `SPACE` | U+0020 | 303 | 19.73% | yes | utf8_fallback=303 |
| 2 | `т` | U+0442 | 153 | 9.96% | yes | message_start=24, newline=1, utf8_fallback=128 |
| 3 | `н` | U+043D | 124 | 8.07% | yes | message_start=44, newline=5, utf8_fallback=75 |
| 4 | `е` | U+0435 | 112 | 7.29% | yes | message_start=14, newline=1, utf8_fallback=97 |
| 5 | `в` | U+0432 | 86 | 5.60% |  | message_start=36, newline=3, utf8_fallback=47 |
| 6 | `л` | U+043B | 85 | 5.53% |  | message_start=3, utf8_fallback=82 |
| 7 | `д` | U+0434 | 60 | 3.91% |  | message_start=33, utf8_fallback=27 |
| 8 | `я` | U+044F | 59 | 3.84% |  | message_start=15, newline=1, utf8_fallback=43 |
| 9 | `п` | U+043F | 57 | 3.71% |  | message_start=54, newline=1, utf8_fallback=2 |
| 10 | `к` | U+043A | 51 | 3.32% |  | message_start=22, utf8_fallback=29 |
| 11 | `с` | U+0441 | 50 | 3.26% |  | message_start=28, newline=1, utf8_fallback=21 |
| 12 | `м` | U+043C | 50 | 3.26% |  | message_start=19, newline=1, utf8_fallback=30 |
| 13 | `а` | U+0430 | 48 | 3.12% |  | message_start=34, newline=1, utf8_fallback=13 |
| 14 | `ч` | U+0447 | 39 | 2.54% |  | message_start=13, utf8_fallback=26 |
| 15 | `о` | U+043E | 35 | 2.28% |  | message_start=28, newline=1, utf8_fallback=6 |
| 16 | `з` | U+0437 | 33 | 2.15% |  | message_start=10, utf8_fallback=23 |
| 17 | `р` | U+0440 | 27 | 1.76% |  | message_start=8, utf8_fallback=19 |
| 18 | `б` | U+0431 | 21 | 1.37% |  | message_start=1, utf8_fallback=20 |
| 19 | `й` | U+0439 | 18 | 1.17% |  | utf8_fallback=18 |
| 20 | `х` | U+0445 | 16 | 1.04% |  | message_start=3, utf8_fallback=13 |
| 21 | `ш` | U+0448 | 13 | 0.85% |  | utf8_fallback=13 |
| 22 | `ж` | U+0436 | 13 | 0.85% |  | message_start=1, utf8_fallback=12 |
| 23 | `г` | U+0433 | 13 | 0.85% |  | message_start=2, utf8_fallback=11 |
| 24 | `у` | U+0443 | 10 | 0.65% |  | message_start=9, utf8_fallback=1 |
| 25 | `ю` | U+044E | 9 | 0.59% |  | utf8_fallback=9 |
| 26 | `4` | U+0034 | 8 | 0.52% |  | utf8_fallback=8 |
| 27 | `3` | U+0033 | 8 | 0.52% |  | newline=1, utf8_fallback=7 |
| 28 | `2` | U+0032 | 7 | 0.46% |  | message_start=1, newline=1, utf8_fallback=5 |
| 29 | `ц` | U+0446 | 7 | 0.46% |  | message_start=2, utf8_fallback=5 |
| 30 | `1` | U+0031 | 5 | 0.33% |  | message_start=3, utf8_fallback=2 |

### AFTER_PUNCT target frequencies — training

| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 299 | 80.38% | yes |
| 2 | `т` | U+0442 | 9 | 2.42% | yes |
| 3 | `2` | U+0032 | 9 | 2.42% | yes |
| 4 | `7` | U+0037 | 9 | 2.42% | yes |
| 5 | `1` | U+0031 | 7 | 1.88% |  |
| 6 | `4` | U+0034 | 5 | 1.34% |  |
| 7 | `у` | U+0443 | 3 | 0.81% |  |
| 8 | `с` | U+0441 | 3 | 0.81% |  |
| 9 | `0` | U+0030 | 3 | 0.81% |  |
| 10 | `п` | U+043F | 3 | 0.81% |  |
| 11 | `в` | U+0432 | 3 | 0.81% |  |
| 12 | `к` | U+043A | 3 | 0.81% |  |
| 13 | `л` | U+043B | 2 | 0.54% |  |
| 14 | `е` | U+0435 | 2 | 0.54% |  |
| 15 | `д` | U+0434 | 2 | 0.54% |  |
| 16 | `о` | U+043E | 1 | 0.27% |  |
| 17 | `й` | U+0439 | 1 | 0.27% |  |
| 18 | `з` | U+0437 | 1 | 0.27% |  |
| 19 | `5` | U+0035 | 1 | 0.27% |  |
| 20 | `я` | U+044F | 1 | 0.27% |  |
| 21 | `а` | U+0430 | 1 | 0.27% |  |
| 22 | `3` | U+0033 | 1 | 0.27% |  |
| 23 | `8` | U+0038 | 1 | 0.27% |  |
| 24 | `6` | U+0036 | 1 | 0.27% |  |
| 25 | `9` | U+0039 | 1 | 0.27% |  |

### Ordinary punctuation that led to AFTER_PUNCT — training

| punctuation | codepoint | following language contexts |
|---|---|---:|
| `,` | U+002C | 168 |
| `.` | U+002E | 99 |
| `-` | U+002D | 32 |
| `?` | U+003F | 14 |
| `)` | U+0029 | 13 |
| `/` | U+002F | 11 |
| `(` | U+0028 | 11 |
| `"` | U+0022 | 6 |
| `:` | U+003A | 4 |
| `!` | U+0021 | 3 |
| `+` | U+002B | 2 |
| `%` | U+0025 | 2 |
| `[` | U+005B | 2 |
| `_` | U+005F | 2 |
| `«` | U+00AB | 1 |
| `»` | U+00BB | 1 |
| `]` | U+005D | 1 |

### START target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `SPACE` | U+0020 | 82 | 19.34% | yes | utf8_fallback=82 |
| 2 | `т` | U+0442 | 45 | 10.61% | yes | message_start=4, newline=2, utf8_fallback=39 |
| 3 | `н` | U+043D | 37 | 8.73% | yes | message_start=14, utf8_fallback=23 |
| 4 | `л` | U+043B | 32 | 7.55% |  | message_start=2, utf8_fallback=30 |
| 5 | `е` | U+0435 | 32 | 7.55% | yes | message_start=6, newline=3, utf8_fallback=23 |
| 6 | `в` | U+0432 | 23 | 5.42% |  | message_start=5, utf8_fallback=18 |
| 7 | `д` | U+0434 | 16 | 3.77% |  | message_start=8, utf8_fallback=8 |
| 8 | `с` | U+0441 | 15 | 3.54% |  | message_start=10, utf8_fallback=5 |
| 9 | `п` | U+043F | 15 | 3.54% |  | message_start=11, newline=1, utf8_fallback=3 |
| 10 | `з` | U+0437 | 13 | 3.07% |  | message_start=3, utf8_fallback=10 |
| 11 | `а` | U+0430 | 12 | 2.83% |  | message_start=8, newline=1, utf8_fallback=3 |
| 12 | `м` | U+043C | 12 | 2.83% |  | message_start=5, utf8_fallback=7 |
| 13 | `я` | U+044F | 11 | 2.59% |  | message_start=6, utf8_fallback=5 |
| 14 | `ч` | U+0447 | 11 | 2.59% |  | message_start=2, utf8_fallback=9 |
| 15 | `к` | U+043A | 11 | 2.59% |  | message_start=2, utf8_fallback=9 |
| 16 | `о` | U+043E | 9 | 2.12% |  | message_start=5, utf8_fallback=4 |
| 17 | `р` | U+0440 | 9 | 2.12% |  | utf8_fallback=9 |
| 18 | `ё` | U+0451 | 6 | 1.42% |  | utf8_fallback=6 |
| 19 | `б` | U+0431 | 5 | 1.18% |  | message_start=1, utf8_fallback=4 |
| 20 | `у` | U+0443 | 5 | 1.18% |  | message_start=5 |
| 21 | `г` | U+0433 | 5 | 1.18% |  | utf8_fallback=5 |
| 22 | `ж` | U+0436 | 4 | 0.94% |  | utf8_fallback=4 |
| 23 | `ш` | U+0448 | 3 | 0.71% |  | message_start=1, utf8_fallback=2 |
| 24 | `ц` | U+0446 | 2 | 0.47% |  | utf8_fallback=2 |
| 25 | `1` | U+0031 | 2 | 0.47% |  | utf8_fallback=2 |
| 26 | `х` | U+0445 | 1 | 0.24% |  | utf8_fallback=1 |
| 27 | `3` | U+0033 | 1 | 0.24% |  | message_start=1 |
| 28 | `ю` | U+044E | 1 | 0.24% |  | utf8_fallback=1 |
| 29 | `й` | U+0439 | 1 | 0.24% |  | utf8_fallback=1 |
| 30 | `э` | U+044D | 1 | 0.24% |  | message_start=1 |

### AFTER_PUNCT target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 66 | 79.52% | yes |
| 2 | `т` | U+0442 | 3 | 3.61% | yes |
| 3 | `7` | U+0037 | 3 | 3.61% | yes |
| 4 | `с` | U+0441 | 2 | 2.41% |  |
| 5 | `е` | U+0435 | 2 | 2.41% |  |
| 6 | `2` | U+0032 | 1 | 1.20% | yes |
| 7 | `д` | U+0434 | 1 | 1.20% |  |
| 8 | `0` | U+0030 | 1 | 1.20% |  |
| 9 | `8` | U+0038 | 1 | 1.20% |  |
| 10 | `н` | U+043D | 1 | 1.20% |  |
| 11 | `м` | U+043C | 1 | 1.20% |  |
| 12 | `з` | U+0437 | 1 | 1.20% |  |

## Bit cost breakdown — validation

| category | tokens | bits | share of total bits |
|---|---:|---:|---:|
| TOP-4 variable | 2875 | 8346 | 22.98% |
| Primary literal | 1955 | 13685 | 37.68% |
| Extension literal | 28 | 252 | 0.69% |
| SHIFT | 104 | 520 | 1.43% |
| Punctuation | 151 | 1208 | 3.33% |
| UTF-8 fallback | 344 | 11048 | 30.42% |
| Header | 105 | 1260 | 3.47% |

## UTF-8 fallback — validation

- Runs: `344`
- Unicode codepoints: `456`
- UTF-8 bytes: `779`
- Total fallback bits: `11048`
- Share of total encoded bits: `30.42%`

| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 296 | U+0438 | `и` | CYRILLIC SMALL LETTER I |
| 21 | U+0449 | `щ` | CYRILLIC SMALL LETTER SHCHA |
| 13 | U+0074 | `t` | LATIN SMALL LETTER T |
| 10 | U+0069 | `i` | LATIN SMALL LETTER I |
| 9 | U+0068 | `h` | LATIN SMALL LETTER H |
| 9 | U+0065 | `e` | LATIN SMALL LETTER E |
| 8 | U+006F | `o` | LATIN SMALL LETTER O |
| 7 | U+0072 | `r` | LATIN SMALL LETTER R |
| 6 | U+006E | `n` | LATIN SMALL LETTER N |
| 6 | U+0075 | `u` | LATIN SMALL LETTER U |
| 6 | U+0064 | `d` | LATIN SMALL LETTER D |
| 6 | U+0061 | `a` | LATIN SMALL LETTER A |
| 6 | U+0073 | `s` | LATIN SMALL LETTER S |
| 5 | U+006D | `m` | LATIN SMALL LETTER M |
| 4 | U+0070 | `p` | LATIN SMALL LETTER P |
| 4 | U+0418 | `И` | CYRILLIC CAPITAL LETTER I |
| 4 | U+0062 | `b` | LATIN SMALL LETTER B |
| 3 | U+006C | `l` | LATIN SMALL LETTER L |
| 3 | U+0054 | `T` | LATIN CAPITAL LETTER T |
| 3 | U+004C | `L` | LATIN CAPITAL LETTER L |
| 3 | U+0067 | `g` | LATIN SMALL LETTER G |
| 2 | U+0066 | `f` | LATIN SMALL LETTER F |
| 2 | U+044A | `ъ` | CYRILLIC SMALL LETTER HARD SIGN |
| 2 | U+006B | `k` | LATIN SMALL LETTER K |
| 2 | U+0063 | `c` | LATIN SMALL LETTER C |
| 2 | U+0052 | `R` | LATIN CAPITAL LETTER R |
| 2 | U+0042 | `B` | LATIN CAPITAL LETTER B |
| 2 | U+0045 | `E` | LATIN CAPITAL LETTER E |
| 1 | U+0048 | `H` | LATIN CAPITAL LETTER H |
| 1 | U+0041 | `A` | LATIN CAPITAL LETTER A |
| 1 | U+0046 | `F` | LATIN CAPITAL LETTER F |
| 1 | U+0055 | `U` | LATIN CAPITAL LETTER U |
| 1 | U+0056 | `V` | LATIN CAPITAL LETTER V |
| 1 | U+004D | `M` | LATIN CAPITAL LETTER M |
| 1 | U+0043 | `C` | LATIN CAPITAL LETTER C |
| 1 | U+0077 | `w` | LATIN SMALL LETTER W |
| 1 | U+0076 | `v` | LATIN SMALL LETTER V |
| 1 | U+0050 | `P` | LATIN CAPITAL LETTER P |

## Most expensive TOP-4 misses — validation

Sorted by avoidable bit cost relative to a hypothetical 3-bit TOP-4 reference hit for the same target. SHIFT cost is excluded because it is paid in both cases.

| previous | next | tier | misses | literal bits | extra vs TOP-4 |
|---|---|---|---:|---:|---:|
| `SPACE` U+0020 | `к` U+043A | primary | 45 | 7 | 180 |
| `SPACE` U+0020 | `т` U+0442 | primary | 43 | 7 | 172 |
| `т` U+0442 | `е` U+0435 | primary | 42 | 7 | 168 |
| START | `л` U+043B | primary | 32 | 7 | 128 |
| `SPACE` U+0020 | `м` U+043C | primary | 32 | 7 | 128 |
| `е` U+0435 | `с` U+0441 | primary | 30 | 7 | 120 |
| `SPACE` U+0020 | `о` U+043E | primary | 29 | 7 | 116 |
| `о` U+043E | `р` U+0440 | primary | 29 | 7 | 116 |
| `SPACE` U+0020 | `д` U+0434 | primary | 28 | 7 | 112 |
| `SPACE` U+0020 | `р` U+0440 | primary | 27 | 7 | 108 |
| `о` U+043E | `с` U+0441 | primary | 27 | 7 | 108 |
| `SPACE` U+0020 | `б` U+0431 | primary | 25 | 7 | 100 |
| `о` U+043E | `в` U+0432 | primary | 24 | 7 | 96 |
| START | `в` U+0432 | primary | 23 | 7 | 92 |
| `о` U+043E | `й` U+0439 | primary | 23 | 7 | 92 |
| `т` U+0442 | `р` U+0440 | primary | 23 | 7 | 92 |
| `SPACE` U+0020 | `у` U+0443 | primary | 22 | 7 | 88 |
| `SPACE` U+0020 | `ч` U+0447 | primary | 22 | 7 | 88 |
| `а` U+0430 | `к` U+043A | primary | 22 | 7 | 88 |
| `а` U+0430 | `н` U+043D | primary | 22 | 7 | 88 |
| `о` U+043E | `л` U+043B | primary | 20 | 7 | 80 |
| `а` U+0430 | `м` U+043C | primary | 19 | 7 | 76 |
| `о` U+043E | `м` U+043C | primary | 19 | 7 | 76 |
| `с` U+0441 | `л` U+043B | primary | 19 | 7 | 76 |
| `а` U+0430 | `в` U+0432 | primary | 18 | 7 | 72 |
| `о` U+043E | `н` U+043D | primary | 18 | 7 | 72 |
| `о` U+043E | `г` U+0433 | primary | 17 | 7 | 68 |
| `о` U+043E | `ж` U+0436 | primary | 17 | 7 | 68 |
| `с` U+0441 | `я` U+044F | primary | 17 | 7 | 68 |
| START | `д` U+0434 | primary | 16 | 7 | 64 |
| `SPACE` U+0020 | `е` U+0435 | primary | 16 | 7 | 64 |
| `о` U+043E | `к` U+043A | primary | 16 | 7 | 64 |
| START | `п` U+043F | primary | 15 | 7 | 60 |
| START | `с` U+0441 | primary | 15 | 7 | 60 |
| `SPACE` U+0020 | `з` U+0437 | primary | 15 | 7 | 60 |
| `а` U+0430 | `й` U+0439 | primary | 15 | 7 | 60 |
| `а` U+0430 | `р` U+0440 | primary | 15 | 7 | 60 |
| `а` U+0430 | `я` U+044F | primary | 14 | 7 | 56 |
| `е` U+0435 | `л` U+043B | primary | 14 | 7 | 56 |
| `е` U+0435 | `м` U+043C | primary | 14 | 7 | 56 |

## Unsupported symbols in validation

These symbols were encoded losslessly through UTF8_RUN during validation.
| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 296 | U+0438 | `и` | CYRILLIC SMALL LETTER I |
| 21 | U+0449 | `щ` | CYRILLIC SMALL LETTER SHCHA |
| 13 | U+0074 | `t` | LATIN SMALL LETTER T |
| 10 | U+0069 | `i` | LATIN SMALL LETTER I |
| 9 | U+0068 | `h` | LATIN SMALL LETTER H |
| 9 | U+0065 | `e` | LATIN SMALL LETTER E |
| 8 | U+006F | `o` | LATIN SMALL LETTER O |
| 7 | U+0072 | `r` | LATIN SMALL LETTER R |
| 6 | U+006E | `n` | LATIN SMALL LETTER N |
| 6 | U+0075 | `u` | LATIN SMALL LETTER U |
| 6 | U+0064 | `d` | LATIN SMALL LETTER D |
| 6 | U+0061 | `a` | LATIN SMALL LETTER A |
| 6 | U+0073 | `s` | LATIN SMALL LETTER S |
| 5 | U+006D | `m` | LATIN SMALL LETTER M |
| 4 | U+0070 | `p` | LATIN SMALL LETTER P |
| 4 | U+0418 | `И` | CYRILLIC CAPITAL LETTER I |
| 4 | U+0062 | `b` | LATIN SMALL LETTER B |
| 3 | U+006C | `l` | LATIN SMALL LETTER L |
| 3 | U+0054 | `T` | LATIN CAPITAL LETTER T |
| 3 | U+004C | `L` | LATIN CAPITAL LETTER L |
| 3 | U+0067 | `g` | LATIN SMALL LETTER G |
| 2 | U+0066 | `f` | LATIN SMALL LETTER F |
| 2 | U+044A | `ъ` | CYRILLIC SMALL LETTER HARD SIGN |
| 2 | U+006B | `k` | LATIN SMALL LETTER K |
| 2 | U+0063 | `c` | LATIN SMALL LETTER C |
| 2 | U+0052 | `R` | LATIN CAPITAL LETTER R |
| 2 | U+0042 | `B` | LATIN CAPITAL LETTER B |
| 2 | U+0045 | `E` | LATIN CAPITAL LETTER E |
| 1 | U+0048 | `H` | LATIN CAPITAL LETTER H |
| 1 | U+0041 | `A` | LATIN CAPITAL LETTER A |
| 1 | U+0046 | `F` | LATIN CAPITAL LETTER F |
| 1 | U+0055 | `U` | LATIN CAPITAL LETTER U |
| 1 | U+0056 | `V` | LATIN CAPITAL LETTER V |
| 1 | U+004D | `M` | LATIN CAPITAL LETTER M |
| 1 | U+0043 | `C` | LATIN CAPITAL LETTER C |
| 1 | U+0077 | `w` | LATIN SMALL LETTER W |
| 1 | U+0076 | `v` | LATIN SMALL LETTER V |
| 1 | U+0050 | `P` | LATIN CAPITAL LETTER P |

## Input files

### Train
- `corpora\be\mcotxt_be_ru_dataset_clean.jsonl`
