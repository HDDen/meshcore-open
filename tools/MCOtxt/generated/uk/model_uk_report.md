# MCOtxt v1 model report — UK

## Build

- Language wire ID: `5`
- Unicode database: `15.1.0`
- Primary selection: `literal-savings`
- Canonical language symbols: `44`
- Primary: `32`
- Extension: `12`
- Total model symbols: `44`
- Prediction contexts: `START`, `AFTER_PUNCT`, `SYMBOL(previous)`
- Punctuation table: built-in MCOtxt v1 fallback; **not verified against punctuation.dart in this run**

## Training corpus

- Files: `1`
- Messages: `596`
- UTF-8 bytes (message payloads): `71099`
- Normalized codepoints: `41025`
- Language symbols: `36782`
- Uppercase mapped: `761`
- Punctuation: `1633`
- Unsupported: `2610`
- Training TOP-4 hit rate: `58.53%`

## Validation

- Source: `deterministic SHA-256 hold-out (20.0%)`
- Explicit validation files: `0`
- Messages: `162`
- Original UTF-8 bytes: `20892`
- Normalized codepoints: `12025`
- Output codepoints: `12025`
- Skipped unsupported: `0`
- UTF-8 fallback runs: `180`
- UTF-8 fallback codepoints: `620`
- UTF-8 fallback bytes: `637`
- UTF-8 fallback bits: `7616`
- Language symbols: `10920`
- TOP-4 hits: `6278` (`57.49%`)
- Primary literals: `4460`
- Extension literals: `182`
- SHIFT tokens: `222`
- Punctuation tokens: `485`
- Token bits: `63422`
- Header bits (12/message): `1944`
- Total bits: `65366`
- Bits/output-char, tokens only: `5.2742`
- Bits/output-char, incl. per-message header: `5.4358`
- UTF-8 bytes of the same decoded/supported text: `20892`
- Compression ratio vs same decoded UTF-8: `2.5569x`

> Validation here is single-language model evaluation. It includes real MCOtxt v1 variable TOP-4 / literal / SHIFT / punctuation / UTF8_RUN costs and a 12-bit normal MCOtxt header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.

## TOP-4 rank diagnostics — validation

| rank | hits | share of TOP-4 hits |
|---:|---:|---:|
| 0 | 2839 | 45.22% |
| 1 | 1476 | 23.51% |
| 2 | 1130 | 18.00% |
| 3 | 833 | 13.27% |

> Variable TOP-4 is enabled in v1: rank 0 = 2 bits, rank 1 = 3 bits, ranks 2/3 = 4 bits. The table above shows the observed rank distribution.

## Final encoder candidate simulation — validation

This section simulates the final message-level selector between optimized normal MCOtxt (precomputed CAPS/SHIFT plan + fallback-only UTF8_RUN) and whole-message RAW_UTF8. It is intentionally separate from the model-only metrics above so TOP-4/model quality remains comparable between builds.

- Optimized MCOtxt candidate bits: `65319`
- Optimized MCOtxt candidate packed bytes: `8242`
- RAW_UTF8 candidate bits: `169728`
- RAW_UTF8 candidate packed bytes: `21216`
- Selected MCOtxt messages: `161`
- Selected RAW_UTF8 messages: `1`
- Optimized CAPS_MODE toggles in MCOtxt candidates: `2`
- Optimized one-symbol SHIFTs in MCOtxt candidates: `217`
- Optimized fallback UTF8_RUNs in MCOtxt candidates: `180`
- Final selected bits: `65318`
- Final selected packed bytes: `8241`
- Savings vs optimized MCOtxt: `1` bytes
- Selected ratio vs normalized UTF-8: `2.5588x`

> RAW_UTF8 simulation uses a `16`-bit byte-aligned message-mode header, matching the current Python A/B reference benchmark.

## Symbol index table

