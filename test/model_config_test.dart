import 'package:docchat/services/model_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('8 GB phones (which report ~7.2-7.6 GB) get Qwen3-4B', () {
    expect(ModelConfig.recommendedFor(7.3), ModelConfig.qwen3_4b);
    expect(ModelConfig.recommendedFor(11.5), ModelConfig.qwen3_4b);
  });

  test('6 GB and smaller phones get Qwen3-1.7B', () {
    expect(ModelConfig.recommendedFor(5.6), ModelConfig.qwen3_1_7b);
    expect(ModelConfig.recommendedFor(3.7), ModelConfig.qwen3_1_7b);
  });

  test('unknown RAM falls back to the smaller model', () {
    expect(ModelConfig.recommendedFor(null), ModelConfig.qwen3_1_7b);
  });

  test('model IDs and file names are unique', () {
    final ids = ModelConfig.allModels.map((m) => m.id).toSet();
    final files = ModelConfig.allModels.map((m) => m.fileName).toSet();
    expect(ids.length, ModelConfig.allModels.length);
    expect(files.length, ModelConfig.allModels.length);
  });
}
