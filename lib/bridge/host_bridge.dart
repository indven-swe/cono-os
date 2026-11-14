import 'package:url_launcher/url_launcher.dart';

class HostBridge {
  static const _blockedSchemes = {
    'http',
    'file',
    'content',
    'data',
    'javascript',
    'intent',
    'vbscript',
  };

  static bool supportsUri(Uri uri) {
    if (!uri.hasScheme || _blockedSchemes.contains(uri.scheme)) {
      return false;
    }
    if (uri.scheme == 'https') {
      return uri.host.isNotEmpty && uri.userInfo.isEmpty;
    }
    if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
      return uri.path.isNotEmpty;
    }
    return RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(uri.scheme);
  }

  Future<bool> launchExternalUri(Uri uri) {
    if (!supportsUri(uri)) {
      throw ArgumentError.value(uri, 'uri', 'This link type is not allowed.');
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> openWebLink(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Only HTTPS links are allowed.');
    }

    return launchExternalUri(uri);
  }
}
