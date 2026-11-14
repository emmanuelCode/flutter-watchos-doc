# watchos_ui (v0.1 proof of concept)

Minimal, standalone Flutter widget layer targeting Apple Watch HIG—built strictly on `package:flutter/widgets.dart` with **zero `material` or `cupertino` dependencies**.

This package is **Layer 1** of the architecture in `../../flutter_watchos_architecture.md`: it runs on stock Flutter (Linux, Windows, macOS, Web, and `flutter test`) and is decoupled from the watchOS embedder runtime underneath.

## Included in v0.1

- `WatchOSSize` / `WatchOSScreenProfile` (40, 41, 42, 44, 45, 46, and 49 mm display presets)
- `WatchOSApp` + `WatchOSTheme` / `WatchOSThemeData` / `WatchOSTextTheme`
- `WatchOSButton` (enforces minimum 44x44 pt hit target, press scale, `Semantics`, `onHaptic` hook)
- `WatchOSPageScaffold`, `WatchOSListScaffold`, and `WatchOSScrollPhysics`
- `WatchOSProgressRing` (`CustomPainter` activity ring)
- `WatchOSHigChecker` (debug render-tree check for small touch targets and horizontal overflow) + `WatchOSPreviewFrame`

## Run tests & example

    cd packages/watchos_ui
    flutter pub get
    flutter analyze
    flutter test

    cd example
    flutter pub get
    flutter run
