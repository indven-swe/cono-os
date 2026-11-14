import 'package:cono_os/ai/daily_request_quota.dart';
import 'package:cono_os/ai/cono_model_tier.dart';
import 'package:cono_os/ai/cono_model_runtime.dart';
import 'package:cono_os/applications/cono_apps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Notes persists edits in app preferences', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            height: 700,
            width: 400,
            child: NotesApp(preferences: preferences),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'A thought for later');
    await tester.pumpAndSettle();

    expect(preferences.getString('cono_note'), 'A thought for later');
  });

  testWidgets('Cono AI does not use a fallback when no model is available', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final quota = DailyRequestQuota(preferences);
    final initialQuota = quota.remaining;
    final runtime = _FakeConoModelRuntime();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SizedBox(
          height: 700,
          width: 400,
          child: Scaffold(
            body: Material(
              child: ConoAiApp(
                quota: quota,
                runtime: runtime,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'what is ConoOS?');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cono Nova is unavailable in this app build.'),
      findsOneWidget,
    );
    expect(quota.remaining, initialQuota);
    expect(runtime.requests, 0);
  });

  testWidgets('Cono AI saves every tier and applies its request limit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final quota = DailyRequestQuota(preferences);
    final runtime = _FakeConoModelRuntime();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SizedBox(
          height: 700,
          width: 400,
          child: Scaffold(
            body: Material(child: ConoAiApp(quota: quota, runtime: runtime)),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButton<ConoModelTier>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balanced · 38.1M').last);
    await tester.pumpAndSettle();

    expect(quota.selectedTier, ConoModelTier.balanced);
    expect(quota.dailyLimit, 150);
    expect(find.text('150 requests per day'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<ConoModelTier>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large · 85.5M').last);
    await tester.pumpAndSettle();

    expect(quota.selectedTier, ConoModelTier.large);
    expect(quota.dailyLimit, 100);
    expect(find.text('100 requests per day'), findsOneWidget);
  });

  testWidgets(
      'Cono AI routes explicit web commands to Ladybird without a model', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final quota = DailyRequestQuota(preferences);
    final initialQuota = quota.remaining;
    final runtime = _FakeConoModelRuntime();
    Uri? openedWebsite;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SizedBox(
          height: 700,
          width: 400,
          child: Scaffold(
            body: Material(
              child: ConoAiApp(
                quota: quota,
                runtime: runtime,
                onOpenWebsite: (uri) => openedWebsite = uri,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'search for Ladybird browser',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(openedWebsite?.host, 'duckduckgo.com');
    expect(
      openedWebsite?.queryParameters['q'],
      'Ladybird browser',
    );
    expect(find.text('Opening duckduckgo.com in Ladybird.'), findsOneWidget);
    expect(runtime.requests, 0);
    expect(quota.remaining, initialQuota);
  });

  testWidgets('Cono AI generates replies only with the installed local model', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final quota = DailyRequestQuota(preferences);
    final runtime = _FakeConoModelRuntime(
      installedTiers: {ConoModelTier.phone},
      answer: 'Hello from Cono Nova.',
    );
    final initialQuota = quota.remaining;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SizedBox(
          height: 700,
          width: 400,
          child: Scaffold(
            body: Material(child: ConoAiApp(quota: quota, runtime: runtime)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(find.text('Hello from Cono Nova.'), findsOneWidget);
    expect(runtime.lastConversation, 'User: hello');

    await tester.enterText(find.byType(TextField), 'How are you?');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(
      runtime.lastConversation,
      'User: hello\n'
      'Cono Nova: Hello from Cono Nova.\n'
      'User: How are you?',
    );
    expect(runtime.requests, 2);
    expect(quota.remaining, initialQuota - 2);
  });
}

class _FakeConoModelRuntime implements ConoModelRuntime {
  _FakeConoModelRuntime({
    this.installedTiers = const {},
    this.answer = '',
  });

  final Set<ConoModelTier> installedTiers;
  final String answer;
  int requests = 0;
  String? lastConversation;

  @override
  Future<bool> hasModel(ConoModelTier tier) async =>
      installedTiers.contains(tier);

  @override
  Future<void> installModel(String sourcePath, ConoModelTier tier) async {
    installedTiers.add(tier);
  }

  @override
  Future<String> reply(String conversation, ConoModelTier tier) async {
    requests++;
    lastConversation = conversation;
    return answer;
  }

  @override
  Future<void> close() async {}
}
