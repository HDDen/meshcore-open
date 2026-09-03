# MCOtxt v1 model report — RU

## Build

- Language wire ID: `1`
- Unicode database: `15.1.0`
- Primary selection: `literal-savings`
- Canonical language symbols: `44`
- Primary: `31`
- Extension: `13`
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
- Training TOP-4 hit rate: `57.13%`

## Validation

- Source: `deterministic SHA-256 hold-out (20.0%)`
- Explicit validation files: `0`
- Messages: `5626`
- Original UTF-8 bytes: `361814`
- Normalized codepoints: `203395`
- Output codepoints (supported + punctuation): `198014`
- Skipped unsupported: `5381`
- Language symbols: `190004`
- TOP-4 hits: `108358` (`57.03%`)
- Primary literals: `79183`
- Extension literals: `2463`
- SHIFT tokens: `7532`
- Punctuation tokens: `8010`
- Token bits: `1003262`
- Header bits (9/message): `50634`
- Total bits: `1053896`
- Bits/output-char, tokens only: `5.0666`
- Bits/output-char, incl. per-message header: `5.3223`
- UTF-8 bytes of the same decoded/supported text: `356305`
- Compression ratio vs same decoded UTF-8: `2.7047x`

> Validation here is single-language model evaluation. It includes real MCOtxt v1 TOP-4 / literal / SHIFT / punctuation costs and a 9-bit header per message, but does not model A/B TOGGLE or SWITCH_OTHER_LANGUAGE for mixed-language messages.

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
| 14 | primary | `г` | U+0433 | 10045 |
| 15 | primary | `ч` | U+0447 | 9791 |
| 16 | primary | `в` | U+0432 | 23889 |
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
| 31 | extension | `ф` | U+0444 | 1369 |
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
- `2` → index `13` → U+0434 'д' CYRILLIC SMALL LETTER DE
- `3` → index `16` → U+0432 'в' CYRILLIC SMALL LETTER VE

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
| `message_start` | 22824 |

### START target frequencies — training

| rank | symbol | codepoint | count | share | in START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `п` | U+043F | 3441 | 15.08% | yes | message_start=3441 |
| 2 | `н` | U+043D | 2220 | 9.73% | yes | message_start=2220 |
| 3 | `д` | U+0434 | 1938 | 8.49% | yes | message_start=1938 |
| 4 | `в` | U+0432 | 1909 | 8.36% | yes | message_start=1909 |
| 5 | `с` | U+0441 | 1408 | 6.17% |  | message_start=1408 |
| 6 | `а` | U+0430 | 1386 | 6.07% |  | message_start=1386 |
| 7 | `т` | U+0442 | 1351 | 5.92% |  | message_start=1351 |
| 8 | `к` | U+043A | 1020 | 4.47% |  | message_start=1020 |
| 9 | `о` | U+043E | 859 | 3.76% |  | message_start=859 |
| 10 | `у` | U+0443 | 850 | 3.72% |  | message_start=850 |
| 11 | `я` | U+044F | 776 | 3.40% |  | message_start=776 |
| 12 | `м` | U+043C | 715 | 3.13% |  | message_start=715 |
| 13 | `и` | U+0438 | 594 | 2.60% |  | message_start=594 |
| 14 | `ч` | U+0447 | 491 | 2.15% |  | message_start=491 |
| 15 | `е` | U+0435 | 456 | 2.00% |  | message_start=456 |
| 16 | `э` | U+044D | 450 | 1.97% |  | message_start=450 |
| 17 | `з` | U+0437 | 435 | 1.91% |  | message_start=435 |
| 18 | `б` | U+0431 | 386 | 1.69% |  | message_start=386 |
| 19 | `р` | U+0440 | 364 | 1.59% |  | message_start=364 |
| 20 | `х` | U+0445 | 274 | 1.20% |  | message_start=274 |
| 21 | `г` | U+0433 | 244 | 1.07% |  | message_start=244 |
| 22 | `SPACE` | U+0020 | 215 | 0.94% |  | message_start=215 |
| 23 | `л` | U+043B | 159 | 0.70% |  | message_start=159 |
| 24 | `1` | U+0031 | 134 | 0.59% |  | message_start=134 |
| 25 | `2` | U+0032 | 119 | 0.52% |  | message_start=119 |
| 26 | `3` | U+0033 | 102 | 0.45% |  | message_start=102 |
| 27 | `4` | U+0034 | 91 | 0.40% |  | message_start=91 |
| 28 | `ж` | U+0436 | 84 | 0.37% |  | message_start=84 |
| 29 | `ш` | U+0448 | 73 | 0.32% |  | message_start=73 |
| 30 | `ф` | U+0444 | 49 | 0.21% |  | message_start=49 |

