import 'package:cono_os/bridge/host_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows HTTPS and user-registered app schemes', () {
    expect(HostBridge.supportsUri(Uri.parse('https://example.com')), isTrue);
    expect(HostBridge.supportsUri(Uri.parse('mapsapp://place/1')), isTrue);
  });

  test('rejects unsafe or incomplete URIs', () {
    expect(HostBridge.supportsUri(Uri(scheme: 'https')), isFalse);
    expect(HostBridge.supportsUri(Uri.parse('http://example.com')), isFalse);
    expect(HostBridge.supportsUri(Uri.parse('file:///private/data')), isFalse);
    expect(HostBridge.supportsUri(Uri.parse('javascript:alert(1)')), isFalse);
  });
}
