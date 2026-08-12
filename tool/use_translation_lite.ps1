$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Copy-Item -LiteralPath (Join-Path $root 'pubspec.lite.yaml') -Destination (Join-Path $root 'pubspec.yaml') -Force
Copy-Item -LiteralPath (Join-Path $root 'tool\translation_profiles\translation_service_disabled.dart.txt') -Destination (Join-Path $root 'lib\services\translation_service.dart') -Force
Copy-Item -LiteralPath (Join-Path $root 'tool\image_codec_profiles\image_codec_backend_disabled.dart.txt') -Destination (Join-Path $root 'lib\services\image_codec_backend.dart') -Force

Write-Host 'Enabled lite profile without LLM translation or AEIC dependencies.'
Write-Host 'Run: flutter pub get'
