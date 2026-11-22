# Сборка Linux и Windows с ONNX Runtime без GitHub Releases

Инструкция для x64-сборок MCOa с приватным модулем `lib_serv`, когда GitHub Releases ONNX Runtime отвечает 404. Используется ONNX Runtime **1.22.0** из официального пакета Microsoft на NuGet. Отслеживаемые CMake-конфиги, pubspec и Pub Cache не изменяются.

Flutter-плагин остаётся `flutter_onnxruntime` **1.9.0**. Подмена источника нативной библиотеки не меняет зависимости Android, iOS или macOS. Профиль приложения должен включать ONNX (`lite-aeic` или `full`); профиль `lite` не включает этот backend.

## Источник библиотеки

Официальный пакет: [Microsoft.ML.OnnxRuntime 1.22.0](https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime/1.22.0).

Адрес скачивания:

```text
https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.22.0/microsoft.ml.onnxruntime.1.22.0.nupkg
```

NuGet-пакет является ZIP-архивом. Установка .NET или Python не нужна. В нём находятся C/C++-заголовки и нативные библиотеки для обеих платформ.

SHA-256 полного архива, проверенного 22 ноября 2026 года:

```text
d571e63a2329baacb713f441e65ad75284de354db6e1ac435fe4bebbb417986a
```

При несовпадении суммы остановиться и проверить источник. Не заменять ожидаемую сумму только ради продолжения сборки.

## Общие условия

- Запускать команды из корня приложения, где находятся `pubspec.yaml` и `lib_serv/`.
- Приватный модуль должен быть подключён через `pubspec_overrides.yaml`, как для обычной release-сборки.
- `flutter` и `dart` в `PATH` должны относиться к одному нужному Flutter SDK.
- `release_build.dart` сам добавляет release-режим, обфускацию и сохранение отладочных символов. Аргументы после `--` передаются в `flutter build`.
- `--force` разрешает повторную сборку при уже существующем каталоге символов. Он не запускает `flutter clean` и не очищает кэш ONNX. Не использовать его для разных публикуемых сборок под одним номером версии без учёта сохранности старых символов.

## Ubuntu Linux x64

Пути в примере: Flutter SDK — `~/flutter`, проект — `~/projects/meshcore-open`. Нужны обычные зависимости Flutter Linux, а также `curl`, `unzip` и `sha256sum`. При отсутствии `unzip`: `sudo apt install unzip`.

### Подготовка SDK

```bash
export PATH="$HOME/flutter/bin:$PATH"
hash -r
command -v flutter
command -v dart
flutter --version
```

Оба инструмента должны выбираться из `~/flutter/bin`. Версия Flutter должна удовлетворять текущему профилю проекта; для описываемой сборки требуется 3.47.9.

### Подготовка ONNX и release-сборка

Блок можно скопировать целиком. Он завершится при ошибке загрузки, проверки, распаковки или сборки.

