import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A GGUF model file the app downloads once and runs on-device.
class ModelSpec {
  final String id;

  /// User-facing name used in sentences, banners and notifications. Model
  /// names (Qwen, EmbeddingGemma) are not shown to users.
  final String displayName;

  /// Short label for the model's card on the selection screen.
  final String title;

  final String description;
  final String fileName;
  final String url;
  final int sizeBytes;
  final String sha256;

  /// Phone RAM (GB) this model is recommended from; 0 for the search model.
  final int recommendedMinRamGb;

  final ModelParams params;

  const ModelSpec({
    required this.id,
    required this.displayName,
    required this.title,
    required this.description,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.params,
    this.recommendedMinRamGb = 0,
  });

  /// Folder under the app support directory that holds all model files.
  static const directory = 'models';

  static Future<String> modelsDir() async =>
      p.join((await getApplicationSupportDirectory()).path, directory);

  Future<String> localPath() async => p.join(await modelsDir(), fileName);

  /// The downloaded file. Throws [ModelNotReadyException] if the model has not
  /// been downloaded yet; downloads go through [ModelManager] only.
  Future<ModelSource> resolveSource() async {
    final path = await localPath();
    if (!await File(path).exists()) throw ModelNotReadyException(this);
    return ModelSource.path(path);
  }

  String get sizeLabel => sizeBytes >= 1e9
      ? '${(sizeBytes / 1e9).toStringAsFixed(1)} GB'
      : '${(sizeBytes / 1e6).round()} MB';
}

class ModelNotReadyException implements Exception {
  final ModelSpec model;
  ModelNotReadyException(this.model);

  @override
  String toString() => '${model.displayName} has not been downloaded yet.';
}

/// Model choices, following the device tiers in the architecture guide.
class ModelConfig {
  ModelConfig._();

  /// 4K context with an 8-bit KV cache keeps the prompt (4-5 chunks plus the
  /// question) in budget while halving cache memory.
  static const _answeringParams = ModelParams(
    contextSize: 4096,
    cacheTypeK: KvCacheType.q8_0,
    cacheTypeV: KvCacheType.q8_0,
  );

  /// Qwen3-4B at Q4_K_M: best on-phone accuracy, for 8 GB+ phones.
  static const qwen3_4b = ModelSpec(
    id: 'qwen3-4b-q4_k_m',
    displayName: 'High accuracy model',
    title: 'High accuracy',
    description: 'Best accuracy for multi-section and numeric questions. '
        'Needs about 3.4 GB of free RAM while answering.',
    fileName: 'Qwen3-4B-Q4_K_M.gguf',
    url: 'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
    sizeBytes: 2497280256,
    sha256: '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5',
    recommendedMinRamGb: 8,
    params: _answeringParams,
  );

  /// Qwen3-1.7B at Q5_K_M (small models lose more to 4-bit quantization):
  /// the default for 6 GB phones.
  static const qwen3_1_7b = ModelSpec(
    id: 'qwen3-1.7b-q5_k_m',
    displayName: 'Basic model',
    title: 'Basic',
    description: 'Faster and smaller. Good for lookups; weaker on questions '
        'that span sections. Needs about 2 GB of free RAM while answering.',
    fileName: 'Qwen3-1.7B-Q5_K_M.gguf',
    url: 'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q5_K_M.gguf',
    sizeBytes: 1257880128,
    sha256: 'b0949de5b2e06cbed6aa96517f9bd8afb334584b6f95ee83479292ff4bdd8ed3',
    recommendedMinRamGb: 6,
    params: _answeringParams,
  );

  /// Answering models the user can choose from, largest first.
  static const answeringModels = [qwen3_4b, qwen3_1_7b];

  static ModelSpec? answeringModelById(String? id) =>
      answeringModels.where((m) => m.id == id).firstOrNull;

  /// Embedding model: EmbeddingGemma-300M at Q8_0, 768-dim vectors. Always
  /// downloaded, whichever answering model is chosen.
  ///
  /// Changing this model (or [embeddingDimensions]) invalidates every stored
  /// vector: all documents must be re-indexed.
  static const embedding = ModelSpec(
    id: 'embeddinggemma-300m-q8_0',
    displayName: 'Default resources pack',
    title: 'Default resources pack',
    description: 'Reads and indexes your PDFs and finds the passages that answer '
        'a question. Required for every answering model.',
    fileName: 'embeddinggemma-300M-Q8_0.gguf',
    url: 'https://huggingface.co/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf',
    sizeBytes: 333590944,
    sha256: 'b5ce9d77a3fc4b3b39ccb5643c36777911cc4eb46a66962eadfa3f5f60490d63',
    // EmbeddingGemma embeds each input in a single micro-batch, so batch and
    // micro-batch must cover the longest chunk (chunks target ~400 tokens).
    params: ModelParams(
      contextSize: 2048,
      batchSize: 2048,
      microBatchSize: 2048,
      maxParallelSequences: 4,
    ),
  );

  static const embeddingDimensions = 768;

  /// Upper bound on tokens per embedded chunk, including the title prefix.
  static const embeddingMaxInputTokens = 1024;

  static const allModels = [embedding, qwen3_4b, qwen3_1_7b];

  static ModelSpec? byId(String id) => allModels.where((m) => m.id == id).firstOrNull;

  /// Total phone RAM in GB, or null where it cannot be read.
  static Future<double?> deviceRamGb() async {
    try {
      final info = DeviceInfoPlugin();
      final int mb;
      if (Platform.isAndroid) {
        mb = (await info.androidInfo).physicalRamSize;
      } else if (Platform.isIOS) {
        mb = (await info.iosInfo).physicalRamSize;
      } else {
        return null;
      }
      return mb / 1024;
    } catch (_) {
      return null;
    }
  }

  /// Qwen3-4B on 8 GB+ phones, Qwen3-1.7B otherwise.
  ///
  /// Phones report somewhat less than their marketed RAM (an "8 GB" phone
  /// shows ~7.2-7.6 GB), so the threshold sits below the nominal size.
  static ModelSpec recommendedFor(double? ramGb) {
    if (ramGb == null) return qwen3_1_7b;
    return ramGb >= qwen3_4b.recommendedMinRamGb - 1 ? qwen3_4b : qwen3_1_7b;
  }
}
