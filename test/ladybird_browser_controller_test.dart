import 'package:cono_os/applications/ladybird_browser_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves addresses and search phrases', () {
    expect(
      LadybirdAddress.resolve('example.com/path'),
      Uri.parse('https://example.com/path'),
    );
    expect(
      LadybirdAddress.resolve('HTTPS://example.com'),
      Uri.parse('https://example.com'),
    );
    expect(
      LadybirdAddress.resolve('cats')?.queryParameters['q'],
      'cats',
    );
    expect(
      LadybirdAddress.resolve('cats and dogs')?.host,
      'duckduckgo.com',
    );
    expect(
      LadybirdAddress.resolve('cats and dogs')?.queryParameters['q'],
      'cats and dogs',
    );
    expect(LadybirdAddress.resolve('javascript:alert(1)'), isNull);
  });

  test('recognizes explicit assistant navigation commands', () {
    expect(
      LadybirdAddress.command('example.com'),
      Uri.parse('https://example.com'),
    );
    expect(
      LadybirdAddress.command('Please go to example.com'),
      Uri.parse('https://example.com'),
    );
    expect(
      LadybirdAddress.command('search the web for ConoOS'),
      Uri.https('duckduckgo.com', '/', {'q': 'ConoOS'}),
    );
    expect(LadybirdAddress.command('what is ConoOS?'), isNull);
  });

  test('browser controller accepts only web URLs', () {
    final controller = LadybirdBrowserController();
    addTearDown(controller.dispose);
    final uri = Uri.parse('https://example.com');

    controller.navigate(uri);

    expect(controller.currentUri, uri);
    expect(controller.navigationRevision, 1);
    expect(
      () => controller.navigate(Uri.parse('javascript:alert(1)')),
      throwsArgumentError,
    );
  });
}
