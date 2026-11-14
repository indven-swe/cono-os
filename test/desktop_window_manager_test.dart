import 'package:cono_os/shell/cono_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop app windows minimize and restore from the taskbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ConoShell(preferences: preferences),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notes').first);
    await tester.pumpAndSettle();
    expect(find.text('QUICK NOTE'), findsOneWidget);

    await tester.tap(find.byTooltip('Minimize Notes'));
    await tester.pumpAndSettle();
    expect(find.text('QUICK NOTE'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Notes'));
    await tester.pumpAndSettle();
    expect(find.text('QUICK NOTE'), findsOneWidget);
  });

  testWidgets('right-click desktop menu opens Cono AI', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ConoShell(preferences: preferences),
      ),
    );
    await tester.pumpAndSettle();

    final rightClick = await tester.startGesture(
      const Offset(600, 400),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await rightClick.up();
    await tester.pumpAndSettle();

    expect(find.text('Cono AI'), findsWidgets);
    await tester.tap(find.text('Cono AI').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('trained from scratch for ConoOS'),
      findsOneWidget,
    );
  });
}
