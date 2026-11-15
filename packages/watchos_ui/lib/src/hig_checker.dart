import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'screen_profile.dart';

enum WatchOSHigViolationSeverity {
  critical,
  warning,
}

@immutable
class WatchOSHigViolation {
  const WatchOSHigViolation({
    required this.category,
    required this.severity,
    required this.message,
    required this.bounds,
  });

  final String category;
  final WatchOSHigViolationSeverity severity;
  final String message;
  final Rect bounds;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WatchOSHigViolation &&
            other.category == category &&
            other.severity == severity &&
            other.message == message &&
            other.bounds == bounds;
  }

  @override
  int get hashCode => Object.hash(category, severity, message, bounds);

  @override
  String toString() => '[$category/${severity.name}] $message';
}

/// Propagates the active [WatchOSScreenProfile] when previewing on desktop/web/tests.
class WatchOSPreviewScope extends InheritedWidget {
  const WatchOSPreviewScope({
    super.key,
    required this.profile,
    required super.child,
  });

  final WatchOSScreenProfile profile;

  static WatchOSScreenProfile? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WatchOSPreviewScope>()
        ?.profile;
  }

  @override
  bool updateShouldNotify(WatchOSPreviewScope oldWidget) =>
      profile != oldWidget.profile;
}

/// Configuration for [WatchOSHigChecker].
///
/// Numeric defaults (`44.0` pt touch target, `14.0`–`34.0` pt font bounds,
/// `#000000` background) and the opt-in font-size / pure-black rules use v0
/// conservative defaults, not verified against current HIG.
@immutable
class WatchOSHigConfig {
  const WatchOSHigConfig({
    this.minTouchTarget = 44.0,
    this.minFontSize = 14.0,
    this.maxFontSize = 34.0,
    this.pureBlackColor = const Color(0xFF000000),
    this.checkOverflow = true,
    this.checkTouchTarget = true,
    this.checkFontSize = false,
    this.checkPureBlack = false,
  });

  /// Minimum interactive hit-target extent in logical points.
  /// v0 conservative defaults, not verified against current HIG.
  final double minTouchTarget;

  /// Minimum font size in logical points when [checkFontSize] is enabled.
  /// v0 conservative defaults, not verified against current HIG.
  final double minFontSize;

  /// Maximum font size in logical points when [checkFontSize] is enabled.
  /// v0 conservative defaults, not verified against current HIG.
  final double maxFontSize;

  /// Expected pure-black OLED background when [checkPureBlack] is enabled.
  /// v0 conservative defaults, not verified against current HIG.
  final Color pureBlackColor;

  /// Flags horizontal overflow beyond the audited root viewport. On by default.
  final bool checkOverflow;

  /// Flags interactive targets smaller than [minTouchTarget]. On by default.
  final bool checkTouchTarget;

  /// Opt-in rule flagging text outside `[minFontSize, maxFontSize]`.
  /// Default off; v0 conservative defaults, not verified against current HIG.
  final bool checkFontSize;

  /// Opt-in rule flagging screen-filling backgrounds that are not [pureBlackColor].
  /// Default off; v0 conservative defaults, not verified against current HIG.
  final bool checkPureBlack;

  WatchOSHigConfig copyWith({
    double? minTouchTarget,
    double? minFontSize,
    double? maxFontSize,
    Color? pureBlackColor,
    bool? checkOverflow,
    bool? checkTouchTarget,
    bool? checkFontSize,
    bool? checkPureBlack,
  }) {
    return WatchOSHigConfig(
      minTouchTarget: minTouchTarget ?? this.minTouchTarget,
      minFontSize: minFontSize ?? this.minFontSize,
      maxFontSize: maxFontSize ?? this.maxFontSize,
      pureBlackColor: pureBlackColor ?? this.pureBlackColor,
      checkOverflow: checkOverflow ?? this.checkOverflow,
      checkTouchTarget: checkTouchTarget ?? this.checkTouchTarget,
      checkFontSize: checkFontSize ?? this.checkFontSize,
      checkPureBlack: checkPureBlack ?? this.checkPureBlack,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WatchOSHigConfig &&
            other.minTouchTarget == minTouchTarget &&
            other.minFontSize == minFontSize &&
            other.maxFontSize == maxFontSize &&
            other.pureBlackColor == pureBlackColor &&
            other.checkOverflow == checkOverflow &&
            other.checkTouchTarget == checkTouchTarget &&
            other.checkFontSize == checkFontSize &&
            other.checkPureBlack == checkPureBlack;
  }

  @override
  int get hashCode => Object.hash(
        minTouchTarget,
        minFontSize,
        maxFontSize,
        pureBlackColor,
        checkOverflow,
        checkTouchTarget,
        checkFontSize,
        checkPureBlack,
      );
}

/// Inspects the laid-out render tree for Apple Watch HIG violations configured
/// by [config]:
/// - Horizontal overflow beyond the watch viewport (`checkOverflow`, default on)
/// - Touch targets smaller than `minTouchTarget` (`checkTouchTarget`, default on)
/// - Opt-in font-size bounds (`checkFontSize`, default off)
/// - Opt-in pure-black root background check (`checkPureBlack`, default off)
class WatchOSHigChecker extends StatefulWidget {
  const WatchOSHigChecker({
    super.key,
    required this.child,
    this.config = const WatchOSHigConfig(),
    this.minTouchTarget,
    this.showOverlay = true,
    this.onViolations,
  });

