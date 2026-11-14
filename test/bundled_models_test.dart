import 'package:cono_os/ai/cono_model_tier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every Cono Nova tier is packaged as an app asset', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final bundledAssets = manifest.listAssets().toSet();

    for (final tier in ConoModelTier.values) {
      expect(bundledAssets, contains(tier.bundledAssetPath));
    }
  });
}