| idx | tier | symbol | codepoint | train count |
|---:|---|---|---|---:|
| 0 | primary | `SPACE` | U+0020 | 6098 |
| 1 | primary | `к` | U+043A | 1147 |
| 2 | primary | `с` | U+0441 | 1057 |
| 3 | primary | `р` | U+0440 | 1389 |
| 4 | primary | `і` | U+0456 | 1440 |
| 5 | primary | `м` | U+043C | 992 |
| 6 | primary | `у` | U+0443 | 1038 |
| 7 | primary | `н` | U+043D | 2047 |
| 8 | primary | `з` | U+0437 | 603 |
| 9 | primary | `б` | U+0431 | 602 |
| 10 | primary | `л` | U+043B | 941 |
| 11 | primary | `д` | U+0434 | 992 |
| 12 | primary | `о` | U+043E | 2781 |
| 13 | primary | `и` | U+0438 | 1685 |
| 14 | primary | `я` | U+044F | 725 |
| 15 | primary | `а` | U+0430 | 2652 |
| 16 | primary | `е` | U+0435 | 1753 |
| 17 | primary | `т` | U+0442 | 1825 |
| 18 | primary | `в` | U+0432 | 1601 |
| 19 | primary | `ш` | U+0448 | 365 |
| 20 | primary | `ч` | U+0447 | 345 |
| 21 | primary | `й` | U+0439 | 335 |
| 22 | primary | `г` | U+0433 | 323 |
| 23 | primary | `п` | U+043F | 1117 |
| 24 | primary | `ж` | U+0436 | 289 |
| 25 | primary | `ю` | U+044E | 324 |
| 26 | primary | `ц` | U+0446 | 254 |
| 27 | primary | `х` | U+0445 | 220 |
| 28 | primary | `є` | U+0454 | 228 |
| 29 | primary | `щ` | U+0449 | 168 |
| 30 | primary | `ф` | U+0444 | 122 |
| 31 | primary | `ї` | U+0457 | 112 |
| 32 | extension | `2` | U+0032 | 146 |
| 33 | extension | `3` | U+0033 | 112 |
| 34 | extension | `ь` | U+044C | 543 |
| 35 | extension | `1` | U+0031 | 82 |
| 36 | extension | `4` | U+0034 | 38 |
| 37 | extension | `5` | U+0035 | 72 |
| 38 | extension | `8` | U+0038 | 38 |
| 39 | extension | `6` | U+0036 | 48 |
| 40 | extension | `7` | U+0037 | 24 |
| 41 | extension | `0` | U+0030 | 90 |
| 42 | extension | `9` | U+0039 | 19 |
| 43 | extension | `ґ` | U+0491 | 0 |

## START TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `17` → U+0442 'т' CYRILLIC SMALL LETTER TE
- `2` → index `7` → U+043D 'н' CYRILLIC SMALL LETTER EN
- `3` → index `11` → U+0434 'д' CYRILLIC SMALL LETTER DE

## AFTER_PUNCT TOP-4

- `0` → index `0` → U+0020 'SPACE' SPACE
- `1` → index `37` → U+0035 '5' DIGIT FIVE
- `2` → index `41` → U+0030 '0' DIGIT ZERO
- `3` → index `35` → U+0031 '1' DIGIT ONE

## Prediction-context diagnostics

### Message begins with — training

| class | messages |
|---|---:|
| `language_symbol` | 577 |
| `foreign_language` | 15 |
| `punctuation` | 4 |

### Why a language symbol used START — training

| reason | transitions |
|---|---:|
| `message_start` | 577 |
| `utf8_fallback` | 417 |

### START target frequencies — training

| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `SPACE` | U+0020 | 254 | 25.55% | yes | utf8_fallback=254 |
| 2 | `т` | U+0442 | 95 | 9.56% | yes | message_start=87, utf8_fallback=8 |
| 3 | `н` | U+043D | 69 | 6.94% | yes | message_start=64, utf8_fallback=5 |
| 4 | `д` | U+0434 | 52 | 5.23% | yes | message_start=51, utf8_fallback=1 |
| 5 | `п` | U+043F | 51 | 5.13% |  | message_start=51 |
| 6 | `в` | U+0432 | 47 | 4.73% |  | message_start=44, utf8_fallback=3 |
| 7 | `а` | U+0430 | 46 | 4.63% |  | message_start=45, utf8_fallback=1 |
| 8 | `я` | U+044F | 43 | 4.33% |  | message_start=36, utf8_fallback=7 |
| 9 | `3` | U+0033 | 43 | 4.33% |  | message_start=1, utf8_fallback=42 |
| 10 | `з` | U+0437 | 28 | 2.82% |  | message_start=27, utf8_fallback=1 |
| 11 | `м` | U+043C | 25 | 2.52% |  | message_start=23, utf8_fallback=2 |
| 12 | `1` | U+0031 | 23 | 2.31% |  | message_start=1, utf8_fallback=22 |
| 13 | `с` | U+0441 | 22 | 2.21% |  | message_start=19, utf8_fallback=3 |
| 14 | `к` | U+043A | 19 | 1.91% |  | message_start=14, utf8_fallback=5 |
| 15 | `о` | U+043E | 17 | 1.71% |  | message_start=16, utf8_fallback=1 |
| 16 | `2` | U+0032 | 16 | 1.61% |  | message_start=3, utf8_fallback=13 |
| 17 | `б` | U+0431 | 15 | 1.51% |  | message_start=14, utf8_fallback=1 |
| 18 | `ц` | U+0446 | 14 | 1.41% |  | message_start=14 |
| 19 | `х` | U+0445 | 12 | 1.21% |  | message_start=4, utf8_fallback=8 |
| 20 | `у` | U+0443 | 11 | 1.11% |  | message_start=11 |
| 21 | `щ` | U+0449 | 9 | 0.91% |  | message_start=9 |
| 22 | `ш` | U+0448 | 9 | 0.91% |  | message_start=8, utf8_fallback=1 |
| 23 | `ч` | U+0447 | 8 | 0.80% |  | message_start=6, utf8_fallback=2 |
| 24 | `і` | U+0456 | 8 | 0.80% |  | message_start=8 |
| 25 | `л` | U+043B | 8 | 0.80% |  | message_start=6, utf8_fallback=2 |
| 26 | `0` | U+0030 | 7 | 0.70% |  | utf8_fallback=7 |
| 27 | `5` | U+0035 | 6 | 0.60% |  | message_start=1, utf8_fallback=5 |
| 28 | `7` | U+0037 | 5 | 0.50% |  | utf8_fallback=5 |
| 29 | `8` | U+0038 | 5 | 0.50% |  | utf8_fallback=5 |
| 30 | `е` | U+0435 | 5 | 0.50% |  | message_start=5 |

### AFTER_PUNCT target frequencies — training

| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 837 | 78.96% | yes |
| 2 | `5` | U+0035 | 38 | 3.58% | yes |
| 3 | `0` | U+0030 | 20 | 1.89% | yes |
| 4 | `1` | U+0031 | 19 | 1.79% | yes |
| 5 | `2` | U+0032 | 18 | 1.70% |  |
| 6 | `4` | U+0034 | 16 | 1.51% |  |
| 7 | `я` | U+044F | 12 | 1.13% |  |
| 8 | `3` | U+0033 | 12 | 1.13% |  |
| 9 | `7` | U+0037 | 9 | 0.85% |  |
| 10 | `є` | U+0454 | 7 | 0.66% |  |
| 11 | `т` | U+0442 | 7 | 0.66% |  |
| 12 | `д` | U+0434 | 5 | 0.47% |  |
| 13 | `с` | U+0441 | 5 | 0.47% |  |
| 14 | `6` | U+0036 | 5 | 0.47% |  |
| 15 | `п` | U+043F | 5 | 0.47% |  |
| 16 | `о` | U+043E | 4 | 0.38% |  |
| 17 | `н` | U+043D | 4 | 0.38% |  |
| 18 | `к` | U+043A | 4 | 0.38% |  |
| 19 | `б` | U+0431 | 4 | 0.38% |  |
| 20 | `з` | U+0437 | 4 | 0.38% |  |
| 21 | `8` | U+0038 | 4 | 0.38% |  |
| 22 | `ш` | U+0448 | 3 | 0.28% |  |
| 23 | `9` | U+0039 | 3 | 0.28% |  |
| 24 | `а` | U+0430 | 3 | 0.28% |  |
| 25 | `в` | U+0432 | 2 | 0.19% |  |
| 26 | `ч` | U+0447 | 2 | 0.19% |  |
| 27 | `л` | U+043B | 2 | 0.19% |  |
| 28 | `м` | U+043C | 1 | 0.09% |  |
| 29 | `ф` | U+0444 | 1 | 0.09% |  |
| 30 | `у` | U+0443 | 1 | 0.09% |  |

