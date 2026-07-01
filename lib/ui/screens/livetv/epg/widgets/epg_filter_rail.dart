import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../widgets/adaptive/adaptive_glass.dart';
import '../../../../widgets/focus/focusable_wrapper.dart';

/// Horizontal genre filter rail. Focusable pill chips (full d-pad on every
/// platform); on Apple the chips sit inside a frosted segmented-style container
/// with a light selected capsule, on Material they are standalone accent pills.
class EpgFilterRail extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool apple;
  final FocusNode Function(int index) focusNodeFor;
  final VoidCallback? onNavigateDown;

  const EpgFilterRail({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
    required this.apple,
    required this.focusNodeFor,
    this.onNavigateDown,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: EdgeInsets.only(right: apple ? 2 : 8),
            child: FocusableWrapper(
              focusNode: focusNodeFor(i),
              disableScale: true,
              useBackgroundFocus: true,
              borderRadius: 14,
              onSelect: () => onSelect(i),
              onNavigateLeft: () {
                if (i > 0) focusNodeFor(i - 1).requestFocus();
              },
              onNavigateRight: () {
                if (i < labels.length - 1) focusNodeFor(i + 1).requestFocus();
              },
              onNavigateDown: onNavigateDown,
              child: _chip(context, i),
            ),
          ),
      ],
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: apple
          ? adaptiveGlass(
              cornerRadius: 15,
              blur: 14,
              fallbackColor: AppColorScheme.surface.withValues(alpha: 0.35),
              tint: Colors.white.withValues(alpha: 0.06),
              child: Padding(padding: const EdgeInsets.all(3), child: row),
            )
          : row,
    );
  }

  Widget _chip(BuildContext context, int i) {
    final selected = i == selectedIndex;
    final textTheme = Theme.of(context).textTheme;
    final Color bg;
    final Color fg;
    if (selected) {
      bg = apple ? const Color(0xFFF4F8FC) : AppColorScheme.accent;
      fg = const Color(0xFF10242E);
    } else {
      bg = apple
          ? Colors.transparent
          : AppColorScheme.surface.withValues(alpha: 0.55);
      fg = AppColorScheme.onSurface.withValues(alpha: 0.85);
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.circular(13),
        border: (!apple && !selected)
            ? Border.all(color: AppColorScheme.onSurface.withValues(alpha: 0.12))
            : null,
      ),
      child: Text(
        labels[i],
        style: textTheme.labelLarge?.copyWith(
          color: fg,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}
