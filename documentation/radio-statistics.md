# Companion Radio Statistics

These statistics describe the radio connected to the app. They are separate from a remote repeater’s status and do not measure every link in a mesh path.

## Open the screen

Use Settings → Radio stats, or a radio-stats shortcut where shown. The companion must report firmware version code **8+**. On unsupported firmware the Settings tile is disabled and its subtitle shows the firmware requirement; an unsupported or disconnected radio shows an explanatory state instead of statistics.

## Read the measurements

| Measurement | Meaning |
|---|---|
| Noise floor (dBm) | Radio’s reported background noise level |
| Last RSSI (dBm) | Strength of the last received signal |
| Last SNR (dB) | Signal-to-noise ratio of the last reception |
| TX / RX airtime | Reported accumulated transmit/receive airtime |
| Recent noise chart | Up to 120 received samples while viewing the screen |

Видимый экран запрашивает обновления раз в секунду. При энергосбережении «Выключено» этот интервал сохраняется и вне видимости. Другие профили могут замедлять опрос скрытого экрана и приостанавливать опрос невидимого радиоиндикатора; см. [энергосбережение](power-saving.md). Видимый экран сохраняет частый опрос, обычные потребители — интервал не более 30 с. При включённой приостановке отправка удерживает опрос независимо от индикатора; пока экран статистики смонтирован, незавершённая отправка сохраняет интервал 1 с. После закрытия последнего экрана действует обычный опрос, либо таймер останавливается, если потребителей нет. График показывает последние образцы и не является постоянным журналом измерений. Оценивайте последние значения вместе с маршрутами и доставкой, а не как полную оценку покрытия.

The thermometer action opens telemetry for your own companion radio. For remote measurements, see [repeater management](repeater-management.md#repeater-status) and [path tracing](map-and-location.md#path-trace-map).