  final Widget child;
  final WatchOSHigConfig config;
  final double? minTouchTarget;
  final bool showOverlay;
  final ValueChanged<List<WatchOSHigViolation>>? onViolations;

  WatchOSHigConfig get resolvedConfig => minTouchTarget == null
      ? config
      : config.copyWith(minTouchTarget: minTouchTarget);

  @override
  State<WatchOSHigChecker> createState() => _WatchOSHigCheckerState();
}

class _WatchOSHigCheckerState extends State<WatchOSHigChecker> {
  final GlobalKey _auditKey = GlobalKey();
  List<WatchOSHigViolation> _violations = const <WatchOSHigViolation>[];
  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleAudit();
  }

  @override
  void didUpdateWidget(WatchOSHigChecker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleAudit();
  }

  void _scheduleAudit() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) {
        _runAudit();
      }
    });
  }

  void _runAudit() {
    final rootContext = _auditKey.currentContext;
    final rootBox = rootContext?.findRenderObject() as RenderBox?;
    if (rootContext == null || rootBox == null || !rootBox.hasSize || !rootBox.attached) {
      return;
    }

    final rootRect = rootBox.localToGlobal(Offset.zero) & rootBox.size;
    final cfg = widget.resolvedConfig;
    final found = <WatchOSHigViolation>[];
    final checkedOverflow = <RenderObject>{};
    final checkedTargets = <RenderObject>{};
    final checkedFonts = <RenderObject>{};
    final checkedBackgrounds = <RenderObject>{};

    void checkTextSpan(InlineSpan span, double? inheritedSize, Rect rect) {
      if (span is! TextSpan) return;
      final effectiveSize = span.style?.fontSize ?? inheritedSize;
      final children = span.children;
      final hasLeafText = (span.text?.isNotEmpty ?? false) ||
          (children == null || children.isEmpty);
      if (hasLeafText && effectiveSize != null) {
        if (effectiveSize + 0.01 < cfg.minFontSize) {
          found.add(
            WatchOSHigViolation(
              category: 'fontSize',
              severity: WatchOSHigViolationSeverity.warning,
              message:
                  'Font size ${effectiveSize.toStringAsFixed(1)} pt < ${cfg.minFontSize.toStringAsFixed(1)} pt',
              bounds: rect,
            ),
          );
        } else if (effectiveSize - 0.01 > cfg.maxFontSize) {
          found.add(
            WatchOSHigViolation(
              category: 'fontSize',
              severity: WatchOSHigViolationSeverity.warning,
              message:
                  'Font size ${effectiveSize.toStringAsFixed(1)} pt > ${cfg.maxFontSize.toStringAsFixed(1)} pt',
              bounds: rect,
            ),
          );
        }
      }
      if (children != null) {
        for (final child in children) {
          checkTextSpan(child, effectiveSize, rect);
        }
      }
    }

    void visit(Element element, {required bool checkOverflow}) {
      final ro = element.renderObject;
      final w = element.widget;

      var childCheckOverflow = checkOverflow;
      if (w is Scrollable &&
          w.axisDirection != AxisDirection.down &&
          w.axisDirection != AxisDirection.up) {
        childCheckOverflow = false;
      }

      if (ro is RenderBox && ro.hasSize && ro.attached) {
        final rect = ro.localToGlobal(Offset.zero) & ro.size;

        if (cfg.checkOverflow &&
            checkOverflow &&
            (rect.left < rootRect.left - 0.5 || rect.right > rootRect.right + 0.5) &&
            checkedOverflow.add(ro)) {
          found.add(
            WatchOSHigViolation(
              category: 'overflow',
              severity: WatchOSHigViolationSeverity.critical,
              message:
                  'Horizontal overflow (${ro.size.width.toStringAsFixed(1)} pt in ${rootBox.size.width.toStringAsFixed(1)} pt)',
              bounds: rect,
            ),
          );
        }

        final isInteractive = (w is GestureDetector &&
                (w.onTap != null || w.onDoubleTap != null || w.onLongPress != null)) ||
            (w is Semantics && (w.properties.button == true || w.properties.onTap != null));

        if (cfg.checkTouchTarget && isInteractive && checkedTargets.add(ro)) {
          if (ro.size.width + 0.01 < cfg.minTouchTarget ||
              ro.size.height + 0.01 < cfg.minTouchTarget) {
            found.add(
              WatchOSHigViolation(
                category: 'touchTarget',
                severity: WatchOSHigViolationSeverity.critical,
                message:
                    'Target ${ro.size.width.toStringAsFixed(1)}x${ro.size.height.toStringAsFixed(1)} < ${cfg.minTouchTarget.toStringAsFixed(0)}x${cfg.minTouchTarget.toStringAsFixed(0)} pt',
                bounds: rect,
              ),
            );
          }
        }

        if (cfg.checkFontSize && ro is RenderParagraph && checkedFonts.add(ro)) {
          checkTextSpan(ro.text, null, rect);
        }

        if (cfg.checkPureBlack && checkedBackgrounds.add(ro)) {
          Color? bgColor;
          if (w is ColoredBox) {
            bgColor = w.color;
          } else if (w is DecoratedBox) {
            final decoration = w.decoration;
            if (decoration is BoxDecoration) {
              bgColor = decoration.color;
            }
          }
          final coversRoot = rect.width + 0.5 >= rootRect.width &&
              rect.height + 0.5 >= rootRect.height;
          if (bgColor != null &&
              bgColor.a > 0 &&
              coversRoot &&
              bgColor != cfg.pureBlackColor) {
            const zero = '0';
            final argbHex = bgColor.toARGB32().toRadixString(16).padLeft(8, zero).toUpperCase();
            found.add(
              WatchOSHigViolation(
                category: 'pureBlack',
                severity: WatchOSHigViolationSeverity.warning,
                message: 'Non-pure-black background (0x$argbHex)',
                bounds: rect,
              ),
            );
          }
        }
      }

      element.visitChildren((Element child) => visit(child, checkOverflow: childCheckOverflow));
    }

    rootContext.visitChildElements((Element child) => visit(child, checkOverflow: true));

    if (!listEquals(_violations, found)) {
      setState(() => _violations = List<WatchOSHigViolation>.unmodifiable(found));
      widget.onViolations?.call(_violations);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAudit();

    return Stack(
      children: <Widget>[
        KeyedSubtree(key: _auditKey, child: widget.child),
        if (widget.showOverlay && _violations.isNotEmpty)
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xDD8B0000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'HIG: ${_violations.length} issue(s)\n${_violations.first.message}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Constrains and renders [child] inside a realistic Apple Watch screen bezel on desktop/web/tests.
class WatchOSPreviewFrame extends StatelessWidget {
  const WatchOSPreviewFrame({
    super.key,
    required this.child,
    this.watchSize = WatchOSSize.mm46,
    this.showBezel = true,
  });

  final Widget child;
  final WatchOSSize watchSize;
  final bool showBezel;

  @override
  Widget build(BuildContext context) {
    final profile = WatchOSScreenProfile.forSize(watchSize);
    final baseMedia = MediaQuery.maybeOf(context) ?? const MediaQueryData();

    final screen = SizedBox(
      width: profile.width,
      height: profile.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(profile.cornerRadius),
        child: WatchOSPreviewScope(
          profile: profile,
          child: MediaQuery(
            data: baseMedia.copyWith(
              size: profile.size,
              devicePixelRatio: profile.pixelRatio,
              padding: profile.safePadding,
              viewPadding: profile.safePadding,
            ),
            child: child,
          ),
        ),
      ),
    );

    if (!showBezel) {
      return screen;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1D),
            borderRadius: BorderRadius.circular(profile.cornerRadius + 10),
            border: Border.all(
              color: const Color(0xFF3A3A3F),
              width: 2,
            ),
          ),
          child: screen,
        ),
        Container(
          width: 6,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFF48484D),
            borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
          ),
        ),
      ],
    );
  }
}