### Ordinary punctuation that led to AFTER_PUNCT — training

| punctuation | codepoint | following language contexts |
|---|---|---:|
| `,` | U+002C | 488 |
| `.` | U+002E | 333 |
| `-` | U+002D | 79 |
| `?` | U+003F | 33 |
| `"` | U+0022 | 24 |
| `!` | U+0021 | 17 |
| `:` | U+003A | 15 |
| `(` | U+0028 | 15 |
| `/` | U+002F | 14 |
| `'` | U+0027 | 13 |
| `)` | U+0029 | 12 |
| `+` | U+002B | 7 |
| `’` | U+2019 | 3 |
| `_` | U+005F | 3 |
| `#` | U+0023 | 2 |
| `«` | U+00AB | 1 |
| `»` | U+00BB | 1 |

### START target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `SPACE` | U+0020 | 69 | 25.65% | yes | utf8_fallback=69 |
| 2 | `я` | U+044F | 22 | 8.18% |  | message_start=19, utf8_fallback=3 |
| 3 | `п` | U+043F | 21 | 7.81% |  | message_start=21 |
| 4 | `т` | U+0442 | 18 | 6.69% | yes | message_start=17, utf8_fallback=1 |
| 5 | `н` | U+043D | 17 | 6.32% | yes | message_start=17 |
| 6 | `а` | U+0430 | 13 | 4.83% |  | message_start=13 |
| 7 | `3` | U+0033 | 10 | 3.72% |  | utf8_fallback=10 |
| 8 | `о` | U+043E | 9 | 3.35% |  | message_start=9 |
| 9 | `д` | U+0434 | 8 | 2.97% | yes | message_start=7, utf8_fallback=1 |
| 10 | `в` | U+0432 | 8 | 2.97% |  | message_start=6, utf8_fallback=2 |
| 11 | `1` | U+0031 | 7 | 2.60% |  | utf8_fallback=7 |
| 12 | `ц` | U+0446 | 6 | 2.23% |  | message_start=6 |
| 13 | `м` | U+043C | 5 | 1.86% |  | message_start=5 |
| 14 | `с` | U+0441 | 5 | 1.86% |  | message_start=3, utf8_fallback=2 |
| 15 | `2` | U+0032 | 5 | 1.86% |  | utf8_fallback=5 |
| 16 | `і` | U+0456 | 4 | 1.49% |  | message_start=4 |
| 17 | `б` | U+0431 | 4 | 1.49% |  | message_start=4 |
| 18 | `з` | U+0437 | 4 | 1.49% |  | message_start=4 |
| 19 | `е` | U+0435 | 3 | 1.12% |  | message_start=1, utf8_fallback=2 |
| 20 | `щ` | U+0449 | 3 | 1.12% |  | message_start=3 |
| 21 | `к` | U+043A | 3 | 1.12% |  | message_start=2, utf8_fallback=1 |
| 22 | `у` | U+0443 | 2 | 0.74% |  | message_start=2 |
| 23 | `8` | U+0038 | 2 | 0.74% |  | utf8_fallback=2 |
| 24 | `4` | U+0034 | 2 | 0.74% |  | message_start=1, utf8_fallback=1 |
| 25 | `0` | U+0030 | 2 | 0.74% |  | message_start=1, utf8_fallback=1 |
| 26 | `х` | U+0445 | 2 | 0.74% |  | message_start=2 |
| 27 | `ж` | U+0436 | 2 | 0.74% |  | message_start=2 |
| 28 | `є` | U+0454 | 2 | 0.74% |  | message_start=1, utf8_fallback=1 |
| 29 | `ш` | U+0448 | 2 | 0.74% |  | message_start=1, utf8_fallback=1 |
| 30 | `р` | U+0440 | 2 | 0.74% |  | message_start=1, utf8_fallback=1 |

