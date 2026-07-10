import 'platform_detection.dart';

/// Which EmulatorJS core names the native tvOS build can actually run.
///
/// The plugin names cores in EmulatorJS terms (nes, snes, gb, gba, segaMD, ...).
/// tvOS bundles a fixed set of libretro cores (no runtime downloads on the App
/// Store), so systems outside this map keep the "not supported" message there.
/// Every other platform runs EmulatorJS itself and supports whatever the plugin
/// serves.
const Map<String, String> _tvosBundledCores = {
  'nes': 'fceumm',
  'snes': 'snes9x',
  'gb': 'gambatte',
  'gba': 'mgba',
  'segaMD': 'genesis_plus_gx',
  'segaMS': 'genesis_plus_gx',
  'segaGG': 'genesis_plus_gx',
  'psx': 'pcsx_rearmed',
};

bool gameCoreSupported(String core) {
  if (!PlatformDetection.isAppleTV) return true;
  return _tvosBundledCores.containsKey(core);
}

/// The bundled libretro core id for an EmulatorJS core name (tvOS only).
String? bundledCoreId(String core) => _tvosBundledCores[core];
