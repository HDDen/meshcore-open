$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Copy-Item -LiteralPath (Join-Path $root 'pubspec.lite.yaml') -Destination (Join-Path $root 'pubspec.yaml') -Force
Copy-Item -LiteralPath (Join-Path $root 'tool\translation_profiles\translation_service_disabled.dart.txt') -Destination (Join-Path $root 'lib\services\translation_service.dart') -Force

Write-Host 'Enabled lite profile without LLM translation dependencies.'
Write-Host 'Run: flutter pub get'
