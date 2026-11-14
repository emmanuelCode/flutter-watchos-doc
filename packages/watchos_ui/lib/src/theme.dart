import 'package:flutter/widgets.dart';

/// Typography tokens tuned for 40-49 mm watch displays.
@immutable
class WatchOSTextTheme {
  const WatchOSTextTheme({
    this.display = const TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.1,
      color: Color(0xFFFFFFFF),
      letterSpacing: -0.5,
    ),
    this.title = const TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: Color(0xFFFFFFFF),
    ),
    this.body = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.25,
      color: Color(0xFFFFFFFF),
    ),
    this.caption = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: Color(0xFFAEAEB2),
    ),
  });

  final TextStyle display;
  final TextStyle title;
  final TextStyle body;
  final TextStyle caption;

  WatchOSTextTheme copyWith({
    TextStyle? display,
    TextStyle? title,
    TextStyle? body,
    TextStyle? caption,
  }) {
    return WatchOSTextTheme(
      display: display ?? this.display,
      title: title ?? this.title,
      body: body ?? this.body,
      caption: caption ?? this.caption,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WatchOSTextTheme &&
            other.display == display &&
            other.title == title &&
            other.body == body &&
            other.caption == caption;
  }

  @override
  int get hashCode => Object.hash(display, title, body, caption);
}

/// Visual tokens for a watchOS app. Defaults to pure black (#000000) for OLED efficiency.
@immutable
class WatchOSThemeData {
  const WatchOSThemeData({
    this.backgroundColor = const Color(0xFF000000),
    this.surfaceColor = const Color(0xFF1C1C1E),
    this.accentColor = const Color(0xFF0A84FF),
    this.foregroundColor = const Color(0xFFFFFFFF),
    this.secondaryForegroundColor = const Color(0xFFAEAEB2),
    this.minTouchTarget = 44.0,
    this.textTheme = const WatchOSTextTheme(),
  });

  final Color backgroundColor;
  final Color surfaceColor;
  final Color accentColor;
  final Color foregroundColor;
  final Color secondaryForegroundColor;
  final double minTouchTarget;
  final WatchOSTextTheme textTheme;

  WatchOSThemeData copyWith({
    Color? backgroundColor,
    Color? surfaceColor,
    Color? accentColor,
    Color? foregroundColor,
    Color? secondaryForegroundColor,
    double? minTouchTarget,
    WatchOSTextTheme? textTheme,
  }) {
    return WatchOSThemeData(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      accentColor: accentColor ?? this.accentColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      secondaryForegroundColor:
          secondaryForegroundColor ?? this.secondaryForegroundColor,
      minTouchTarget: minTouchTarget ?? this.minTouchTarget,
      textTheme: textTheme ?? this.textTheme,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WatchOSThemeData &&
            other.backgroundColor == backgroundColor &&
            other.surfaceColor == surfaceColor &&
            other.accentColor == accentColor &&
            other.foregroundColor == foregroundColor &&
            other.secondaryForegroundColor == secondaryForegroundColor &&
            other.minTouchTarget == minTouchTarget &&
            other.textTheme == textTheme;
  }

  @override
  int get hashCode => Object.hash(
        backgroundColor,
        surfaceColor,
        accentColor,
        foregroundColor,
        secondaryForegroundColor,
        minTouchTarget,
        textTheme,
      );
}

/// Propagates [WatchOSThemeData] down the widget tree.
class WatchOSTheme extends InheritedWidget {
  const WatchOSTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final WatchOSThemeData data;

  static WatchOSThemeData of(BuildContext context) {
    return maybeOf(context) ?? const WatchOSThemeData();
  }

  static WatchOSThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WatchOSTheme>()?.data;
  }

  @override
  bool updateShouldNotify(WatchOSTheme oldWidget) => data != oldWidget.data;
}
