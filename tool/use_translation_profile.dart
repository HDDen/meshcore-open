import 'dart:io';

/// Minimum iOS version each profile can build against. `flutter_onnxruntime`,
/// which carries AEIC, refuses anything below 16.0; lite ships without it and
/// keeps the floor the app has always built and run against, rather than
/// dropping iPhones for a plugin it does not include.
const _iosDeploymentTargets = {
  'lite': '13.0',
  'lite-aeic': '16.0',
  'full': '16.0',
};

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

  final iosTarget = _iosDeploymentTargets[profile]!;
  _setIosDeploymentTarget(root, iosTarget);

  stdout.writeln('Enabled $profile build profile.');
  stdout.writeln('iOS deployment target set to $iosTarget.');
  stdout.writeln('Run: flutter pub get');
  stdout.writeln('For iOS also: cd ios && rm -rf Pods Podfile.lock '
      '&& pod install');
}

/// Keeps the Podfile platform and every Xcode configuration on the same
/// version. CocoaPods fails the build outright when the Podfile asks for less
/// than a plugin needs, and Xcode happily disagrees with the Podfile until it
/// does.
void _setIosDeploymentTarget(Directory root, String version) {
  final podfile = File('${root.path}/ios/Podfile');
  if (podfile.existsSync()) {
    podfile.writeAsStringSync(
      podfile.readAsStringSync().replaceFirst(
        RegExp("platform :ios, '[^']+'"),
        "platform :ios, '$version'",
      ),
    );
  }

  final project = File('${root.path}/ios/Runner.xcodeproj/project.pbxproj');
  if (project.existsSync()) {
    project.writeAsStringSync(
      project.readAsStringSync().replaceAll(
        RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;'),
        'IPHONEOS_DEPLOYMENT_TARGET = $version;',
      ),
    );
  }
}
