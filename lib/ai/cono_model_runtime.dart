import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'cono_model_tier.dart';

abstract interface class ConoModelRuntime {
  Future<bool> hasModel(ConoModelTier tier);

  Future<void> installModel(String sourcePath, ConoModelTier tier);

  Future<String> reply(String conversation, ConoModelTier tier);

  Future<void> close();
}

class LocalConoModelRuntime implements ConoModelRuntime {
  LocalConoModelRuntime({OnnxRuntime? runtime})
      : _runtime = runtime ?? OnnxRuntime();

  static const _contextLength = 256;
  static const _maxNewTokens = 96;
  static const _vocabularySize = 258;
  static const _spaceToken = 32;
  static const _bosToken = 256;
  static const _eosToken = 257;

  final OnnxRuntime _runtime;
  final math.Random _random = math.Random();
  late final Future<Set<String>> _bundledAssets =
      AssetManifest.loadFromAssetBundle(rootBundle)
          .then((manifest) => manifest.listAssets().toSet());
  OrtSession? _activeSession;
  ConoModelTier? _activeTier;

  @override
  Future<bool> hasModel(ConoModelTier tier) async {
    if (await (await _modelFile(tier)).exists()) {
      return true;
    }
    return (await _bundledAssets).contains(tier.bundledAssetPath);
  }

  @override
  Future<void> installModel(String sourcePath, ConoModelTier tier) async {
    final source = File(sourcePath);
    if (!await source.exists() ||
        !source.path.toLowerCase().endsWith('.onnx')) {
      throw const FormatException('Choose a Cono Nova ONNX model file.');
    }

    final destination = await _modelFile(tier);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.importing');

    try {
      await source.copy(temporary.path);
      final candidate = await _createSession(tier, modelFile: temporary);
      await candidate.close();
      if (_activeTier == tier) {
        await close();
      }
      if (await destination.exists()) {
        await destination.delete();
      }
      await temporary.rename(destination.path);
    } on Object {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  @override
  Future<String> reply(String conversation, ConoModelTier tier) async {
    if (conversation.trim().isEmpty) {
      throw ArgumentError.value(
        conversation,
        'conversation',
        'Conversation cannot be empty.',
      );
    }
    final session = await _sessionFor(tier);
    final tokens = _promptTokens(conversation);
    final generated = <int>[];

    for (var index = 0; index < _maxNewTokens; index++) {
      final input = await OrtValue.fromList(
        Int64List.fromList(tokens),
        [1, tokens.length],
      );
      Map<String, OrtValue>? outputs;
      try {
        outputs = await session.run({'token_ids': input});
        final logits = await outputs['logits']?.asFlattenedList();
        if (logits == null || logits.length < _vocabularySize) {
          throw StateError('Cono Nova returned an invalid logits tensor.');
        }
        final nextToken = _sampleToken(
          logits,
          tokens.length - 1,
          _vocabularySize,
        );
        if (nextToken == _eosToken) {
          break;
        }
        if (nextToken < _bosToken) {
          generated.add(nextToken);
        }
        tokens.add(nextToken);
        if (tokens.length > _contextLength) {
          tokens.removeAt(1);
        }
      } finally {
        await input.dispose();
        if (outputs != null) {
          for (final output in outputs.values) {
            await output.dispose();
          }
        }
      }
    }

    final response = utf8.decode(generated, allowMalformed: true);
    final nextTurn = response.indexOf(RegExp(r'\n(?:User|Cono Nova):'));
    final answer =
        (nextTurn < 0 ? response : response.substring(0, nextTurn)).trim();
    if (answer.isEmpty) {
      throw StateError('Cono Nova did not generate a response.');
    }
    return answer;
  }

  @override
  Future<void> close() async {
    await _activeSession?.close();
    _activeSession = null;
    _activeTier = null;
  }

  Future<OrtSession> _sessionFor(ConoModelTier tier) async {
    if (_activeTier == tier && _activeSession != null) {
      return _activeSession!;
    }
    await _activeSession?.close();
    _activeSession = null;
    _activeTier = null;

    final session = await _createSession(
      tier,
      modelFile: await _modelFile(tier),
    );
    _activeSession = session;
    _activeTier = tier;
    return session;
  }

  Future<OrtSession> _createSession(
    ConoModelTier tier, {
    File? modelFile,
  }) async {
    final installedModel = modelFile;
    final options = OrtSessionOptions(
      intraOpNumThreads: 2,
      interOpNumThreads: 1,
      providers: [OrtProvider.CPU],
    );
    final session = installedModel != null && await installedModel.exists()
        ? await _runtime.createSession(
            installedModel.path,
            options: options,
          )
        : await _runtime.createSessionFromAsset(
            tier.bundledAssetPath,
            options: options,
          );
    try {
      if (!session.inputNames.contains('token_ids') ||
          !session.outputNames.contains('logits')) {
        throw const FormatException('This is not a Cono Nova model package.');
      }
      final metadata = await session.getMetadata();
      if (metadata.customMetadataMap['cono.model_name'] !=
              ConoModelTier.modelName ||
          metadata.customMetadataMap['cono.model_preset'] !=
              tier.trainingPreset ||
          metadata.customMetadataMap['cono.context_length'] !=
              '$_contextLength' ||
          metadata.customMetadataMap['cono.tokenizer'] != 'utf-8-bytes-v1') {
        throw const FormatException('This is not a Cono Nova model package.');
      }
      return session;
    } on Object {
      await session.close();
      rethrow;
    }
  }

  Future<File> _modelFile(ConoModelTier tier) async {
    final directory = await getApplicationSupportDirectory();
    final filename = 'cono-nova-${tier.trainingPreset}.onnx';
    return File(
      '${directory.path}${Platform.pathSeparator}models'
      '${Platform.pathSeparator}$filename',
    );
  }

  List<int> _promptTokens(String conversation) {
    final suffix = utf8.encode('\nCono Nova:');
    final promptBytes = utf8.encode(conversation);
    final promptLimit = _contextLength - _maxNewTokens - suffix.length - 1;
    final clippedPrompt = promptBytes.length > promptLimit
        ? promptBytes.sublist(promptBytes.length - promptLimit)
        : promptBytes;
    final paddingLength =
        _contextLength - clippedPrompt.length - suffix.length - 1;
    return [
      _bosToken,
      ...List<int>.filled(paddingLength, _spaceToken),
      ...clippedPrompt,
      ...suffix,
    ];
  }

  int _sampleToken(List<dynamic> logits, int position, int vocabularySize) {
    final start = position * vocabularySize;
    final candidates = List<int>.generate(vocabularySize, (index) => index)
      ..sort(
        (left, right) => (logits[start + right] as num)
            .compareTo(logits[start + left] as num),
      );
    final topCandidates = candidates.take(8).toList();
    final maximum = logits[start + topCandidates.first] as num;
    final weights = topCandidates
        .map(
          (token) => math.exp(
            ((logits[start + token] as num) - maximum) / 0.8,
          ),
        )
        .toList();
    final total = weights.fold<double>(0, (sum, weight) => sum + weight);
    var choice = _random.nextDouble() * total;
    for (var index = 0; index < topCandidates.length; index++) {
      choice -= weights[index];
      if (choice <= 0) {
        return topCandidates[index];
      }
    }
    return topCandidates.first;
  }
}
