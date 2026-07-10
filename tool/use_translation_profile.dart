import 'dart:io';

void main(List<String> args) {
  if (args.length != 1 || (args.first != 'full' && args.first != 'lite')) {
    stderr.writeln('Usage: dart run tool/use_translation_profile.dart <full|lite>');
    exitCode = 64;
    return;
  }

  final profile = args.first;
  final root = Directory.current;
  final pubspecSource = File('${root.path}/pubspec.$profile.yaml');
  final serviceSource = File(
    '${root.path}/tool/translation_profiles/'
    '${profile == 'full' ? 'translation_service_llm' : 'translation_service_disabled'}.dart.txt',
  );

  if (!pubspecSource.existsSync()) {
    stderr.writeln('Missing ${pubspecSource.path}');
    exitCode = 66;
    return;
  }
  if (!serviceSource.existsSync()) {
    stderr.writeln('Missing ${serviceSource.path}');
    exitCode = 66;
    return;
  }

  pubspecSource.copySync('${root.path}/pubspec.yaml');
  serviceSource.copySync('${root.path}/lib/services/translation_service.dart');

  stdout.writeln(
    profile == 'full'
        ? 'Enabled full LLM translation profile.'
        : 'Enabled lite profile without LLM translation dependencies.',
  );
  stdout.writeln('Run: flutter pub get');
}
