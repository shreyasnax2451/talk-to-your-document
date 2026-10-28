import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A GGUF model the app runs on-device.
///
/// Until the custom model download (manifest + CDN) is built, a model is
/// resolved from `<app support dir>/models/<fileName>` if the file was placed
/// there manually, and otherwise from [huggingFaceUri] through llamadart's
/// built-in download cache.
class ModelSpec {
  final String id;
  final String fileName;
  final String huggingFaceUri;

  const ModelSpec({
    required this.id,
    required this.fileName,
    required this.huggingFaceUri,
  });

  Future<ModelSource> resolveSource() async {
    final supportDir = await getApplicationSupportDirectory();
    final localFile = File(p.join(supportDir.path, 'models', fileName));
    if (await localFile.exists()) {
      return ModelSource.path(localFile.path);
    }
    return ModelSource.parse(huggingFaceUri);
  }
}

/// Fixed model choices (the "Pro" tier from the architecture guide).
class ModelConfig {
  ModelConfig._();

  /// Answering model: Qwen3-4B at Q4_K_M (~2.5 GB, ~3.2 GB RAM while running).
  static const answering = ModelSpec(
    id: 'qwen3-4b-q4_k_m',
    fileName: 'Qwen3-4B-Q4_K_M.gguf',
    huggingFaceUri: 'hf://Qwen/Qwen3-4B-GGUF/Qwen3-4B-Q4_K_M.gguf',
  );

  /// 4K context with an 8-bit KV cache keeps the prompt (4-5 chunks plus the
  /// question) in budget while halving cache memory.
  static const answeringParams = ModelParams(
    contextSize: 4096,
    cacheTypeK: KvCacheType.q8_0,
    cacheTypeV: KvCacheType.q8_0,
  );

  /// Embedding model: EmbeddingGemma-300M at Q8_0 (~320 MB), 768-dim vectors.
  ///
  /// Changing this model (or [embeddingDimensions]) invalidates every stored
  /// vector: all documents must be re-indexed.
  static const embedding = ModelSpec(
    id: 'embeddinggemma-300m-q8_0',
    fileName: 'embeddinggemma-300M-Q8_0.gguf',
    huggingFaceUri:
        'hf://ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf',
  );

  static const embeddingDimensions = 768;

  /// EmbeddingGemma embeds each input in a single micro-batch, so batch and
  /// micro-batch must cover the longest chunk (chunks target ~400 tokens).
  static const embeddingParams = ModelParams(
    contextSize: 2048,
    batchSize: 2048,
    microBatchSize: 2048,
    maxParallelSequences: 4,
  );

  /// Upper bound on tokens per embedded chunk, including the title prefix.
  static const embeddingMaxInputTokens = 1024;
}
