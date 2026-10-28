import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Indexing progress in the notification shade.
///
/// Android: while documents are being indexed the app runs a foreground
/// service whose notification shows a progress bar. The service also keeps
/// the app alive, so indexing continues after the user leaves the app.
///
/// iOS has no progress notifications; a "ready" notification is posted when
/// indexing finishes while the app is in the background.
///
/// Model download notifications are posted by background_downloader.
class IndexingNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _serviceRunning = false;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  static const _progressId = 7101;
  static const _doneId = 7102;

  static const _doneChannel = AndroidNotificationDetails(
    'indexing_done',
    'Indexing complete',
    channelDescription: 'Tells you when your PDFs are ready to chat with',
    importance: Importance.defaultImportance,
  );

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is requested on the model screen, not at startup.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Shows (or updates) the progress notification for the running job.
  Future<void> progress({required String docName, required double progress, int queued = 0}) async {
    if (!_initialized || !Platform.isAndroid) return;
    final percent = (progress * 100).clamp(0, 100).round();
    final body = queued > 0 ? '$percent% · $queued more queued' : '$percent%';
    final details = AndroidNotificationDetails(
      'indexing_progress',
      'Indexing progress',
      channelDescription: 'Shows progress while PDFs are being indexed',
      importance: Importance.low, // silent, no heads-up
      priority: Priority.low,
      onlyAlertOnce: true,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: percent,
    );
    try {
      if (!_serviceRunning) {
        _serviceRunning = true;
        await _android?.startForegroundService(
          id: _progressId,
          title: 'Indexing $docName',
          body: body,
          notificationDetails: details,
          foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
        );
        return;
      }
      // Android drops notification updates sent faster than ~5 per second.
      final now = DateTime.now();
      if (percent < 100 && now.difference(_lastUpdate).inMilliseconds < 700) return;
      _lastUpdate = now;
      await _plugin.show(
        id: _progressId,
        title: 'Indexing $docName',
        body: body,
        notificationDetails: NotificationDetails(android: details),
      );
    } catch (e) {
      debugPrint('Indexing notification failed: $e');
    }
  }

  /// Removes the progress notification once the queue is empty and, if the
  /// app is not on screen, says how indexing went.
  Future<void> finished({required int ready, required int failed}) async {
    if (!_initialized) return;
    try {
      if (_serviceRunning) {
        _serviceRunning = false;
        await _android?.stopForegroundService();
        await _plugin.cancel(id: _progressId);
      }
      final inForeground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (inForeground || ready + failed == 0) return;
      final title = failed == 0
          ? (ready == 1 ? 'Your document is ready' : '$ready documents are ready')
          : '$failed document${failed == 1 ? '' : 's'} could not be indexed';
      await _plugin.show(
        id: _doneId,
        title: title,
        body: failed == 0 ? 'Ask questions about it in DocChat.' : 'Open DocChat to retry.',
        notificationDetails: const NotificationDetails(
          android: _doneChannel,
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Indexing notification failed: $e');
    }
  }
}
