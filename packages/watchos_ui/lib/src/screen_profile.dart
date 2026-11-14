import 'package:flutter/widgets.dart';

/// Supported Apple Watch case sizes (watchOS 27+ arm64 floor plus current sizes).
enum WatchOSSize {
  mm40,
  mm41,
  mm42,
  mm44,
  mm45,
  mm46,
  mm49,
}

/// Logical screen geometry and HIG layout limits for an Apple Watch display.
@immutable
class WatchOSScreenProfile {
  const WatchOSScreenProfile({
    required this.watchSize,
    required this.label,
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.cornerRadius,
    required this.safePadding,
    this.crownExclusionWidth = 10.0,
  });

  final WatchOSSize watchSize;
  final String label;
  final double width;
  final double height;
  final double pixelRatio;
  final double cornerRadius;
  final EdgeInsets safePadding;
  final double crownExclusionWidth;

  Size get size => Size(width, height);

  static const WatchOSScreenProfile mm40 = WatchOSScreenProfile(
    watchSize: WatchOSSize.mm40,
    label: '40 mm (SE 3)',
    width: 162,
    height: 197,
    pixelRatio: 2.0,
    cornerRadius: 34,
    safePadding: EdgeInsets.fromLTRB(8, 20, 8, 12),
  );

  static const WatchOSScreenProfile mm41 = WatchOSScreenProfile(
    watchSize: WatchOSSize.mm41,
    label: '41 mm',
    width: 176,
    height: 215,
    pixelRatio: 2.0,
    cornerRadius: 38,
    safePadding: EdgeInsets.fromLTRB(8, 22, 8, 12),
  );

  static const WatchOSScreenProfile mm42 = WatchOSScreenProfile(
    watchSize: WatchOSSize.mm42,
    label: '42 mm',
    width: 187,
    height: 223,
    pixelRatio: 2.0,
    cornerRadius: 40,
    safePadding: EdgeInsets.fromLTRB(8, 22, 8, 12),
  );

  static const WatchOSScreenProfile mm44 = WatchOSScreenProfile(
    watchSize: WatchOSSize.mm44,
    label: '44 mm (SE 3)',
    width: 184,
    height: 224,
    pixelRatio: 2.0,
    cornerRadius: 38,
    safePadding: EdgeInsets.fromLTRB(8, 22, 8, 12),
  );

  static const WatchOSScreenProfile mm45 = WatchOSScreenProfile(
    watchSize: WatchOSSize.mm45,
    label: '45 mm',
    width: 198,
    height: 242,
    pixelRatio: 2.0,
    cornerRadius: 42,
    safePadding: EdgeInsets.fromLTRB(10, 24, 10, 14),
  );

  static const WatchOSScreenProfile mm46 = WatchOSScreenProfile(
    watchSize: WatchOSSize.mm46,
    label: '46 mm',
    width: 208,
    height: 248,
    pixelRatio: 2.0,
    cornerRadius: 44,
    safePadding: EdgeInsets.fromLTRB(10, 24, 10, 14),
  );

  static const WatchOSScreenProfile mm49 = WatchOSScreenProfile(
    watchSize: WatchOSSize.mm49,
    label: '49 mm (Ultra)',
    width: 205,
    height: 251,
    pixelRatio: 2.0,
    cornerRadius: 46,
    safePadding: EdgeInsets.fromLTRB(10, 24, 10, 14),
  );

  static const List<WatchOSScreenProfile> all = <WatchOSScreenProfile>[
    mm40,
    mm41,
    mm42,
    mm44,
    mm45,
    mm46,
    mm49,
  ];

  static WatchOSScreenProfile forSize(WatchOSSize size) {
    return switch (size) {
      WatchOSSize.mm40 => mm40,
      WatchOSSize.mm41 => mm41,
      WatchOSSize.mm42 => mm42,
      WatchOSSize.mm44 => mm44,
      WatchOSSize.mm45 => mm45,
      WatchOSSize.mm46 => mm46,
      WatchOSSize.mm49 => mm49,
    };
  }
}
