import 'dart:convert';

import 'package:cono_os/ai/daily_request_quota.dart';
import 'package:cono_os/ai/cono_model_tier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('allows at most 200 requests and resets on the next local day', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final quota = DailyRequestQuota(preferences);
    final today = DateTime(2026, 11, 13, 9);

    for (var request = 0; request < DailyRequestQuota.limit; request++) {
      expect(await quota.tryConsume(now: today), isTrue);
    }

    expect(await quota.tryConsume(now: today), isFalse);
    expect(quota.remainingOn(today), 0);
    expect(
      await quota.tryConsume(now: today.add(const Duration(days: 1))),
      isTrue,
    );
  });

  test('applies the selected model tier daily limit', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final quota = DailyRequestQuota(preferences);
    final today = DateTime(2026, 11, 13, 9);
    await preferences.setString(
      'cono_ai_usage_v1',
      jsonEncode({'day': '2026-11-13', 'count': 100}),
    );

    await quota.setTier(ConoModelTier.large);
    expect(quota.dailyLimit, 100);
    expect(await quota.tryConsume(now: today), isFalse);

    await quota.setTier(ConoModelTier.balanced);
    expect(quota.dailyLimit, 150);
    expect(await quota.tryConsume(now: today), isTrue);
    expect(quota.remainingOn(today), 49);

    await quota.setTier(ConoModelTier.phone);
    expect(quota.dailyLimit, 200);
    expect(quota.remainingOn(today), 99);
  });
}
