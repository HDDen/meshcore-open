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

The screen requests one-second polling while open. Closing it restores the 30-second interval, or stops stats polling entirely if nothing else is holding it. The chart is a recent view, not a persistent measurement log. Use last-reception metrics together with route and delivery observations rather than interpreting one sample as a complete coverage survey.

The thermometer action opens telemetry for your own companion radio. For remote measurements, see [repeater management](repeater-management.md#repeater-status) and [path tracing](map-and-location.md#path-trace-map).
