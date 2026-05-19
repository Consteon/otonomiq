import 'package:flutter/material.dart';

import '../global.dart';

class ApproverStickyBar extends StatefulWidget {
  static final ValueNotifier<WidgetBuilder?> slot = ValueNotifier(null);
  static final ValueNotifier<bool> overlaysHidden = ValueNotifier(false);

  const ApproverStickyBar({
    super.key,
    required this.builder,
    required this.scrName,
  });

  final Widget Function() builder;
  final String scrName;

  @override
  State<ApproverStickyBar> createState() => _ApproverStickyBarState();
}

class _ApproverStickyBarState extends State<ApproverStickyBar>
    with AutomaticKeepAliveClientMixin {
  OverlayEntry? _entry;
  bool _slotMode = false;
  WidgetBuilder? _registeredBuilder;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (_hasCommentInput()) {
      _slotMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _registeredBuilder = (_) => widget.builder();
        ApproverStickyBar.slot.value = _registeredBuilder;
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _insertOverlay());
    }
  }

  @override
  void didUpdateWidget(covariant ApproverStickyBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_slotMode) {
        _registeredBuilder = (_) => widget.builder();
        ApproverStickyBar.slot.value = _registeredBuilder;
      } else {
        _entry?.markNeedsBuild();
      }
    });
  }

  bool _hasCommentInput() {
    try {
      final children = screenUIComponent[widget.scrName]?['children'] ?? [];
      for (final c in children) {
        if (c is Map &&
            c['type']?.toString().toLowerCase() == 'comment_detail') {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  void _insertOverlay() {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (entryCtx) => ValueListenableBuilder<bool>(
        valueListenable: ApproverStickyBar.overlaysHidden,
        builder: (ctx, hidden, _) {
          if (hidden) return const SizedBox.shrink();
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          if (bottomInset > 0) return const SizedBox.shrink();
          final safeBottom = MediaQuery.of(ctx).padding.bottom;
          final hideNav =
              screenUIComponent[widget.scrName]?['hideBottomBar'] == true;
          final navBarHeight = hideNav ? 0.0 : 66.0;
          final commentInputOffset = _hasCommentInput() ? 76.0 : 0.0;
          final bottomPadding = hideNav ? 8.0 : 0.0;
          return Positioned(
            left: 0,
            right: 0,
            bottom: navBarHeight + safeBottom + commentInputOffset,
            child: Material(
              color: Colors.white,
              elevation: 8,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  child: widget.builder(),
                ),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  void dispose() {
    if (_slotMode) {
      final mine = _registeredBuilder;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ApproverStickyBar.slot.value == mine) {
          ApproverStickyBar.slot.value = null;
        }
      });
    }
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const SizedBox.shrink();
  }
}
