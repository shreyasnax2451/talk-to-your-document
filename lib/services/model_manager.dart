import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_config.dart';

enum ModelStatus { notDownloaded, downloading, paused, verifying, ready, failed }

class ModelState {
  final ModelStatus status;
  final double progress; // 0..1, meaningful while downloading
  final String? error;

  const ModelState(this.status, {this.progress = 0, this.error});

  bool get isActive =>
      status == ModelStatus.downloading ||
      status == ModelStatus.paused ||
      status == ModelStatus.verifying;
}

/// Downloads model files with the OS background transfer service
/// (WorkManager / UIDT on Android, background URLSession on iOS), so
/// downloads continue while the app is in the background or closed, and
/// resume after network drops.
///
/// Each model's task ID is its [ModelSpec.id]. Finished files are checked
/// against the published SHA-256 before they are used.
class ModelManager extends ChangeNotifier {
  final Map<String, ModelState> _states = {
    for (final m in ModelConfig.allModels) m.id: const ModelState(ModelStatus.notDownloaded),
  };
  final Map<String, List<Completer<void>>> _waiters = {};
  StreamSubscription<TaskUpdate>? _updates;
  bool _initialized = false;

  ModelState stateOf(ModelSpec model) => _states[model.id]!;
  bool isReady(ModelSpec model) => stateOf(model).status == ModelStatus.ready;

  /// Models currently downloading or being verified.
  List<ModelSpec> get activeDownloads =>
      [for (final m in ModelConfig.allModels) if (stateOf(m).isActive) m];

  /// Models in the current batch of downloads: everything that has been
  /// active since downloads last went idle, including ones already finished,
  /// so overall progress never jumps back when one item completes.
  final Set<String> _batch = {};

  List<ModelSpec> get downloadBatch => [for (final m in ModelConfig.allModels) if (_batch.contains(m.id)) m];

