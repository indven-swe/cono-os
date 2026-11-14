enum ConoModelTier {
  phone('Phone', '25.5M', 200, 'phone-25m'),
  balanced('Balanced', '38.1M', 150, 'balanced-38m'),
  large('Large', '85.5M', 100, 'large-85m');

  const ConoModelTier(
    this.label,
    this.parameterLabel,
    this.dailyRequestLimit,
    this.trainingPreset,
  );

  static const modelName = 'Cono Nova';

  final String label;
  final String parameterLabel;
  final int dailyRequestLimit;
  final String trainingPreset;

  String get bundledAssetPath => 'assets/models/cono-nova-$trainingPreset.onnx';
}
