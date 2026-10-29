import 'dart:convert';
import 'dart:io';

typedef GitBuildInfoReader = String Function(Directory directory, List<String> args);

String _git(Directory directory, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: directory.path);
  if (result.exitCode != 0) {
    throw ProcessException('git', args, '${result.stderr}', result.exitCode);
  }
  return '${result.stdout}'.trim();
}

/// Only Git metadata is read; no license profiles, keys or application data.
Map<String, Object> collectGitBuildInfo(Directory root, {GitBuildInfoReader? readGit}) {
  final read = readGit ?? _git;
  String commit(Directory directory) {
    final sha = read(directory, ['rev-parse', 'HEAD']);
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) {
      throw const FormatException('Git did not return a full commit SHA');
    }
    return sha;
  }

  final appCommit = commit(root);
  final appDirty = read(root, ['status', '--porcelain']).isNotEmpty;
  final module = Directory('${root.path}/lib_serv');
  final moduleGit = '${module.path}/.git';
  // A regular subdirectory would otherwise inherit the APP's Git repository.
  final hasModuleRepo = Directory(moduleGit).existsSync() || File(moduleGit).existsSync();
  return {
    'MCO_APP_COMMIT': appCommit,
    'MCO_MODULE_COMMIT': hasModuleRepo ? commit(module) : '',
    'MCO_APP_DIRTY': appDirty,
    'MCO_MODULE_DIRTY': hasModuleRepo && read(module, ['status', '--porcelain']).isNotEmpty,
  };
}

File writeGitBuildInfo(Directory root, Map<String, Object> defines) {
  final directory = Directory('${root.path}/.dart_tool')..createSync(recursive: true);
  final destination = File('${directory.path}/mco_build_info.json');
  final temporary = File('${destination.path}.tmp');
  temporary.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(defines)}\n', flush: true);
  return temporary.renameSync(destination.path);
}

void main() {
  // Follow this script, not the shell's cwd, when invoked from another folder.
  final root = File.fromUri(Platform.script).parent.parent;
  try {
    final defines = collectGitBuildInfo(root);
    final output = writeGitBuildInfo(root, defines);
    stdout.writeln('Git build metadata written to ${output.path}');
  } catch (error) {
    stderr.writeln('Could not prepare Git build metadata: $error');
    exitCode = 1; // VSCode must not silently launch with stale metadata.
  }
}