### AFTER_PUNCT target frequencies — training

| rank | symbol | codepoint | count | share | in AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 13211 | 80.06% | yes |
| 2 | `т` | U+0442 | 434 | 2.63% | yes |
| 3 | `1` | U+0031 | 288 | 1.75% | yes |
| 4 | `к` | U+043A | 190 | 1.15% | yes |
| 5 | `с` | U+0441 | 173 | 1.05% |  |
| 6 | `н` | U+043D | 156 | 0.95% |  |
| 7 | `3` | U+0033 | 155 | 0.94% |  |
| 8 | `п` | U+043F | 146 | 0.88% |  |
| 9 | `2` | U+0032 | 144 | 0.87% |  |
| 10 | `5` | U+0035 | 124 | 0.75% |  |
| 11 | `в` | U+0432 | 122 | 0.74% |  |
| 12 | `4` | U+0034 | 104 | 0.63% |  |
| 13 | `0` | U+0030 | 95 | 0.58% |  |
| 14 | `м` | U+043C | 93 | 0.56% |  |
| 15 | `7` | U+0037 | 89 | 0.54% |  |
| 16 | `з` | U+0437 | 84 | 0.51% |  |
| 17 | `9` | U+0039 | 77 | 0.47% |  |
| 18 | `д` | U+0434 | 73 | 0.44% |  |
| 19 | `о` | U+043E | 69 | 0.42% |  |
| 20 | `8` | U+0038 | 68 | 0.41% |  |
| 21 | `а` | U+0430 | 65 | 0.39% |  |
| 22 | `6` | U+0036 | 59 | 0.36% |  |
| 23 | `р` | U+0440 | 54 | 0.33% |  |
| 24 | `и` | U+0438 | 54 | 0.33% |  |
| 25 | `л` | U+043B | 50 | 0.30% |  |
| 26 | `е` | U+0435 | 42 | 0.25% |  |
| 27 | `я` | U+044F | 41 | 0.25% |  |
| 28 | `ч` | U+0447 | 41 | 0.25% |  |
| 29 | `х` | U+0445 | 40 | 0.24% |  |
| 30 | `б` | U+0431 | 38 | 0.23% |  |

### Ordinary punctuation that led to AFTER_PUNCT — training

