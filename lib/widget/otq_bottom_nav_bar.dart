import 'package:flutter/material.dart';

class OtqBottomNavBar extends StatefulWidget {
  final int selectedIndex;
  final List<OtqNavItem> items;
  final ValueChanged<int> onTap;

  const OtqBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onTap,
  });

  @override
  State<OtqBottomNavBar> createState() => _OtqBottomNavBarState();
}

class _OtqBottomNavBarState extends State<OtqBottomNavBar>
    with TickerProviderStateMixin {
  late List<AnimationController> _scaleControllers;
  late List<Animation<double>> _scaleAnimations;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _scaleControllers = List.generate(
      widget.items.length,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
        value: widget.selectedIndex == i ? 1.0 : 0.0,
      ),
    );
    _scaleAnimations = _scaleControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOutBack))
        .toList();
  }

  @override
  void didUpdateWidget(covariant OtqBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      for (final c in _scaleControllers) {
        c.dispose();
      }
      _initAnimations();
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      for (int i = 0; i < _scaleControllers.length; i++) {
        if (i == widget.selectedIndex) {
          _scaleControllers[i].forward();
        } else {
          _scaleControllers[i].reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _scaleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final bgLuminance = theme.scaffoldBackgroundColor.computeLuminance();
    final isDark = bgLuminance < 0.4;

    final barColor = isDark
        ? Colors.grey.shade900.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.95);
    final inactiveColor = isDark ? Colors.grey.shade500 : Colors.grey.shade400;
    final pillColor = HSLColor.fromColor(primaryColor)
        .withLightness(isDark ? 0.25 : 0.92)
        .withSaturation(isDark ? 0.5 : 0.35)
        .toColor();
    final activeColor = HSLColor.fromColor(
      primaryColor,
    ).withLightness(isDark ? 0.7 : 0.35).withSaturation(0.8).toColor();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(widget.items.length, (i) {
              final item = widget.items[i];

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTap(i),
                  child: AnimatedBuilder(
                    animation: _scaleAnimations[i],
                    builder: (context, child) {
                      final t = _scaleAnimations[i].value;
                      final iconColor = Color.lerp(
                        inactiveColor,
                        activeColor,
                        t,
                      )!;
                      final iconSize = 24.0 + (2.0 * t);

                      return Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.0 + (4.0 * t),
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: pillColor.withValues(alpha: 0.0 + (1.0 * t)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        // heightFactor:1 shrink-wraps vertically (no blowup);
                        // Center fills the slot width and centers the icon+badge
                        // Stack, which then sizes to the icon so the badge hugs
                        // its corner instead of the far pill edge.
                        child: Center(
                          heightFactor: 1.0,
                          child: _buildIcon(item, iconColor, iconSize),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(OtqNavItem item, Color color, double size) {
    Widget iconWidget = Icon(item.icon, color: color, size: size);

    if (item.badgeCount != null && item.badgeCount! > 0) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade400, Colors.red.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  item.badgeCount! > 99 ? '99+' : '${item.badgeCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return iconWidget;
  }
}

class OtqNavItem {
  final IconData? icon;
  final String? label;
  final int? badgeCount;

  const OtqNavItem({this.icon, this.label, this.badgeCount});

  OtqNavItem copyWith({IconData? icon, String? label, int? badgeCount}) {
    return OtqNavItem(
      icon: icon ?? this.icon,
      label: label ?? this.label,
      badgeCount: badgeCount ?? this.badgeCount,
    );
  }
}
