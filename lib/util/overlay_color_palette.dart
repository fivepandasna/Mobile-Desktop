import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

abstract final class OverlayColorPalette {
  static const keys = <String>[
    'gray',
    'black',
    'dark_blue',
    'purple',
    'teal',
    'navy',
    'charcoal',
    'brown',
    'dark_red',
    'dark_green',
    'slate',
    'indigo',
  ];

  static const pickerSwatches = <String, int>{
    'gray': 0xFF6B7280,
    'black': 0xFF111827,
    'dark_blue': 0xFF1E3A8A,
    'purple': 0xFF6D28D9,
    'teal': 0xFF0F766E,
    'navy': 0xFF1E293B,
    'charcoal': 0xFF374151,
    'brown': 0xFF7C4A2D,
    'dark_red': 0xFF7F1D1D,
    'dark_green': 0xFF14532D,
    'slate': 0xFF334155,
    'indigo': 0xFF4338CA,
  };

  static Color resolveColor(String colorName) {
    return switch (colorName) {
      'black' => Colors.black,
      'gray' => Colors.grey,
      'dark_blue' => const Color(0xFF1A2332),
      'purple' => const Color(0xFF4A148C),
      'teal' => const Color(0xFF00695C),
      'navy' => const Color(0xFF0D1B2A),
      'charcoal' => const Color(0xFF36454F),
      'brown' => const Color(0xFF3E2723),
      'dark_red' => const Color(0xFF8B0000),
      'dark_green' => const Color(0xFF0B4F0F),
      'slate' => const Color(0xFF475569),
      'indigo' => const Color(0xFF1E3A8A),
      _ => Colors.grey,
    };
  }

  static String labelFor(String key, AppLocalizations l10n) {
    return switch (key) {
      'gray' => l10n.gray,
      'black' => l10n.black,
      'dark_blue' => l10n.darkBlue,
      'purple' => l10n.purple,
      'teal' => l10n.teal,
      'navy' => l10n.navy,
      'charcoal' => l10n.charcoal,
      'brown' => l10n.brown,
      'dark_red' => l10n.darkRed,
      'dark_green' => l10n.darkGreen,
      'slate' => l10n.slate,
      'indigo' => l10n.indigo,
      _ => key,
    };
  }

  static Map<String, String> localizedOptions(AppLocalizations l10n) {
    return {for (final key in keys) key: labelFor(key, l10n)};
  }
}