### AFTER_PUNCT target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 277 | 81.71% | yes |
| 2 | `5` | U+0035 | 12 | 3.54% | yes |
| 3 | `0` | U+0030 | 8 | 2.36% | yes |
| 4 | `3` | U+0033 | 5 | 1.47% |  |
| 5 | `7` | U+0037 | 5 | 1.47% |  |
| 6 | `т` | U+0442 | 4 | 1.18% |  |
| 7 | `4` | U+0034 | 4 | 1.18% |  |
| 8 | `з` | U+0437 | 3 | 0.88% |  |
| 9 | `я` | U+044F | 3 | 0.88% |  |
| 10 | `1` | U+0031 | 3 | 0.88% | yes |
| 11 | `д` | U+0434 | 2 | 0.59% |  |
| 12 | `ф` | U+0444 | 2 | 0.59% |  |
| 13 | `6` | U+0036 | 2 | 0.59% |  |
| 14 | `п` | U+043F | 2 | 0.59% |  |
| 15 | `9` | U+0039 | 1 | 0.29% |  |
| 16 | `2` | U+0032 | 1 | 0.29% |  |
| 17 | `м` | U+043C | 1 | 0.29% |  |
| 18 | `с` | U+0441 | 1 | 0.29% |  |
| 19 | `8` | U+0038 | 1 | 0.29% |  |
| 20 | `б` | U+0431 | 1 | 0.29% |  |
| 21 | `к` | U+043A | 1 | 0.29% |  |

## Bit cost breakdown — validation

| category | tokens | bits | share of total bits |
|---|---:|---:|---:|
| TOP-4 variable | 6278 | 17958 | 27.47% |
| Primary literal | 4460 | 31220 | 47.76% |
| Extension literal | 182 | 1638 | 2.51% |
| SHIFT | 222 | 1110 | 1.70% |
| Punctuation | 485 | 3880 | 5.94% |
| UTF-8 fallback | 180 | 7616 | 11.65% |
| Header | 162 | 1944 | 2.97% |

## UTF-8 fallback — validation

- Runs: `180`
- Unicode codepoints: `620`
- UTF-8 bytes: `637`
- Total fallback bits: `7616`
- Share of total encoded bits: `11.65%`

| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 58 | U+0065 | `e` | LATIN SMALL LETTER E |
| 50 | U+0074 | `t` | LATIN SMALL LETTER T |
| 36 | U+0069 | `i` | LATIN SMALL LETTER I |
| 32 | U+0073 | `s` | LATIN SMALL LETTER S |
| 32 | U+006F | `o` | LATIN SMALL LETTER O |
| 31 | U+0061 | `a` | LATIN SMALL LETTER A |
| 26 | U+0072 | `r` | LATIN SMALL LETTER R |
| 24 | U+006D | `m` | LATIN SMALL LETTER M |
| 24 | U+0063 | `c` | LATIN SMALL LETTER C |
| 22 | U+0070 | `p` | LATIN SMALL LETTER P |
| 22 | U+006C | `l` | LATIN SMALL LETTER L |
| 19 | U+0064 | `d` | LATIN SMALL LETTER D |
| 18 | U+0068 | `h` | LATIN SMALL LETTER H |
| 18 | U+006E | `n` | LATIN SMALL LETTER N |
| 15 | U+0075 | `u` | LATIN SMALL LETTER U |
| 11 | U+0044 | `D` | LATIN CAPITAL LETTER D |
| 11 | U+0077 | `w` | LATIN SMALL LETTER W |
| 11 | U+0054 | `T` | LATIN CAPITAL LETTER T |
| 10 | U+044B | `ы` | CYRILLIC SMALL LETTER YERU |
| 10 | U+0066 | `f` | LATIN SMALL LETTER F |
| 10 | U+0062 | `b` | LATIN SMALL LETTER B |
| 8 | U+004C | `L` | LATIN CAPITAL LETTER L |
| 8 | U+004D | `M` | LATIN CAPITAL LETTER M |
| 7 | U+0052 | `R` | LATIN CAPITAL LETTER R |
| 7 | U+0048 | `H` | LATIN CAPITAL LETTER H |
| 7 | U+0043 | `C` | LATIN CAPITAL LETTER C |
| 6 | U+0059 | `Y` | LATIN CAPITAL LETTER Y |
| 6 | U+006B | `k` | LATIN SMALL LETTER K |
| 6 | U+0042 | `B` | LATIN CAPITAL LETTER B |
| 6 | U+0067 | `g` | LATIN SMALL LETTER G |
| 6 | U+0076 | `v` | LATIN SMALL LETTER V |
| 6 | U+0053 | `S` | LATIN CAPITAL LETTER S |
| 5 | U+0045 | `E` | LATIN CAPITAL LETTER E |
| 5 | U+0078 | `x` | LATIN SMALL LETTER X |
| 4 | U+0041 | `A` | LATIN CAPITAL LETTER A |
| 4 | U+0049 | `I` | LATIN CAPITAL LETTER I |
| 4 | U+0071 | `q` | LATIN SMALL LETTER Q |
| 3 | U+004E | `N` | LATIN CAPITAL LETTER N |
| 3 | U+004F | `O` | LATIN CAPITAL LETTER O |
| 3 | U+0057 | `W` | LATIN CAPITAL LETTER W |
| 3 | U+0056 | `V` | LATIN CAPITAL LETTER V |
| 2 | U+0079 | `y` | LATIN SMALL LETTER Y |
| 2 | U+044D | `э` | CYRILLIC SMALL LETTER E |
| 2 | U+0055 | `U` | LATIN CAPITAL LETTER U |
| 2 | U+004B | `K` | LATIN CAPITAL LETTER K |
| 2 | U+02BC | `ʼ` | MODIFIER LETTER APOSTROPHE |
| 2 | U+0050 | `P` | LATIN CAPITAL LETTER P |
| 2 | U+0058 | `X` | LATIN CAPITAL LETTER X |
| 2 | U+0046 | `F` | LATIN CAPITAL LETTER F |
| 2 | U+007A | `z` | LATIN SMALL LETTER Z |
| 1 | U+004A | `J` | LATIN CAPITAL LETTER J |
| 1 | U+2013 | `–` | EN DASH |
| 1 | U+0051 | `Q` | LATIN CAPITAL LETTER Q |
| 1 | U+0047 | `G` | LATIN CAPITAL LETTER G |
| 1 | U+044A | `ъ` | CYRILLIC SMALL LETTER HARD SIGN |

## Most expensive TOP-4 misses — validation

Sorted by avoidable bit cost relative to a hypothetical 3-bit TOP-4 reference hit for the same target. SHIFT cost is excluded because it is paid in both cases.