```bash
(
  set -e
  export PATH="$HOME/flutter/bin:$PATH"
  cd "$HOME/projects/meshcore-open"
  test -f pubspec.yaml
  test -f lib_serv/tools/release_build.dart

  work_dir="$(mktemp -d)"
  build_dir="$PWD/build/linux/x64/release"
  runtime_dir="$build_dir/plugins/flutter_onnxruntime/onnxruntime/onnxruntime-linux-x64-1.22.0"

  curl --fail --location --retry 3 \
    "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.22.0/microsoft.ml.onnxruntime.1.22.0.nupkg" \
    --output "$work_dir/onnxruntime.zip"

  printf '%s  %s\n' \
    'd571e63a2329baacb713f441e65ad75284de354db6e1ac435fe4bebbb417986a' \
    "$work_dir/onnxruntime.zip" | sha256sum --check --status

  unzip -q "$work_dir/onnxruntime.zip" -d "$work_dir/package"
  mkdir -p "$runtime_dir/include" "$runtime_dir/lib"
  cp -a "$work_dir/package/build/native/include/." "$runtime_dir/include/"
  cp -a "$work_dir/package/runtimes/linux-x64/native/." "$runtime_dir/lib/"

  cp "$runtime_dir/lib/libonnxruntime.so" "$runtime_dir/lib/libonnxruntime.so.1"
  cp "$runtime_dir/lib/libonnxruntime.so" "$runtime_dir/lib/libonnxruntime.so.1.22.0"
  test -f "$runtime_dir/include/onnxruntime_cxx_api.h"

  # Удаляются только служебные данные CMake, не распакованный runtime.
  # Это также убирает выбор GNU/Makefiles после ручного запуска cmake.
  rm -f -- "$build_dir/CMakeCache.txt"
  rm -rf -- "$build_dir/CMakeFiles"
  printf 'ONNXRUNTIME_VERSION:STRING=1.22.0\n' > "$build_dir/CMakeCache.txt"

  # Flutter сам создаст generated_config.cmake и запустит CMake с Ninja.
  dart run lib_serv/tools/release_build.dart linux --force -- \
    --dart-define=MESHCORE_ENABLE_TRANSLATION=false \
    --dart-define=MCO_SERV=true
)
```

Не запускать `cmake -S linux ...` отдельно до генерации Flutter-файлов: это может дать `generated_config.cmake` not found. Наличие в выводе строки `Downloading ONNX Runtime from: ...github...` само по себе не означает сетевой запрос: плагин печатает URL и при использовании уже распакованного каталога.

### Повторная сборка Linux

