import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A full-width framed stepper control for custody item counts.
///
/// Used by:
/// - `CustodyCountList` (P6 blind count) -- neutral/untinted, editable.
/// - `CustodyReveal` (STEP 2/2 compare) -- status-tinted, editable.
///
/// NOT a dispatched SDUI type; purely internal. No barrel export, no dispatch
/// branch.
///
/// Layout (full-width):
/// ```
///   +---------------------------------------------+
///   |  [ - ]     big centered number      [ + ]   |
///   |                status line                   |
///   +---------------------------------------------+
/// ```
///
/// When [enabled] is false, the -/+ buttons are disabled (reduced opacity,
/// no onTap). When the value is at [min], the decrement button is disabled.
class CustodyStepper extends StatelessWidget {
  const CustodyStepper({
    super.key,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    this.min = 0,
    this.enabled = true,
    this.showButtons = true,
    this.frameBg,
    this.frameBorder,
    this.numberColor,
    this.statusLine,
  });

  /// Current integer value displayed in the center.
  final int value;

  /// Called when the decrement button is tapped. Null = button always disabled.
  final VoidCallback? onDecrement;

  /// Called when the increment button is tapped. Null = button always disabled.
  final VoidCallback? onIncrement;

  /// Minimum allowed value (default 0). Decrement disabled when `value <= min`.
  final int min;

  /// Whether the stepper is interactive. When false, both buttons are disabled
  /// regardless of value.
  final bool enabled;

  /// Whether to show the -/+ buttons. When false, only the centered number
  /// (and optional status line) renders inside the frame — buttons are
  /// genuinely removed, not just faded. Default true.
  final bool showButtons;

  /// Background color of the stepper frame. Null = white (neutral).
  final Color? frameBg;

  /// Border color of the stepper frame. Null = Color(0xFFE2E8F0) (slate-200).
  final Color? frameBorder;

  /// Color of the big centered number. Null = Color(0xFF1E293B) (slate-800).
  final Color? numberColor;

  /// Optional widget displayed below the number (e.g. status label like
  /// "Match" or "Selisih: +3"). Null = no status line.
  final Widget? statusLine;

  // -- Layout constants ---------------------------------------------------
  static const double _btnSize = 40.0;
  static const double _iconSize = 20.0;
  static const double _numberFontSize = 26.0;

  @override
  Widget build(BuildContext context) {
    final bool canDecrement = enabled && value > min && onDecrement != null;
    final bool canIncrement = enabled && onIncrement != null;

    final Color bgColor = frameBg ?? Colors.white;
    final Color borderColor = frameBorder ?? const Color(0xFFE2E8F0);
    final Color numColor = numberColor ?? const Color(0xFF1E293B);
    // Button icon color: use numberColor when enabled, faded when disabled.
    final Color activeIconColor = numColor;
    final Color disabledIconColor = numColor.withValues(alpha: 0.25);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          // -- Decrement button --
          if (showButtons)
            _stepButton(
              icon: Icons.remove,
              enabled: canDecrement,
              activeColor: activeIconColor,
              disabledColor: disabledIconColor,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(9),
              ),
              onTap: canDecrement
                  ? () {
                      onDecrement!();
                      HapticFeedback.selectionClick();
                    }
                  : null,
            ),

          // -- Center: number + optional status line --
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _numberFontSize,
                    fontWeight: FontWeight.w800,
                    color: numColor,
                    height: 1.05,
                  ),
                ),
                if (statusLine != null) ...[
                  const SizedBox(height: 2),
                  statusLine!,
                ],
              ],
            ),
          ),

          // -- Increment button --
          if (showButtons)
            _stepButton(
              icon: Icons.add,
              enabled: canIncrement,
              activeColor: activeIconColor,
              disabledColor: disabledIconColor,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(9),
              ),
              onTap: canIncrement
                  ? () {
                      onIncrement!();
                      HapticFeedback.selectionClick();
                    }
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required Color activeColor,
    required Color disabledColor,
    required BorderRadius borderRadius,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _btnSize,
        height: _btnSize,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.white.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.5),
          borderRadius: borderRadius,
          border: Border.all(
            color: enabled
                ? activeColor.withValues(alpha: 0.3)
                : disabledColor.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: _iconSize,
          color: enabled ? activeColor : disabledColor,
        ),
      ),
    );
  }
}

// -- Pure-logic helpers (for testability) ----------------------------------

/// Clamp a stepper value to the minimum bound. Used by both P6 count list
/// and reveal to enforce min=0 on decrement.
///
/// Exported as a named function so tests can verify clamping without
/// constructing the widget.
int clampStepperValue(int value, int min) => value < min ? min : value;
