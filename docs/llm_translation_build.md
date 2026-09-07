# LLM Translation Build Flag

MeshCore Open can be built without the on-device LLM translation feature.
This is useful for regional builds where incoming/outgoing message translation
is not needed and the native `llamadart`/LiteRT/Gemma libraries make packages
too large.

This flag does not disable MCMP or MeshCompressor. The current MeshCompressor
asset:

- `assets/models/model-en-ru.json`

remains part of the app because it is used by message compression, not by LLM
translation.

## Current checkout

The checked-in `pubspec.yaml` currently matches the `lite-aeic` profile:
on-device LLM translation is disabled, while the ONNX-backed AEIC image codec
remains enabled. A normal build therefore does not enable translation:

```powershell
flutter build apk --release
```

To enable translation, switch to the full profile before resolving dependencies:

```powershell
dart run tool/use_translation_profile.dart full
flutter pub get
flutter build apk --release
```

## Build without LLM translation on Android

Use:

```powershell
flutter build apk --release --dart-define=MESHCORE_ENABLE_TRANSLATION=false
```

For Android, this also excludes the heavy translation native libraries from the
APK package:

- `libLiteRt*.so`
- `libGemmaModelConstraintProvider.so`
- `libllama*.so`
- `libggml*.so`
- `libllamadart.so`
- `libmtmd.so`

For smaller Android downloads, combine the flag with ABI splitting:

```powershell
flutter build apk --release --split-per-abi --dart-define=MESHCORE_ENABLE_TRANSLATION=false
```

or build an app bundle:

```powershell
flutter build appbundle --release --dart-define=MESHCORE_ENABLE_TRANSLATION=false
```

## Cross-platform dependency profiles

The profile switcher supports three variants:

| Profile | LLM translation | AEIC ONNX codec | Minimum iOS |
|---|---|---|---:|
| `lite` | disabled | disabled | 13.0 |
| `lite-aeic` | disabled | enabled | 16.0 |
| `full` | enabled | enabled | 16.0 |

To remove `llamadart` and `flutter_langdetect` from the dependency graph,
switch to either lite profile before running `flutter pub get`.

Cross-platform command for Windows, Linux, and macOS:

```powershell
dart run tool/use_translation_profile.dart lite-aeic
flutter pub get
```

Then build any target normally, preferably still passing the Dart define so UI
and packaging stay explicit:

```powershell
flutter build apk --release --split-per-abi --dart-define=MESHCORE_ENABLE_TRANSLATION=false
flutter build windows --release --dart-define=MESHCORE_ENABLE_TRANSLATION=false
flutter build linux --release --dart-define=MESHCORE_ENABLE_TRANSLATION=false
flutter build macos --release --dart-define=MESHCORE_ENABLE_TRANSLATION=false
```

The selected profile replaces:

- `pubspec.yaml` with `pubspec.<profile>.yaml`
- `lib/services/translation_service.dart` with a disabled implementation that
  has the same public API but does not import LLM packages for `lite` and
  `lite-aeic`
- `lib/services/image_codec_backend.dart` with the disabled backend for `lite`
  or the ONNX backend for `lite-aeic` and `full`

To restore the full translation profile:

```powershell
dart run tool/use_translation_profile.dart full
flutter pub get
```

The full profile restores:

- `pubspec.full.yaml`
- the LLM-backed `TranslationService` implementation

Windows PowerShell shortcuts are also available:

```powershell
.\tool\use_translation_lite.ps1
.\tool\use_translation_full.ps1
```