| previous | next | tier | misses | literal bits | extra vs TOP-4 |
|---|---|---|---:|---:|---:|
| `SPACE` U+0020 | `д` U+0434 | primary | 100 | 7 | 400 |
| `SPACE` U+0020 | `з` U+0437 | primary | 92 | 7 | 368 |
| `SPACE` U+0020 | `м` U+043C | primary | 80 | 7 | 320 |
| `SPACE` U+0020 | `с` U+0441 | primary | 74 | 7 | 296 |
| `SPACE` U+0020 | `р` U+0440 | primary | 58 | 7 | 232 |
| `а` U+0430 | `в` U+0432 | primary | 58 | 7 | 232 |
| `о` U+043E | `с` U+0441 | primary | 56 | 7 | 224 |
| `SPACE` U+0020 | `о` U+043E | primary | 55 | 7 | 220 |
| `SPACE` U+0020 | `і` U+0456 | primary | 55 | 7 | 220 |
| `SPACE` U+0020 | `к` U+043A | primary | 54 | 7 | 216 |
| `а` U+0430 | `м` U+043C | primary | 52 | 7 | 208 |
| `о` U+043E | `б` U+0431 | primary | 52 | 7 | 208 |
| `о` U+043E | `т` U+0442 | primary | 51 | 7 | 204 |
| `SPACE` U+0020 | `б` U+0431 | primary | 49 | 7 | 196 |
| `SPACE` U+0020 | `я` U+044F | primary | 48 | 7 | 192 |
| `н` U+043D | `я` U+044F | primary | 47 | 7 | 188 |
| `SPACE` U+0020 | `а` U+0430 | primary | 45 | 7 | 180 |
| `т` U+0442 | `р` U+0440 | primary | 45 | 7 | 180 |
| `н` U+043D | `и` U+0438 | primary | 42 | 7 | 168 |
| `о` U+043E | `р` U+0440 | primary | 42 | 7 | 168 |
| `а` U+0430 | `к` U+043A | primary | 40 | 7 | 160 |
| `н` U+043D | `н` U+043D | primary | 39 | 7 | 156 |
| `SPACE` U+0020 | `ч` U+0447 | primary | 38 | 7 | 152 |
| `о` U+043E | `ж` U+0436 | primary | 38 | 7 | 152 |
| `в` U+0432 | `с` U+0441 | primary | 36 | 7 | 144 |
| `д` U+0434 | `и` U+0438 | primary | 36 | 7 | 144 |
| `к` U+043A | `SPACE` U+0020 | primary | 36 | 7 | 144 |
| `о` U+043E | `г` U+0433 | primary | 35 | 7 | 140 |
| `т` U+0442 | `у` U+0443 | primary | 35 | 7 | 140 |
| `SPACE` U+0020 | `ц` U+0446 | primary | 33 | 7 | 132 |
| `SPACE` U+0020 | `щ` U+0449 | primary | 33 | 7 | 132 |
| `р` U+0440 | `і` U+0456 | primary | 33 | 7 | 132 |
| `и` U+0438 | `й` U+0439 | primary | 32 | 7 | 128 |
| `т` U+0442 | `е` U+0435 | primary | 32 | 7 | 128 |
| `л` U+043B | `о` U+043E | primary | 31 | 7 | 124 |
| `м` U+043C | `і` U+0456 | primary | 31 | 7 | 124 |
| `т` U+0442 | `SPACE` U+0020 | primary | 31 | 7 | 124 |
| `в` U+0432 | `о` U+043E | primary | 30 | 7 | 120 |
| `SPACE` U+0020 | `2` U+0032 | extension | 20 | 9 | 120 |
| `о` U+043E | `н` U+043D | primary | 29 | 7 | 116 |

## Unsupported symbols in validation

