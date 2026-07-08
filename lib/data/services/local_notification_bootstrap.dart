import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../di/injection.dart';
import '../../playback/headless_session_bootstrap.dart';
import '../../ui/navigation/app_router.dart';
import 'seerr/seerr_http_client.dart';
import 'seerr/seerr_models.dart';

/// iOS category tying the approve/decline buttons to request notifications.
const String seerrRequestCategoryId = 'seerr_request';

/// Action ids shared with the plugin's push payloads.
const String seerrApproveActionId = 'approve';
const String seerrDeclineActionId = 'decline';

/// Notification tapped or actioned while the app is backgrounded/terminated.
/// Runs in its own isolate, so it re-resolves everything it needs.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  _handleNotificationResponse(response);
}

/// Routes a notification response: an approve/decline action runs the silent
/// request flow, anything else navigates to the payload's route.
void _handleNotificationResponse(NotificationResponse response) {
  final actionId = response.actionId;
  if (actionId == seerrApproveActionId || actionId == seerrDeclineActionId) {
    final requestId = _requestIdFromPayload(response.payload);
    if (requestId != null) {
      unawaited(_runRequestAction(
        approve: actionId == seerrApproveActionId,
        requestId: requestId,
        notificationId: response.id,
      ));
      return;
    }
  }
  _navigate(_routeFromPayload(response.payload));
}

/// Reads the route from a payload that may be a JSON map or a bare route
/// string. Non-request notifications keep sending the raw route.
String? _routeFromPayload(String? payload) {
  if (payload == null || payload.trim().isEmpty) return null;
  final raw = payload.trim();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['route'] is String) {
      return (decoded['route'] as String).trim();
    }
  } catch (_) {}
  return raw;
}

String? _requestIdFromPayload(String? payload) {
  if (payload == null || payload.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(payload.trim());
    if (decoded is Map && decoded['requestId'] is String) {
      final id = (decoded['requestId'] as String).trim();
      return id.isNotEmpty ? id : null;
    }
  } catch (_) {}
  return null;
}

void _navigate(String? route) {
  if (route == null || route.trim().isEmpty) return;
  appRouter.go(route.trim());
}

/// Approves or declines a request without any UI. Restores the saved session
/// headlessly, calls the proxy endpoint, and cleans up the notification.
Future<void> _runRequestAction({
  required bool approve,
  required String requestId,
  required int? notificationId,
}) async {
  final parsedId = int.tryParse(requestId);
  if (parsedId == null) return;

  SeerrHttpClient? seerr;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await configureBackgroundDependencies();

    final client = await HeadlessSessionBootstrap().restoreClient();
    final token = client?.accessToken;
    if (client == null || token == null || token.isEmpty) {
      throw StateError('no session');
    }

    seerr = SeerrHttpClient(
      proxyConfig: MoonfinProxyConfig(
        jellyfinBaseUrl: client.baseUrl,
        jellyfinToken: token,
      ),
    );

    if (approve) {
      await seerr.approveRequest(parsedId);
    } else {
      await seerr.declineRequest(parsedId);
    }

    if (notificationId != null) {
      await LocalNotificationBootstrap.instance.plugin.cancel(
        id: notificationId,
      );
    }
  } catch (_) {
    // Surface the failure so the tap isn't silently lost.
    try {
      await LocalNotificationBootstrap.instance.initialize();
      await LocalNotificationBootstrap.instance.plugin.show(
        id: requestId.hashCode ^ 0x5eec,
        title: 'Request',
        body: approve ? "Couldn't approve" : "Couldn't deny",
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'seerr_notifications',
            'Requests',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (_) {}
  } finally {
    seerr?.close();
  }
}

class LocalNotificationBootstrap {
  LocalNotificationBootstrap._();

  static final LocalNotificationBootstrap instance =
      LocalNotificationBootstrap._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    // The request category adds Approve/Deny buttons. Leaving the action
    // options empty (no `foreground`) lets iOS run them without opening the app.
    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          seerrRequestCategoryId,
          actions: [
            DarwinNotificationAction.plain(seerrApproveActionId, 'Approve'),
            DarwinNotificationAction.plain(seerrDeclineActionId, 'Deny'),
          ],
          options: {
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
      ],
    );
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open');

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    _initialized = true;
  }

  Future<String?> getLaunchRoute() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return _routeFromPayload(details?.notificationResponse?.payload);
  }
}
