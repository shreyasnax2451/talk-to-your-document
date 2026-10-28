import 'package:background_downloader/background_downloader.dart';
import 'package:docchat/services/model_config.dart';
import 'package:docchat/services/model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadTask taskFor(ModelSpec m) => DownloadTask(taskId: m.id, url: m.url, filename: m.fileName);

void progress(ModelManager models, ModelSpec m, double p) =>
    models.handleUpdate(TaskProgressUpdate(taskFor(m), p));

void status(ModelManager models, ModelSpec m, TaskStatus s) =>
    models.handleUpdate(TaskStatusUpdate(taskFor(m), s));

void main() {
  const pack = ModelConfig.embedding;
  const model = ModelConfig.qwen3_4b;

  test('progress for a running download never goes backwards', () {
    final models = ModelManager();
    progress(models, model, 0.9);
    progress(models, model, 0.25); // stale or duplicate report
    expect(models.stateOf(model).progress, 0.9);
    progress(models, model, 0.95);
    expect(models.stateOf(model).progress, 0.95);
  });

  test('a fresh download after a failure starts again from zero', () {
    final models = ModelManager();
    progress(models, model, 0.9);
    status(models, model, TaskStatus.failed);
    expect(models.stateOf(model).status, ModelStatus.failed);
    progress(models, model, 0.1);
    expect(models.stateOf(model).progress, 0.1);
  });

  test('pausing keeps the progress', () {
    final models = ModelManager();
    progress(models, model, 0.6);
    status(models, model, TaskStatus.paused);
    expect(models.stateOf(model).status, ModelStatus.paused);
    expect(models.stateOf(model).progress, 0.6);
    status(models, model, TaskStatus.running);
    expect(models.stateOf(model).progress, 0.6);
  });

  test('banner progress combines all downloads, weighted by size', () {
    final models = ModelManager();
    progress(models, pack, 0.9);
    progress(models, model, 0.25);
    final expected = (pack.sizeBytes * 0.9 + model.sizeBytes * 0.25) / (pack.sizeBytes + model.sizeBytes);
    expect(models.batchProgress, closeTo(expected, 1e-9));
    expect(models.downloadBatch, [pack, model]);
  });

  test('a cancelled item leaves the batch only once everything is idle', () {
    final models = ModelManager();
    progress(models, pack, 0.5);
    progress(models, model, 0.5);
    status(models, pack, TaskStatus.canceled);
    expect(models.downloadBatch, [pack, model]); // still one batch while the model downloads
    status(models, model, TaskStatus.canceled);
    expect(models.downloadBatch, isEmpty);
    expect(models.batchProgress, 0);
  });
}
