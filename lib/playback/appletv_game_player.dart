import 'dart:async';

import 'package:flutter/services.dart';

/// Result of loading a game into the native tvOS emulator.
class GameLoadInfo {
  const GameLoadInfo({
    required this.textureId,
    required this.width,
    required this.height,
    required this.aspect,
    required this.fps,
    required this.sampleRate,
  });

  final int textureId;
  final int width;
  final int height;
  final double aspect;
  final double fps;
  final double sampleRate;
}

/// One emulator core option (from the core's variables list).
class GameCoreOption {
  const GameCoreOption({
    required this.id,
    required this.label,
    required this.current,
    required this.choices,
  });

  final String id;
  final String label;
  final String current;
  final List<String> choices;
}

/// Bridge to the native tvOS libretro session (AppleTvGameChannel). The core's
/// video arrives as a Flutter texture; controller input stays native, so this
/// channel only carries lifecycle, saves, options, and UI events.
class AppleTvGamePlayer {
  static const _control = MethodChannel('moonfin/appletv_game_control');
  static const _events = EventChannel('moonfin/appletv_game_events');
  static Stream<Map<String, dynamic>>? _sharedEvents;

  static Stream<Map<String, dynamic>> get events {
    return _sharedEvents ??= _events
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => (event as Map).cast<String, dynamic>())
        .asBroadcastStream();
  }

  Future<GameLoadInfo> load({
    required String core,
    required String romPath,
    required String systemDir,
    required String saveDir,
    required String gameId,
    Map<String, String>? options,
  }) async {
    final result = await _control.invokeMethod<Map<dynamic, dynamic>>('load', {
      'core': core,
      'romPath': romPath,
      'systemDir': systemDir,
      'saveDir': saveDir,
      'gameId': gameId,
      if (options != null && options.isNotEmpty) 'options': options,
    });
    if (result == null) {
      throw PlatformException(code: 'load_failed');
    }
    return GameLoadInfo(
      textureId: (result['textureId'] as num).toInt(),
      width: (result['width'] as num?)?.toInt() ?? 0,
      height: (result['height'] as num?)?.toInt() ?? 0,
      aspect: (result['aspect'] as num?)?.toDouble() ?? (4 / 3),
      fps: (result['fps'] as num?)?.toDouble() ?? 60,
      sampleRate: (result['sampleRate'] as num?)?.toDouble() ?? 44100,
    );
  }

  Future<void> start() => _invoke('start');
  Future<void> pause() => _invoke('pause');
  Future<void> resume() => _invoke('resume');
  Future<void> restart() => _invoke('restart');
  Future<void> stop() => _invoke('stop');

  Future<Uint8List?> saveState() async {
    try {
      final data = await _control.invokeMethod<Uint8List>('saveState');
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<bool> loadState(Uint8List data) async {
    try {
      final ok = await _control.invokeMethod<bool>('loadState', {'data': data});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setFastForward(int factor) async {
    try {
      await _control.invokeMethod<void>('setFastForward', {'factor': factor});
    } catch (_) {}
  }

  // Briefly holds a RetroPad button (index) so the overlay can send Start/Select.
  Future<void> pulseButton(int index, {int durationMs = 150}) async {
    try {
      await _control.invokeMethod<void>(
          'pulseButton', {'index': index, 'durationMs': durationMs});
    } catch (_) {}
  }

  Future<List<GameCoreOption>> getOptions() async {
    final raw = await _control.invokeMethod<List<dynamic>>('getOptions');
    return (raw ?? const [])
        .whereType<Map>()
        .map((m) {
          final map = m.cast<String, dynamic>();
          final choices = (map['choices'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((c) => c['value']?.toString() ?? '')
              .where((v) => v.isNotEmpty)
              .toList(growable: false);
          return GameCoreOption(
            id: map['id']?.toString() ?? '',
            label: map['label']?.toString() ?? '',
            current: map['current']?.toString() ?? '',
            choices: choices,
          );
        })
        .where((o) => o.id.isNotEmpty && o.choices.length > 1)
        .toList(growable: false);
  }

  Future<void> setOption(String id, String value) async {
    try {
      await _control
          .invokeMethod<void>('setOption', {'id': id, 'value': value});
    } catch (_) {}
  }

  Future<Map<String, String>> getCurrentOptions() async {
    try {
      final raw =
          await _control.invokeMethod<Map<dynamic, dynamic>>('getCurrentOptions');
      return (raw ?? const {}).cast<String, String>();
    } catch (_) {
      return const {};
    }
  }

  Future<int> controllerCount() async {
    try {
      final count = await _control.invokeMethod<int>('controllerCount');
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _invoke(String method) async {
    try {
      await _control.invokeMethod<void>(method);
    } catch (_) {}
  }
}
