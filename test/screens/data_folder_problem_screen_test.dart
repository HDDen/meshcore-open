import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/screens/data_folder_problem_screen.dart';
import 'package:meshcore_open/storage/data_root_core.dart';

// The screen put up instead of the app when its data folder cannot be used.
// The hint about --data-dir appears only where the argument is read.

void main() {
  final showsHint = Platform.isWindows || Platform.isLinux;

  testWidgets('a folder in use is named, with the way out', (tester) async {
    await tester.pumpWidget(
      const DataFolderProblemApp(problem: DataRootInUse(r'D:\MCO\userdata')),
    );
    await tester.pumpAndSettle();

    expect(find.text('The data folder is already in use'), findsOneWidget);
    expect(find.textContaining(r'D:\MCO\userdata'), findsOneWidget);
    expect(
      find.textContaining('--data-dir=<path>'),
      showsHint ? findsOneWidget : findsNothing,
    );
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('a folder that cannot be written shows what went wrong', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DataFolderProblemApp(
        problem: DataRootUnavailable(
          r'C:\Program Files\MCO\userdata',
          error: 'Access is denied.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The data folder cannot be used'), findsOneWidget);
    expect(
      find.textContaining(r'C:\Program Files\MCO\userdata'),
      findsOneWidget,
    );
    expect(find.text('Details: Access is denied.'), findsOneWidget);
  });

  testWidgets('an empty --data-dir says how it is written', (tester) async {
    await tester.pumpWidget(
      const DataFolderProblemApp(
        problem: DataRootUnavailable('--data-dir=', missingPath: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The data folder cannot be used'), findsOneWidget);
    expect(find.textContaining('names no folder'), findsOneWidget);
    expect(find.textContaining('Details:'), findsNothing);
  });
}