  /// Progress of the whole batch, weighted by file size (0..1).
  double get batchProgress {
    var total = 0.0;
    var done = 0.0;
    for (final m in downloadBatch) {
      final s = stateOf(m);
      total += m.sizeBytes;
      done += m.sizeBytes *
          switch (s.status) {
            ModelStatus.ready || ModelStatus.verifying => 1.0,
            ModelStatus.downloading || ModelStatus.paused => s.progress,
            ModelStatus.notDownloaded || ModelStatus.failed => 0.0,
          };
    }
    return total == 0 ? 0 : done / total;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _init();
    } catch (e) {
      debugPrint('Model manager failed to start: $e');
    }
  }

  Future<void> _init() async {
    await Directory(await ModelSpec.modelsDir()).create(recursive: true);
    // Earlier builds let llamadart fetch models into its own cache; those
    // copies are now unused and can be up to ~2.8 GB.
    final legacyCache = Directory(p.join((await getApplicationCacheDirectory()).path, 'llamadart'));
    if (await legacyCache.exists()) await legacyCache.delete(recursive: true);

    // The listener must be registered before start(), which replays updates
    // for transfers that finished while the app was not running.
    _updates = FileDownloader().updates.listen(handleUpdate);
    FileDownloader().configureNotification(
      running: const TaskNotification('Downloading {displayName}', '{progress} · {networkSpeed}'),
      complete: const TaskNotification('Download complete', '{displayName} is ready'),
      error: const TaskNotification('Download failed', '{displayName}: tap the app to retry'),
      paused: const TaskNotification('Download paused', '{displayName}'),
      progressBar: true,
    );
    // Android: run downloads as a foreground job. Otherwise WorkManager stops
    // a job after ~9 minutes and the downloader pauses and resumes it; for a
    // 2.5 GB model that cycle can end in a restart from 0%, which showed up as
    // a notification jumping back and the app stuck at 100%.
    await FileDownloader().configure(androidConfig: [(Config.runInForeground, Config.always)]);
    await FileDownloader().start();

    for (final model in ModelConfig.allModels) {
      if (stateOf(model).status != ModelStatus.notDownloaded) continue; // set by replay
      final file = File(await model.localPath());
      if (await file.exists() && await file.length() == model.sizeBytes) {
        _set(model, const ModelState(ModelStatus.ready));
        continue;
      }
      final record = await FileDownloader().database.recordForId(model.id);
      if (record != null && !record.status.isFinalState) {
        _set(model, ModelState(
          record.status == TaskStatus.paused ? ModelStatus.paused : ModelStatus.downloading,
          progress: record.progress.clamp(0, 1),
        ));
      }
    }

    // The search model is needed by every feature: fetch it right away.
    final embedding = stateOf(ModelConfig.embedding).status;
    if (embedding == ModelStatus.notDownloaded || embedding == ModelStatus.failed) {
      await download(ModelConfig.embedding);
    }
  }

  /// Starts (or restarts) the background download of [model].
  ///
  /// Never starts a second copy: if the downloader still has a task for the
  /// model (for example after the app was reopened mid-download) it is kept,
  /// and a paused download resumes from its partial file instead of
  /// starting over. Two copies of one download would report alternating
  /// progress.
  Future<void> download(ModelSpec model, {bool wifiOnly = false}) async {
    if (isReady(model) || stateOf(model).isActive) return;
    final record = await FileDownloader().database.recordForId(model.id);
    final progress = (record?.progress ?? 0).clamp(0.0, 1.0);
    if (await FileDownloader().taskForId(model.id) != null) {
      _set(model, ModelState(ModelStatus.downloading, progress: progress));
      return;
    }
    if (record != null && record.status == TaskStatus.paused && record.task is DownloadTask) {
      _set(model, ModelState(ModelStatus.downloading, progress: progress));
      if (await FileDownloader().resume(record.task as DownloadTask)) return;
    }
    final task = DownloadTask(
      taskId: model.id,
      url: model.url,
      filename: model.fileName,
      directory: ModelSpec.directory,
      baseDirectory: BaseDirectory.applicationSupport,
      displayName: model.displayName,
      updates: Updates.statusAndProgress,
      requiresWiFi: wifiOnly,
      retries: 5,
      // Large, user-requested files: resumable across Android's 9-minute
      // worker limit, and UIDT (no time limit) on Android 14+.
      transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
    );
    _set(model, const ModelState(ModelStatus.downloading));
    if (!await FileDownloader().enqueue(task)) {
      _set(model, const ModelState(ModelStatus.failed, error: 'Could not start the download.'));
    }
  }

  Future<void> cancel(ModelSpec model) async {
    await FileDownloader().cancelTaskWithId(model.id);
    _set(model, const ModelState(ModelStatus.notDownloaded));
  }

  /// Deletes a downloaded model to free storage.
  Future<void> delete(ModelSpec model) async {
    if (stateOf(model).isActive) await FileDownloader().cancelTaskWithId(model.id);
    final file = File(await model.localPath());
    if (await file.exists()) await file.delete();
    _set(model, const ModelState(ModelStatus.notDownloaded));
  }

  /// Completes once [model] is downloaded and verified; throws if its
  /// download fails. [onProgress] reports download progress meanwhile.
  Future<void> waitUntilReady(ModelSpec model, {void Function(double progress)? onProgress}) async {
    if (isReady(model)) return;
    if (!stateOf(model).isActive) await download(model);
    final completer = Completer<void>();
    _waiters.putIfAbsent(model.id, () => []).add(completer);
    void listener() => onProgress?.call(stateOf(model).progress);
    addListener(listener);
    try {
      await completer.future;
    } finally {
      removeListener(listener);
    }
  }

  /// Progress drops smaller than this are treated as out-of-order reports.
  static const _maxIgnoredDrop = 0.05;

  /// Applies a status or progress report from the downloader.
  @visibleForTesting
  void handleUpdate(TaskUpdate update) {
    final model = ModelConfig.byId(update.task.taskId);
    if (model == null) return;
    switch (update) {
      case TaskProgressUpdate(:final progress):
        if (progress >= 0 && progress <= 1) {
          // Small drops are out-of-order reports and are ignored, so the bar
          // doesn't flicker. A large drop is a real restart and is shown as
          // it is: hiding it made the app sit at 100% while the download had
          // actually started over.
          final current = stateOf(model);
          final drop = current.progress - progress;
          final shown = current.isActive && drop > 0 && drop < _maxIgnoredDrop ? current.progress : progress;
          if (current.isActive && drop >= _maxIgnoredDrop) {
            debugPrint('${model.id}: download restarted (${current.progress} -> $progress)');
          }
          _set(model, ModelState(ModelStatus.downloading, progress: shown));
        }
      case TaskStatusUpdate(:final status, :final exception):
        switch (status) {
          case TaskStatus.complete:
            _verify(model);
          case TaskStatus.paused:
            _set(model, ModelState(ModelStatus.paused, progress: stateOf(model).progress));
          case TaskStatus.enqueued || TaskStatus.running || TaskStatus.waitingToRetry:
            _set(model, ModelState(ModelStatus.downloading, progress: stateOf(model).progress));
          case TaskStatus.canceled:
            _set(model, const ModelState(ModelStatus.notDownloaded));
          case TaskStatus.notFound || TaskStatus.failed:
            _set(model, ModelState(ModelStatus.failed,
                error: exception?.description ?? 'The download failed.'));
        }
    }
  }

  Future<void> _verify(ModelSpec model) async {
    _set(model, const ModelState(ModelStatus.verifying, progress: 1));
    final path = await model.localPath();
    try {
      // Hashing a multi-GB file takes a while: keep it off the UI isolate.
      final digest = await Isolate.run(() async {
        final output = _DigestSink();
        final input = sha256.startChunkedConversion(output);
        await for (final chunk in File(path).openRead()) {
          input.add(chunk);
        }
        input.close();
        return output.value.toString();
      });
      if (digest == model.sha256) {
        _set(model, const ModelState(ModelStatus.ready));
      } else {
        await File(path).delete();
        _set(model, const ModelState(ModelStatus.failed,
            error: 'The downloaded file was corrupted. Please download again.'));
      }
    } catch (e) {
      _set(model, ModelState(ModelStatus.failed, error: 'Could not verify the download: $e'));
    }
  }

  void _set(ModelSpec model, ModelState state) {
    _states[model.id] = state;
    if (state.isActive) {
      _batch.add(model.id);
    } else if (activeDownloads.isEmpty) {
      _batch.clear();
    }
    if (state.status == ModelStatus.ready || state.status == ModelStatus.failed) {
      for (final waiter in _waiters.remove(model.id) ?? const <Completer<void>>[]) {
        if (state.status == ModelStatus.ready) {
          waiter.complete();
        } else {
          waiter.completeError(Exception('${model.displayName}: ${state.error}'));
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
