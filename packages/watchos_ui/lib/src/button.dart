import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Pill-shaped watchOS action button enforcing a minimum touch target (44x44 pt by default).
class WatchOSButton extends StatefulWidget {
  const WatchOSButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.onHaptic,
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.minWidth,
    this.minHeight,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onHaptic;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry padding;
  final double? minWidth;
  final double? minHeight;
  final BorderRadius? borderRadius;

  @override
  State<WatchOSButton> createState() => _WatchOSButtonState();
}

class _WatchOSButtonState extends State<WatchOSButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    if (widget.onPressed == null) return;
    widget.onHaptic?.call();
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = WatchOSTheme.of(context);
    final enabled = widget.onPressed != null;
    final bg = widget.backgroundColor ?? theme.surfaceColor;
    final fg = widget.foregroundColor ?? theme.foregroundColor;
    final minW = widget.minWidth ?? theme.minTouchTarget;
    final minH = widget.minHeight ?? theme.minTouchTarget;
    final radius = widget.borderRadius ?? BorderRadius.circular(999);

    return Semantics(
      button: true,
      enabled: enabled,
      onTap: enabled ? _handleTap : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minW,
          minHeight: minH,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: enabled ? _handleTap : null,
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: AnimatedOpacity(
              opacity: enabled ? (_pressed ? 0.85 : 1.0) : 0.45,
              duration: const Duration(milliseconds: 90),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: radius,
                ),
                child: Padding(
                  padding: widget.padding,
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                    child: Center(
                      widthFactor: 1.0,
                      heightFactor: 1.0,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
