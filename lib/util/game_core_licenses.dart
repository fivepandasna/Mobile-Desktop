import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The libretro cores bundled in the native Apple TV build, with the display
/// name shown on the licenses screen and the asset holding each core's license.
/// Snes9x and Genesis Plus GX are non-commercial licenses that require this
/// attribution when their binaries ship inside the app.
const Map<String, String> _coreLicenses = {
  'Snes9x (SNES core)': 'snes9x',
  'Genesis Plus GX (Sega core)': 'genesis_plus_gx',
  'fceumm (NES core)': 'fceumm',
  'Gambatte (Game Boy core)': 'gambatte',
  'mGBA (Game Boy Advance core)': 'mgba',
  'PCSX ReARMed (PlayStation core)': 'pcsx_rearmed',
};

/// Adds the bundled emulator cores to LicenseRegistry so they appear on the
/// licenses screen. Call only on builds that ship the core binaries (tvOS).
void registerGameCoreLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in _coreLicenses.entries) {
      final text =
          await rootBundle.loadString('assets/licenses/cores/${entry.value}.txt');
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}
