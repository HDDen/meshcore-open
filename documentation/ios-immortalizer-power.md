# Энергосбережение встроенного удержания iOS

Параметры находятся в «Энергосбережение → Свои настройки → iOS: фоновое
удержание». Группа отображается только на iOS. Все готовые профили, включая
«Максимальную экономию», пока используют исходные значения этой группы.
Переключение профиля сохраняет выбранные пользователем custom-значения.
Минимальная версия iOS проекта остаётся 16.0; эффективность новых опций на
конкретных версиях ОС и устройствах ещё требует проверки.

Эти параметры не включают удержание сами по себе. Сохраняются прежние условия:
разрешён фоновый TCP и установлено TCP-подключение к ноде (LAN или Tailscale,
включая автоматическое восстановление ранее установленного соединения), либо
работает TCP-раздача companion-прокси. Для TCP-раздачи открытого listener
достаточно, подключённый клиент не обязателен. Только BLE этих причин не создаёт.
Плавающая кнопка по-прежнему позволяет вручную выключить удержание; ручной OFF
сохраняется через перезапуск до ручного ON. Её внешний вид и сворачивание не менялись.

## Параметры

| Настройка | Исходное значение | Эксперимент |
|---|---|---|
| Пауза планирования кадров в фоне | Выключена | Останавливает обычные запросы UI-кадров при закрытом native presentation gate. Состояние Flutter lifecycle, Dart isolate, таймеры и обработчики транспорта сохраняются. Уже запрошенный кадр может прийти; forced/warm-up кадры защищены прежними pipeline/GPU guards. При возврате запрашивается кадр с накопленными изменениями. |
| Облегчённая обработка native hooks | Выключена | Повторно использует регулярные выражения и пропускает ненужную обработку scene diff. Маркеры, порядок отложенных вызовов/completions, flush и предел очереди сохраняются. |
| Режим удержания | Штатный, с тихим аудио | «Без аудио» сохраняет hooks, но полностью убирает наш тихий player. iOS может приостановить приложение и доставку: это эксперимент, а не обещание работы TCP без аудио. |
| Частота файла тишины | 8 кГц | Выбирает фактическую частоту активного аудиовыхода; не запрашивает новую аппаратную частоту. При недоступном/неподдерживаемом значении используется 8 кГц. |
| Предпочтительный аудиобуфер | Системная | Затем 10–200 мс с шагом 10 мс. «Системная» не задаёт предпочтение. Запрос выполняется до активации нашей audio session; отказ не отключает прежний аудиопуть. |
| Длина цикла тишины | 1 с | 1–10 с с шагом 1 с. PCM16 mono; больший цикл/частота увеличивают память. Собственного секундного таймера в player нет, поэтому выигрыш от длинного цикла пока неизвестен. |

При режиме без аудио настройки частоты, буфера и цикла недоступны для изменения,
но сохраняются и снова применяются после возврата штатного режима. Изменение
аудиопараметров перезапускает только наш player; опции UI/hooks сами по себе
аудио не перезапускают. На переднем плане player не работает. Сохраняется
`mixWithOthers`; очистка восстанавливает прежнюю category/preference только
если они ещё принадлежат нашему аудиопути и не были заменены другой функцией.

Предпочтение буфера — подсказка системе, а не гарантированный интервал.
Сравнивать actual следует после активации, по `event=started`. Изменение активной
session может перезапустить I/O; это учтено остановкой нашего player перед сменой
предпочтения. См. [Apple QA1631](https://developer.apple.com/library/archive/qa/qa1631/_index.html).

## Программные проверки

Из корня проекта в PowerShell, перед полной сборкой:

```powershell
Set-Location O:\_git\meshcore-open
flutter gen-l10n
if ($LASTEXITCODE -ne 0) { throw 'Localization generation failed' }

$iosImmortalizerTests = @(
  'test/helpers/ios_execution_diagnostics_baseline_test.dart'
  'test/helpers/ios_rendering_frame_gate_baseline_test.dart'
  'test/helpers/ios_render_pipeline_baseline_test.dart'
  'test/helpers/ios_presentation_guard_test.dart'
  'test/helpers/ios_background_execution_binding_test.dart'
  'test/helpers/ios_frame_diagnostics_test.dart'
  'test/helpers/ios_execution_diagnostics_test.dart'
  'test/screens/app_debug_log_ios_diagnostics_test.dart'
  'test/models/power_saving_settings_test.dart'
  'test/screens/power_saving_screen_test.dart'
  'test/models/ios_immortalizer_power_options_test.dart'
  'test/helpers/ios_immortalizer_power_binding_test.dart'
  'test/helpers/ios_frame_scheduling_power_test.dart'
  'test/widgets/ios_immortalizer_settings_card_test.dart'
)
if ($iosImmortalizerTests.Count -ne 14) { throw 'Expected fourteen iOS test files' }
flutter test @iosImmortalizerTests --exclude-tags=slow --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'iOS Immortalizer tests failed' }
flutter analyze
```

Flutter не компилирует ObjC/Swift и не проверяет настоящую audio session.
На Mac доступны native XCTest для parser/controller/manual OFF, WAV header/bounds,
эквивалентности classifier и исходной кнопки. Сначала определить destination:

```bash
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -showdestinations
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS,id=IPHONE_UDID' -only-testing:RunnerTests/RunnerTests -only-testing:RunnerTests/ExecutionButtonTests test
```

Заменить `IPHONE_UDID` идентификатором своего iPhone; при доступном симуляторе можно
выбрать его destination. Отдельного разрешения hooks/audio реальными XCTest
не доказывают: controller использует fake, WAV/classifier — чистые проверки.

## Сборка и приёмка

Нужна полная iOS-сборка на Mac из корня проекта; hot reload недостаточно:

```bash
dart run lib_serv/tools/release_build.dart ios --force -- --dart-define=MCO_SERV=true --dart-define=MESHCORE_ENABLE_TRANSLATION=false
```

Новых build flags для этих настроек нет. Этот шаг не меняет Go-библиотеку,
encrypted blobs или поколения лицензирования. Обычные новые подписи добавлены
только в ru/en ARB; сгенерированные Dart-файлы создаёт владелец командой выше.

1. Сначала проверить новую сборку с исходными значениями всех шести опций.
2. В той же сборке менять по одному параметру, затем проверять полезные сочетания.
   Начать с LAN TCP, отдельно проверить Tailscale и TCP-прокси с подключением
   клиента уже после ухода сервера в фон.
3. Проверить приём/отправку, переподключение, ручной OFF/ON, возврат без пропавших
   букв, музыку/звонок и смену аудиовыхода. Режим без аудио требует длительной
   проверки без debugger: короткое окно не исключает последующий suspend.
4. Скопировать журнал по [инструкции диагностики](ios-background-diagnostics.md).
   `power.*` — эффективные запрошенные параметры; `sampleRate`, `ioBufferDuration`
   и формат player — фактические показания. Контрольные значения и длительность
   окна нужно приложить к сравнению энергии. Короткий опыт 5–10 минут проверяет
   работу/снимки, но не экономию батареи.

До аппаратной приёмки новые опции экспериментальны. Успешные программные тесты
не подтверждают расход, фоновую доставку и отсутствие glyph corruption на iPhone.
