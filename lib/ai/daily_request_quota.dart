import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cono_model_tier.dart';

class DailyRequestQuota {
  DailyRequestQuota(this._preferences);

  static final limit = ConoModelTier.phone.dailyRequestLimit;
  static const _storageKey = 'cono_ai_usage_v1';
  static const _tierStorageKey = 'cono_ai_model_tier_v1';
  static Future<void> _writeQueue = Future<void>.value();

  final SharedPreferences _preferences;

  ConoModelTier get selectedTier {
    final storedTier = _preferences.getString(_tierStorageKey);
    if (storedTier == null) {
      return ConoModelTier.phone;
    }
    return ConoModelTier.values.firstWhere(
      (tier) => tier.name == storedTier,
      orElse: () => throw const FormatException(
        'Stored Cono AI model tier is invalid.',
      ),
    );
  }

  Future<void> setTier(ConoModelTier tier) async {
    final saved = await _preferences.setString(_tierStorageKey, tier.name);
    if (!saved) {
      throw Exception('Could not save the selected Cono AI model tier.');
    }
  }

  int get dailyLimit => selectedTier.dailyRequestLimit;

  int get remaining {
    return remainingOn(DateTime.now());
  }

  int remainingOn(DateTime now) {
    final usage = _readUsage();
    if (usage.$1 != _dayKey(now)) {
      return dailyLimit;
    }
    return (dailyLimit - usage.$2).clamp(0, dailyLimit).toInt();
  }

  Future<bool> tryConsume({DateTime? now}) {
    final completer = Completer<bool>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await _consume(now ?? DateTime.now()));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<bool> _consume(DateTime now) async {
    final day = _dayKey(now);
    final usage = _readUsage();
    final count = usage.$1 == day ? usage.$2 : 0;
    final requestLimit = dailyLimit;
    if (count >= requestLimit) {
      return false;
    }

    final saved = await _preferences.setString(
      _storageKey,
      jsonEncode({'day': day, 'count': count + 1}),
    );
    if (!saved) {
      throw Exception('Could not save Cono AI daily usage.');
    }
    return true;
  }

  (String, int) _readUsage() {
    final raw = _preferences.getString(_storageKey);
    if (raw == null) {
      return ('', 0);
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['day'] is! String ||
        decoded['count'] is! int ||
        decoded['count'] < 0) {
      throw const FormatException('Stored Cono AI usage is invalid.');
    }
    return (decoded['day'] as String, decoded['count'] as int);
  }

  static String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
