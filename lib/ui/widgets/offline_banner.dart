import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../di/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../util/platform_detection.dart';
import '../navigation/app_router.dart';
import '../navigation/destinations.dart';
import '../screens/downloads/downloads_panel.dart';

class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key});

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  static const _tvAutoDismissDuration = Duration(seconds: 7);

  bool _dismissed = false;
  bool _lastIsOnline = true;
  bool _lastServerReachable = true;
  Timer? _autoDismissTimer;

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _scheduleTvAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(_tvAutoDismissDuration, () {
      if (mounted) setState(() => _dismissed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isOnline = ref.watch(isOnlineProvider);
    final serverReachable = ref.watch(activeServerReachableProvider);
    final isTv = PlatformDetection.useLeanbackUi;

    if (isOnline != _lastIsOnline || serverReachable != _lastServerReachable) {
      _lastIsOnline = isOnline;
      _lastServerReachable = serverReachable;
      _dismissed = false;
      _autoDismissTimer?.cancel();
      _autoDismissTimer = null;
    }

    if ((isOnline && serverReachable) || _dismissed) {
      return const SizedBox.shrink();
    }

    final isServerUnavailable = isOnline && !serverReachable;
    final bannerText = isServerUnavailable
        ? l10n.offlineServerUnavailable
        : l10n.offlineNoInternet;
    final showAction = !isTv;
    final actionLabel = isServerUnavailable ? l10n.offlineSwitchServer : l10n.offlineSavedMedia;
    // The regular UI already shows only downloaded items when offline, so
    // the banner action just opens the downloads dialog.
    final action = isServerUnavailable
        ? () => appRouter.go(Destinations.serverSelect)
        : () => showDownloadsDialog(context);

    if (isTv && _autoDismissTimer == null) {
      _scheduleTvAutoDismiss();
    }

    final banner = SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: AppColorScheme.statusPending.withValues(alpha: 0.9),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: AppColorScheme.onSurface, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                bannerText,
                style: TextStyle(color: AppColorScheme.onSurface, fontSize: 13),
              ),
            ),
            if (showAction)
              TextButton(
                onPressed: action,
                style: TextButton.styleFrom(
                  foregroundColor: AppColorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(actionLabel),
              ),
          ],
        ),
      ),
    );

    if (isTv) {
      return banner;
    }

    return Dismissible(
      key: ValueKey('offline_banner_${isServerUnavailable ? 'server' : 'network'}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => setState(() => _dismissed = true),
      child: banner,
    );
  }
}
