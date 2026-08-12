import 'dart:io';

void main(List<String> args) {
  const profiles = {'full', 'lite', 'lite-aeic'};
  if (args.length != 1 || !profiles.contains(args.first)) {
    stderr.writeln(
      'Usage: dart run tool/use_translation_profile.dart '
      '<full|lite|lite-aeic>',
    );
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
  final imageBackendSource = File(
    '${root.path}/tool/image_codec_profiles/'
    '${profile == 'lite' ? 'image_codec_backend_disabled' : 'image_codec_backend_onnx'}.dart.txt',
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
  if (!imageBackendSource.existsSync()) {
    stderr.writeln('Missing ${imageBackendSource.path}');
    exitCode = 66;
    return;
  }

  pubspecSource.copySync('${root.path}/pubspec.yaml');
  serviceSource.copySync('${root.path}/lib/services/translation_service.dart');
  imageBackendSource.copySync(
    '${root.path}/lib/services/image_codec_backend.dart',
  );

  stdout.writeln('Enabled $profile build profile.');
  stdout.writeln('Run: flutter pub get');
}
