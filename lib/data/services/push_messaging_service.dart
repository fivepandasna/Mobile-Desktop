import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../firebase_options.dart';
import '../../ui/navigation/app_router.dart';
import '../../util/platform_detection.dart';
import 'plugin_sync_service.dart';
import 'seerr_notification_service.dart';

/// Background/terminated messages that carry a notification block are drawn by
/// the OS. The one exception is the Android data-only request push, which has
/// no notification block, so this handler renders the actioned local
/// notification itself. Everything else stays a no-op.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  if (message.data['kind'] != 'request') return;

  final data = message.data;
  final route = data['route'];
  if (route is! String || route.trim().isEmpty) return;
  final requestId = data['requestId'];

  try {
    WidgetsFlutterBinding.ensureInitialized();
    final service = SeerrNotificationService();
    await service.initialize();
    service.show(
      data['title'] is String ? data['title'] as String : '',
      data['body'] is String ? data['body'] as String : '',
      route.trim(),
      requestId: requestId is String ? requestId : null,
      isRequest: true,
    );
  } catch (_) {}
}

/// Client side of the push notification path. The plugin sends FCM messages
/// carrying both a notification block (title/body) and a data route, so the OS
/// renders background/terminated notifications and this service only handles
/// token registration and taps. Foreground messages are ignored because the
/// SSE settings stream already shows the in-app notification.
class PushMessagingService {
  bool _initialized = false;
  String? _lastRegisteredToken;

  Future<void> initialize() async {
    if (!PlatformDetection.isMobile) return;
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp(
        options: PlatformDetection.isAndroid
            ? null
            : DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      // A duplicate-app error means Firebase was already initialized earlier in
      // startup, which is fine; anything else aborts push setup.
      if (e.code != 'duplicate-app') {
        _initialized = false;
        return;
      }
    } catch (_) {
      _initialized = false;
      return;
    }

    final messaging = FirebaseMessaging.instance;

    try {
      await messaging.requestPermission();
    } catch (_) {}

    // On iOS the APNs token must be present before FCM will hand out a token.
    if (PlatformDetection.isIOS) {
      try {
        await messaging.getAPNSToken();
      } catch (_) {}
    }

    try {
      final token = await messaging.getToken();
      await _registerToken(token);
    } catch (_) {}

    messaging.onTokenRefresh.listen((token) {
      _registerToken(token);
    });

    // Foreground is handled by the SSE stream, so FCM onMessage is a no-op here
    // to avoid drawing the notification twice.
    FirebaseMessaging.onMessage.listen((_) {});

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _navigateFromMessage(message);
    });

    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _navigateFromMessage(initial);
      }
    } catch (_) {}
  }

  /// Re-registers the current FCM token after login. Startup registration bails
  /// before a session exists, so this is called once the client is authenticated.
  Future<void> registerWithCurrentToken() async {
    if (!PlatformDetection.isMobile) return;
    if (!_initialized) {
      debugPrint('PushMessagingService: skip register, not initialized');
      return;
    }
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _registerToken(token);
    } catch (_) {}
  }

  Future<void> _registerToken(String? token) async {
    if (!PlatformDetection.isMobile) return;
    if (token == null || token.isEmpty) {
      debugPrint('PushMessagingService: skip register, no FCM token');
      return;
    }
    if (token == _lastRegisteredToken) return;

    final client = GetIt.instance.isRegistered<MediaServerClient>()
        ? GetIt.instance<MediaServerClient>()
        : null;
    if (client == null ||
        client.accessToken == null ||
        client.accessToken!.isEmpty) {
      debugPrint('PushMessagingService: skip register, no active session');
      return;
    }

    if (!GetIt.instance.isRegistered<PluginSyncService>()) {
      debugPrint('PushMessagingService: skip register, plugin sync unavailable');
      return;
    }
    final sync = GetIt.instance<PluginSyncService>();

    await sync.registerPushDevice(
      client,
      token: token,
      platform: PlatformDetection.isIOS ? 'ios' : 'android',
      deviceId: _deviceId(token),
    );
    _lastRegisteredToken = token;
  }

  /// Unregister this device with the plugin, e.g. on logout. No-op off mobile
  /// or when there is no active client.
  Future<void> unregister() async {
    if (!PlatformDetection.isMobile) return;

    final client = GetIt.instance.isRegistered<MediaServerClient>()
        ? GetIt.instance<MediaServerClient>()
        : null;
    if (client == null) return;
    if (!GetIt.instance.isRegistered<PluginSyncService>()) return;

    await GetIt.instance<PluginSyncService>().unregisterPushDevice(
      client,
      deviceId: _deviceId(_lastRegisteredToken),
    );
    _lastRegisteredToken = null;
  }

  /// Reuses the app's Jellyfin device id so the plugin can tie the push
  /// registration to the same session; falls back to the token hash if the id
  /// is unavailable.
  String _deviceId(String? token) {
    if (GetIt.instance.isRegistered<DeviceInfo>()) {
      final id = GetIt.instance<DeviceInfo>().id.trim();
      if (id.isNotEmpty) return id;
    }
    return (token ?? '').hashCode.toString();
  }

  void _navigateFromMessage(RemoteMessage message) {
    final route = message.data['route'];
    if (route is String && route.trim().isNotEmpty) {
      appRouter.go(route.trim());
    }
  }
}