Пока `build/` и CMake-кэш сохранены, повторная загрузка не нужна:

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd "$HOME/projects/meshcore-open"
dart run lib_serv/tools/release_build.dart linux --force -- --dart-define=MESHCORE_ENABLE_TRANSLATION=false --dart-define=MCO_SERV=true
```

После `flutter clean`, удаления `build/` или сброса CMake-кэша повторить подготовку. Сначала очистка, затем подготовка ONNX, затем release-сборка.

Результат: `build/linux/x64/release/bundle/`. Передавать весь bundle вместе с его `lib/` и `data/`.

## Windows x64

Пути в примере: проект — `V:\_temporary-git\meshcore-open`, Flutter SDK — `V:\Program Files\flutter\flutter`. Если SDK установлен иначе, изменить только переменную `$flutterSdk` ниже.

### Подготовка SDK

В PowerShell:

```powershell
$flutterSdk = 'V:\Program Files\flutter\flutter'
$env:PATH = (Join-Path $flutterSdk 'bin') + [IO.Path]::PathSeparator + $env:PATH
Set-Location -LiteralPath 'V:\_temporary-git\meshcore-open'
Get-Command flutter, dart | Select-Object Name, Source
flutter --version
```

### Подготовка кэша ONNX

Windows CMake уже использует постоянный каталог `windows/.cache/onnxruntime/onnxruntime-win-x64-1.22.0`. Если там есть проверенная библиотека, можно сразу перейти к сборке. Если кэша нет, заполнить его из NuGet:

```powershell
& {
    $ErrorActionPreference = 'Stop'
    Set-Location -LiteralPath 'V:\_temporary-git\meshcore-open'
    $projectRoot = (Get-Location).Path
    $workDir = Join-Path ([IO.Path]::GetTempPath()) ('meshcore-onnx-' + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $workDir
    $archive = Join-Path $workDir 'onnxruntime.zip'
    $packageDir = Join-Path $workDir 'package'
    $runtimeDir = Join-Path $projectRoot 'windows/.cache/onnxruntime/onnxruntime-win-x64-1.22.0'

    Invoke-WebRequest -Uri 'https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.22.0/microsoft.ml.onnxruntime.1.22.0.nupkg' -OutFile $archive
    $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($archiveHash -ne 'd571e63a2329baacb713f441e65ad75284de354db6e1ac435fe4bebbb417986a') {
        throw 'ONNX Runtime: SHA-256 архива не совпадает'
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $packageDir

    $includeDir = Join-Path $runtimeDir 'include'
    $libDir = Join-Path $runtimeDir 'lib'
    $null = New-Item -ItemType Directory -Path $includeDir, $libDir -Force
    Get-ChildItem -LiteralPath (Join-Path $packageDir 'build/native/include') |
        Copy-Item -Destination $includeDir -Recurse -Force
    Get-ChildItem -LiteralPath (Join-Path $packageDir 'runtimes/win-x64/native') |
        Copy-Item -Destination $libDir -Recurse -Force

    # Те же суммы, которые требует windows/cmake/prepare_onnxruntime.cmake.
    $expected = @{
        'lib/onnxruntime.dll' = '579b636403983254346a5c1d80bd28f1519cd1e284cd204f8d4ff41f8d711559'
        'lib/onnxruntime.lib' = 'ab00cba665b186c0d29df9c575d34fd2bcc8f9b9ecae997f81610d07b2fc8ebc'
        'include/onnxruntime_cxx_api.h' = '7606924bbc40810a72fca54d8aff75c9564908301241eb835bc1814a3aee4ad8'
    }
    foreach ($relative in $expected.Keys) {
        $actual = (Get-FileHash -LiteralPath (Join-Path $runtimeDir $relative) -Algorithm SHA256).Hash
        if ($actual -ne $expected[$relative]) {
            throw "ONNX Runtime: SHA-256 не совпадает для $relative"
        }
    }
    Write-Host "Кэш ONNX Runtime 1.22.0 подготовлен: $runtimeDir"
}
```

Не менять контрольные суммы в CMake для принятия другого бинарного файла. DLL, import library и заголовок из указанного NuGet-пакета совпадают с уже закреплёнными суммами проекта. Валидный кэш позволяет CMake пропустить GitHub-загрузку.

### Release-сборка Windows

После успешного завершения подготовки, в том же PowerShell с настроенным `PATH`:

```powershell
Set-Location -LiteralPath 'V:\_temporary-git\meshcore-open'
dart run lib_serv/tools/release_build.dart windows --force -- --dart-define=MESHCORE_ENABLE_TRANSLATION=false --dart-define=MCO_SERV=true
if ($LASTEXITCODE -ne 0) { throw 'Release-сборка Windows завершилась с ошибкой' }
explorer.exe "V:\_temporary-git\meshcore-open\build\windows\x64\runner\"
```

Откроется родительский каталог `runner`. Файлы готового приложения находятся в `build/windows/x64/runner/Release/`. Распространять весь каталог Release. Обычный `flutter clean` не удаляет постоянный ONNX-кэш в `windows/.cache/`, но удаление этого каталога потребует повторной подготовки.

## Проверка результата

- В логе Linux должна использоваться ONNX Runtime **1.22.0**; Windows должен сообщать `Using cached ONNX Runtime`.
- Отладочные символы и сведения о сборке сохраняются в `lib_serv/symbols/<версия>/<платформа>/<коммит>/`. Сообщение `symbols left in place` после ошибки означает, что сборка не завершена; оно не указывает первопричину.
- Проверить запуск готового приложения из каталога вне дерева сборки. На Linux выполнить `ldd` для исполняемого файла и ONNX-плагина из bundle: зависимостей `not found` быть не должно.
- Проверить кодирование и декодирование AEIC с установленными моделями. Успех компиляции ещё не подтверждает работу моделей. MCOimg и AEIC — разные форматы; проверка только MCOimg не проверяет ONNX.
- Инструкция рассчитана на x64. Для ARM64 нужны другие каталоги native и отдельная проверка зависимостей.

Оба варианта оставляют временно скачанный пакет в системном временном каталоге. После успешной подготовки его можно удалить отдельно; каталог runtime должен оставаться на месте согласно правилам соответствующей платформы.
