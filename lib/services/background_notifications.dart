import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications for work that should finish even if the user leaves the app:
/// indexing PDFs and writing an answer.
///
/// Android: while either is running, the app runs one foreground service
/// whose notification shows indexing progress (or "Writing an answer…"). The
/// service keeps the app alive in the background and stops when both are done.
///
/// iOS has no foreground services or progress notifications; a notification
/// is posted when indexing finishes while the app is in the background.
/// (Answers are stopped on iOS when the app is backgrounded.)
///
/// Model download notifications are posted by background_downloader.
class BackgroundNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _serviceRunning = false;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // Current work shown in the ongoing notification.
  ({String docName, int percent, int queued})? _indexing;
  bool _answering = false;

  static const _ongoingId = 7101;
  static const _indexingDoneId = 7102;
  static const _answerReadyId = 7103;

  static const _resultChannel = AndroidNotificationDetails(
    'work_done',
    'Documents and answers ready',
    channelDescription: 'Tells you when your PDFs are indexed or an answer is ready',
    importance: Importance.defaultImportance,
  );

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is requested on the download screen, not at startup.
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

  static bool get _inForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> indexingProgress({required String docName, required double progress, int queued = 0}) {
    final percent = (progress * 100).clamp(0, 100).round();
    final changedDoc = _indexing?.docName != docName;
    _indexing = (docName: docName, percent: percent, queued: queued);
    return _render(force: changedDoc || percent == 100);
  }

  /// Called when the indexing queue is empty; reports the result if the app
  /// is not on screen.
  Future<void> indexingFinished({required int ready, required int failed}) async {
    _indexing = null;
    await _render(force: true);
    if (!_initialized || _inForeground || ready + failed == 0) return;
    final title = failed == 0
        ? (ready == 1 ? 'Your document is ready' : '$ready documents are ready')
        : '$failed document${failed == 1 ? '' : 's'} could not be indexed';
    await _post(_indexingDoneId, title,
        failed == 0 ? 'Ask questions about it in DocChat.' : 'Open DocChat to retry.');
  }

  Future<void> answeringStarted() {
    _answering = true;
    return _render(force: true);
  }

  /// [answer] is the finished reply (null if it was stopped); a notification
  /// with its start is posted when [notify] is true.
  Future<void> answeringFinished({String? answer, required bool notify}) async {
    _answering = false;
    await _render(force: true);
    if (!_initialized || !notify || answer == null) return;
    final preview = answer.replaceAll(RegExp(r'\s*\[p\. \d+\]'), '').replaceAll('\n', ' ');
    await _post(_answerReadyId, 'Your answer is ready',
        preview.length > 140 ? '${preview.substring(0, 137)}…' : preview);
  }

  /// Shows, updates or removes the ongoing Android notification.
  Future<void> _render({bool force = false}) async {
    if (!_initialized || !Platform.isAndroid) return;
    final indexing = _indexing;
    try {
      if (indexing == null && !_answering) {
        if (_serviceRunning) {
          _serviceRunning = false;
          await _android?.stopForegroundService();
          await _plugin.cancel(id: _ongoingId);
        }
        return;
      }
      // Android drops notification updates sent faster than ~5 per second.
      final now = DateTime.now();
      if (_serviceRunning && !force && now.difference(_lastUpdate).inMilliseconds < 700) return;
      _lastUpdate = now;

      final String title;
      final String body;
      if (indexing != null) {
        title = 'Indexing ${indexing.docName}';
        body = [
          '${indexing.percent}%',
          if (indexing.queued > 0) '${indexing.queued} more queued',
          if (_answering) 'writing an answer',
        ].join(' · ');
      } else {
        title = 'Writing an answer…';
        body = 'DocChat is answering your question';
      }
      final details = AndroidNotificationDetails(
        'background_work',
        'Indexing and answering',
        channelDescription: 'Shows progress while PDFs are indexed or an answer is written',
        importance: Importance.low, // silent, no heads-up
        priority: Priority.low,
        onlyAlertOnce: true,
        ongoing: true,
        autoCancel: false,
        showProgress: true,
        maxProgress: 100,
        progress: indexing?.percent ?? 0,
        indeterminate: indexing == null,
      );

      if (!_serviceRunning) {
        _serviceRunning = true;
        await _android?.startForegroundService(
          id: _ongoingId,
          title: title,
          body: body,
          notificationDetails: details,
          foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
        );
      } else {
        await _plugin.show(
          id: _ongoingId,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(android: details),
        );
      }
    } catch (e) {
      debugPrint('Background notification failed: $e');
    }
  }

  Future<void> _post(int id, String title, String body) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: _resultChannel,
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }
}
