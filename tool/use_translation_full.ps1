$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Copy-Item -LiteralPath (Join-Path $root 'pubspec.full.yaml') -Destination (Join-Path $root 'pubspec.yaml') -Force
Copy-Item -LiteralPath (Join-Path $root 'tool\translation_profiles\translation_service_llm.dart.txt') -Destination (Join-Path $root 'lib\services\translation_service.dart') -Force

Write-Host 'Enabled full LLM translation profile.'
Write-Host 'Run: flutter pub get'
