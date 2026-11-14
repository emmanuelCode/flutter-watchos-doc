import 'package:flutter/widgets.dart';

import 'hig_checker.dart';
import 'theme.dart';

/// Root widget for standalone Apple Watch apps (replaces MaterialApp / CupertinoApp).
class WatchOSApp extends StatelessWidget {
  const WatchOSApp({
    super.key,
    this.title = '',
    this.theme,
    this.home,
    this.routes = const <String, WidgetBuilder>{},
    this.initialRoute,
    this.onGenerateRoute,
    this.enableHigChecker = false,
    this.debugShowCheckedModeBanner = false,
  });

  final String title;
  final WatchOSThemeData? theme;
  final Widget? home;
  final Map<String, WidgetBuilder> routes;
  final String? initialRoute;
  final RouteFactory? onGenerateRoute;
  final bool enableHigChecker;
  final bool debugShowCheckedModeBanner;

  @override
  Widget build(BuildContext context) {
    final resolvedTheme = theme ?? const WatchOSThemeData();
    final previewProfile = WatchOSPreviewScope.maybeOf(context);

    return WidgetsApp(
      title: title,
      color: resolvedTheme.accentColor,
      home: home,
      routes: routes,
      initialRoute: initialRoute,
      onGenerateRoute: onGenerateRoute,
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (
            BuildContext routeContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            return ColoredBox(
              color: resolvedTheme.backgroundColor,
              child: builder(routeContext),
            );
          },
          transitionsBuilder: (
            BuildContext routeContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            return FadeTransition(opacity: animation, child: child);
          },
        );
      },
      builder: (BuildContext appContext, Widget? navigator) {
        Widget content = ColoredBox(
          color: resolvedTheme.backgroundColor,
          child: DefaultTextStyle(
            style: resolvedTheme.textTheme.body,
            child: navigator ?? const SizedBox.shrink(),
          ),
        );

        if (enableHigChecker) {
          content = WatchOSHigChecker(
            minTouchTarget: resolvedTheme.minTouchTarget,
            child: content,
          );
        }

        content = WatchOSTheme(
          data: resolvedTheme,
          child: content,
        );

        if (previewProfile != null) {
          content = MediaQuery(
            data: MediaQuery.of(appContext).copyWith(
              size: previewProfile.size,
              devicePixelRatio: previewProfile.pixelRatio,
              padding: previewProfile.safePadding,
              viewPadding: previewProfile.safePadding,
            ),
            child: content,
          );
        }

        return content;
      },
    );
  }
}