| punctuation | codepoint | following language contexts |
|---|---|---:|
| `,` | U+002C | 7261 |
| `.` | U+002E | 4086 |
| `-` | U+002D | 1952 |
| `?` | U+003F | 683 |
| `)` | U+0029 | 446 |
| `!` | U+0021 | 347 |
| `/` | U+002F | 271 |
| `"` | U+0022 | 270 |
| `\` | U+005C | 263 |
| `:` | U+003A | 209 |
| `(` | U+0028 | 203 |
| `+` | U+002B | 146 |
| `%` | U+0025 | 56 |
| `#` | U+0023 | 45 |
| `[` | U+005B | 45 |
| `]` | U+005D | 43 |
| `_` | U+005F | 33 |
| `«` | U+00AB | 32 |
| `=` | U+003D | 27 |
| `@` | U+0040 | 23 |
| `»` | U+00BB | 21 |
| `—` | U+2014 | 16 |
| `'` | U+0027 | 13 |
| `;` | U+003B | 6 |
| `&` | U+0026 | 5 |

### START target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by START TOP-4 | reason breakdown |
|---:|---|---|---:|---:|---|---|
| 1 | `п` | U+043F | 675 | 12.14% | yes | message_start=675 |
| 2 | `н` | U+043D | 556 | 10.00% | yes | message_start=556 |
| 3 | `д` | U+0434 | 548 | 9.86% | yes | message_start=548 |
| 4 | `в` | U+0432 | 465 | 8.36% | yes | message_start=465 |
| 5 | `а` | U+0430 | 350 | 6.29% |  | message_start=350 |
| 6 | `с` | U+0441 | 334 | 6.01% |  | message_start=334 |
| 7 | `т` | U+0442 | 311 | 5.59% |  | message_start=311 |
| 8 | `к` | U+043A | 235 | 4.23% |  | message_start=235 |
| 9 | `о` | U+043E | 229 | 4.12% |  | message_start=229 |
| 10 | `у` | U+0443 | 225 | 4.05% |  | message_start=225 |
| 11 | `и` | U+0438 | 176 | 3.17% |  | message_start=176 |
| 12 | `я` | U+044F | 173 | 3.11% |  | message_start=173 |
| 13 | `м` | U+043C | 160 | 2.88% |  | message_start=160 |
| 14 | `ч` | U+0447 | 121 | 2.18% |  | message_start=121 |
| 15 | `р` | U+0440 | 108 | 1.94% |  | message_start=108 |
| 16 | `е` | U+0435 | 106 | 1.91% |  | message_start=106 |
| 17 | `э` | U+044D | 103 | 1.85% |  | message_start=103 |
| 18 | `з` | U+0437 | 97 | 1.74% |  | message_start=97 |
| 19 | `б` | U+0431 | 91 | 1.64% |  | message_start=91 |
| 20 | `г` | U+0433 | 81 | 1.46% |  | message_start=81 |
| 21 | `SPACE` | U+0020 | 67 | 1.21% |  | message_start=67 |
| 22 | `х` | U+0445 | 67 | 1.21% |  | message_start=67 |
| 23 | `1` | U+0031 | 49 | 0.88% |  | message_start=49 |
| 24 | `л` | U+043B | 48 | 0.86% |  | message_start=48 |
| 25 | `2` | U+0032 | 31 | 0.56% |  | message_start=31 |
| 26 | `3` | U+0033 | 24 | 0.43% |  | message_start=24 |
| 27 | `4` | U+0034 | 19 | 0.34% |  | message_start=19 |
| 28 | `ж` | U+0436 | 18 | 0.32% |  | message_start=18 |
| 29 | `ш` | U+0448 | 17 | 0.31% |  | message_start=17 |
| 30 | `5` | U+0035 | 16 | 0.29% |  | message_start=16 |

### AFTER_PUNCT target frequencies — validation

| rank | symbol | codepoint | count | share | predicted by AFTER_PUNCT TOP-4 |
|---:|---|---|---:|---:|---|
| 1 | `SPACE` | U+0020 | 3577 | 81.82% | yes |
| 2 | `т` | U+0442 | 108 | 2.47% | yes |
| 3 | `1` | U+0031 | 70 | 1.60% | yes |
| 4 | `3` | U+0033 | 47 | 1.08% |  |
| 5 | `н` | U+043D | 45 | 1.03% |  |
| 6 | `с` | U+0441 | 40 | 0.91% |  |
| 7 | `п` | U+043F | 39 | 0.89% |  |
| 8 | `к` | U+043A | 31 | 0.71% | yes |
| 9 | `4` | U+0034 | 28 | 0.64% |  |
| 10 | `2` | U+0032 | 28 | 0.64% |  |
| 11 | `в` | U+0432 | 26 | 0.59% |  |
| 12 | `0` | U+0030 | 24 | 0.55% |  |
| 13 | `9` | U+0039 | 24 | 0.55% |  |
| 14 | `5` | U+0035 | 23 | 0.53% |  |
| 15 | `р` | U+0440 | 21 | 0.48% |  |
| 16 | `8` | U+0038 | 20 | 0.46% |  |
| 17 | `7` | U+0037 | 19 | 0.43% |  |
| 18 | `а` | U+0430 | 18 | 0.41% |  |
| 19 | `д` | U+0434 | 18 | 0.41% |  |
| 20 | `м` | U+043C | 16 | 0.37% |  |
| 21 | `о` | U+043E | 16 | 0.37% |  |
| 22 | `б` | U+0431 | 14 | 0.32% |  |
| 23 | `г` | U+0433 | 13 | 0.30% |  |
| 24 | `з` | U+0437 | 13 | 0.30% |  |
| 25 | `6` | U+0036 | 12 | 0.27% |  |
| 26 | `е` | U+0435 | 11 | 0.25% |  |
| 27 | `ч` | U+0447 | 11 | 0.25% |  |
| 28 | `у` | U+0443 | 9 | 0.21% |  |
| 29 | `и` | U+0438 | 9 | 0.21% |  |
| 30 | `х` | U+0445 | 9 | 0.21% |  |

## Bit cost breakdown — validation

| category | tokens | bits | share of total bits |
|---|---:|---:|---:|
| TOP-4 | 108358 | 325074 | 30.84% |
| Primary literal | 79183 | 554281 | 52.59% |
| Extension literal | 2463 | 22167 | 2.10% |
| SHIFT | 7532 | 37660 | 3.57% |
| Punctuation | 8010 | 64080 | 6.08% |
| Header | 5626 | 50634 | 4.80% |

## Most expensive TOP-4 misses — validation

Sorted by avoidable bit cost relative to a hypothetical TOP-4 hit for the same target. SHIFT cost is excluded because it is paid in both cases.

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
| `о` U+043E | `м` U+043C | primary | 762 | 7 | 3048 |
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
