import 'package:flutter/foundation.dart';

class LadybirdBrowserController extends ChangeNotifier {
  Uri? _currentUri;
  var _navigationRevision = 0;

  Uri? get currentUri => _currentUri;
  int get navigationRevision => _navigationRevision;

  void navigate(Uri uri) {
    if (!LadybirdAddress.isWebAddress(uri)) {
      throw ArgumentError.value(
          uri, 'uri', 'Only HTTP and HTTPS pages are allowed.');
    }
    _currentUri = uri;
    _navigationRevision++;
    notifyListeners();
  }
}

class LadybirdAddress {
  static const _searchHost = 'duckduckgo.com';

  static Uri? resolve(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.contains(RegExp(r'\s'))) {
      return search(value);
    }

    final hasExplicitWebScheme =
        RegExp(r'^https?://', caseSensitive: false).hasMatch(value);
    final hasAuthorityScheme =
        RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(value);
    if (hasAuthorityScheme && !hasExplicitWebScheme) {
      return null;
    }
    final hasScheme =
        RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(value);
    final looksLikePort = RegExp(r'^[^/:?#\s]+:\d+(?:/|$)').hasMatch(value);
    if (hasScheme && !hasExplicitWebScheme && !looksLikePort) {
      return null;
    }

    final parsedCandidate = Uri.tryParse(
      hasExplicitWebScheme ? value : 'https://$value',
    );
    final candidate = parsedCandidate?.replace(
      scheme: parsedCandidate.scheme.toLowerCase(),
    );
    final looksLikeHost = candidate != null &&
        (candidate.host.contains('.') ||
            candidate.host == 'localhost' ||
            value.startsWith('['));
    if (candidate != null &&
        isWebAddress(candidate) &&
        (hasExplicitWebScheme || looksLikeHost)) {
      return candidate;
    }
    if (hasExplicitWebScheme ||
        hasAuthorityScheme ||
        (hasScheme && !looksLikePort)) {
      return null;
    }
    return search(value);
  }

  static Uri search(String query) => Uri.https(
        _searchHost,
        '/',
        {'q': query.trim()},
      );

  static Uri? command(String input) {
    final value = input.trim();
    final searchMatch = RegExp(
      r'^(?:please\s+)?(?:search(?:\s+(?:the\s+)?web)?(?:\s+for)?|look\s+up|find)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (searchMatch != null) {
      return search(searchMatch.group(1)!);
    }

    final openMatch = RegExp(
      r'^(?:please\s+)?(?:open|go\s+to|visit|navigate\s+to|browse\s+to|take\s+me\s+to)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (openMatch != null) {
      return resolve(openMatch.group(1)!);
    }

    final directAddress = resolve(value);
    if (directAddress != null && directAddress.host != _searchHost) {
      return directAddress;
    }
    return null;
  }

  static bool isWebAddress(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }
}