These symbols were encoded losslessly through UTF8_RUN during validation.
| count | codepoint | symbol | Unicode name |
|---:|---|---|---|
| 58 | U+0065 | `e` | LATIN SMALL LETTER E |
| 50 | U+0074 | `t` | LATIN SMALL LETTER T |
| 36 | U+0069 | `i` | LATIN SMALL LETTER I |
| 32 | U+0073 | `s` | LATIN SMALL LETTER S |
| 32 | U+006F | `o` | LATIN SMALL LETTER O |
| 31 | U+0061 | `a` | LATIN SMALL LETTER A |
| 26 | U+0072 | `r` | LATIN SMALL LETTER R |
| 24 | U+006D | `m` | LATIN SMALL LETTER M |
| 24 | U+0063 | `c` | LATIN SMALL LETTER C |
| 22 | U+0070 | `p` | LATIN SMALL LETTER P |
| 22 | U+006C | `l` | LATIN SMALL LETTER L |
| 19 | U+0064 | `d` | LATIN SMALL LETTER D |
| 18 | U+0068 | `h` | LATIN SMALL LETTER H |
| 18 | U+006E | `n` | LATIN SMALL LETTER N |
| 15 | U+0075 | `u` | LATIN SMALL LETTER U |
| 11 | U+0044 | `D` | LATIN CAPITAL LETTER D |
| 11 | U+0077 | `w` | LATIN SMALL LETTER W |
| 11 | U+0054 | `T` | LATIN CAPITAL LETTER T |
| 10 | U+044B | `ы` | CYRILLIC SMALL LETTER YERU |
| 10 | U+0066 | `f` | LATIN SMALL LETTER F |
| 10 | U+0062 | `b` | LATIN SMALL LETTER B |
| 8 | U+004C | `L` | LATIN CAPITAL LETTER L |
| 8 | U+004D | `M` | LATIN CAPITAL LETTER M |
| 7 | U+0052 | `R` | LATIN CAPITAL LETTER R |
| 7 | U+0048 | `H` | LATIN CAPITAL LETTER H |
| 7 | U+0043 | `C` | LATIN CAPITAL LETTER C |
| 6 | U+0059 | `Y` | LATIN CAPITAL LETTER Y |
| 6 | U+006B | `k` | LATIN SMALL LETTER K |
| 6 | U+0042 | `B` | LATIN CAPITAL LETTER B |
| 6 | U+0067 | `g` | LATIN SMALL LETTER G |
| 6 | U+0076 | `v` | LATIN SMALL LETTER V |
| 6 | U+0053 | `S` | LATIN CAPITAL LETTER S |
| 5 | U+0045 | `E` | LATIN CAPITAL LETTER E |
| 5 | U+0078 | `x` | LATIN SMALL LETTER X |
| 4 | U+0041 | `A` | LATIN CAPITAL LETTER A |
| 4 | U+0049 | `I` | LATIN CAPITAL LETTER I |
| 4 | U+0071 | `q` | LATIN SMALL LETTER Q |
| 3 | U+004E | `N` | LATIN CAPITAL LETTER N |
| 3 | U+004F | `O` | LATIN CAPITAL LETTER O |
| 3 | U+0057 | `W` | LATIN CAPITAL LETTER W |
| 3 | U+0056 | `V` | LATIN CAPITAL LETTER V |
| 2 | U+0079 | `y` | LATIN SMALL LETTER Y |
| 2 | U+044D | `э` | CYRILLIC SMALL LETTER E |
| 2 | U+0055 | `U` | LATIN CAPITAL LETTER U |
| 2 | U+004B | `K` | LATIN CAPITAL LETTER K |
| 2 | U+02BC | `ʼ` | MODIFIER LETTER APOSTROPHE |
| 2 | U+0050 | `P` | LATIN CAPITAL LETTER P |
| 2 | U+0058 | `X` | LATIN CAPITAL LETTER X |
| 2 | U+0046 | `F` | LATIN CAPITAL LETTER F |
| 2 | U+007A | `z` | LATIN SMALL LETTER Z |
| 1 | U+004A | `J` | LATIN CAPITAL LETTER J |
| 1 | U+2013 | `–` | EN DASH |
| 1 | U+0051 | `Q` | LATIN CAPITAL LETTER Q |
| 1 | U+0047 | `G` | LATIN CAPITAL LETTER G |
| 1 | U+044A | `ъ` | CYRILLIC SMALL LETTER HARD SIGN |

## Input files

### Train
- `corpora\uk\mcotxt_uk_ru_dataset_clean_final.jsonl`
