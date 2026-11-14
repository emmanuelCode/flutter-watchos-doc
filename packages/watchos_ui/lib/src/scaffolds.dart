import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Scroll physics tuned for Apple Watch rotary / Digital Crown list scrolling.
class WatchOSScrollPhysics extends BouncingScrollPhysics {
  const WatchOSScrollPhysics({super.parent});

  @override
  WatchOSScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return WatchOSScrollPhysics(parent: buildParent(ancestor));
  }
}

/// Paged container mirroring watchOS TabView navigation (vertical by default on watchOS 10+).
class WatchOSPageScaffold extends StatefulWidget {
  const WatchOSPageScaffold({
    super.key,
    required this.pages,
    this.scrollDirection = Axis.vertical,
    this.showPageIndicator = true,
    this.controller,
    this.backgroundColor,
    this.onPageChanged,
  });

  final List<Widget> pages;
  final Axis scrollDirection;
  final bool showPageIndicator;
  final PageController? controller;
  final Color? backgroundColor;
  final ValueChanged<int>? onPageChanged;

  @override
  State<WatchOSPageScaffold> createState() => _WatchOSPageScaffoldState();
}

class _WatchOSPageScaffoldState extends State<WatchOSPageScaffold> {
  late PageController _controller;
  late bool _ownsController;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? PageController();
    _pageIndex = _controller.initialPage;
  }

  @override
  void didUpdateWidget(WatchOSPageScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? PageController();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = WatchOSTheme.of(context);
    final bg = widget.backgroundColor ?? theme.backgroundColor;

    return ColoredBox(
      color: bg,
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _controller,
            scrollDirection: widget.scrollDirection,
            physics: const WatchOSScrollPhysics(),
            itemCount: widget.pages.length,
            onPageChanged: (int index) {
              setState(() => _pageIndex = index);
              widget.onPageChanged?.call(index);
            },
            itemBuilder: (BuildContext context, int index) {
              return SafeArea(child: widget.pages[index]);
            },
          ),
          if (widget.showPageIndicator && widget.pages.length > 1)
            _buildIndicator(theme),
        ],
      ),
    );
  }

  Widget _buildIndicator(WatchOSThemeData theme) {
    final isVertical = widget.scrollDirection == Axis.vertical;
    final dots = List<Widget>.generate(widget.pages.length, (int i) {
      final active = i == _pageIndex;
      return Container(
        width: 5,
        height: 5,
        margin: EdgeInsets.symmetric(
          vertical: isVertical ? 2.5 : 0,
          horizontal: isVertical ? 0 : 2.5,
        ),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? theme.foregroundColor
              : theme.foregroundColor.withValues(alpha: 0.3),
        ),
      );
    });

    if (isVertical) {
      return Positioned(
        right: 4,
        top: 0,
        bottom: 0,
        child: IgnorePointer(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: dots,
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 4,
      child: IgnorePointer(
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: dots,
          ),
        ),
      ),
    );
  }
}

/// Vertical scrollable list tuned for Apple Watch safe areas and Crown scrolling.
class WatchOSListScaffold extends StatelessWidget {
  const WatchOSListScaffold({
    super.key,
    required this.children,
    this.header,
    this.controller,
    this.physics,
    this.padding,
    this.backgroundColor,
    this.itemSpacing = 8.0,
  });

  final List<Widget> children;
  final Widget? header;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double itemSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = WatchOSTheme.of(context);
    final bg = backgroundColor ?? theme.backgroundColor;

    final items = <Widget>[
      if (header != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DefaultTextStyle.merge(
            style: theme.textTheme.title,
            child: header!,
          ),
        ),
      for (int i = 0; i < children.length; i++) ...<Widget>[
        children[i],
        if (i < children.length - 1) SizedBox(height: itemSpacing),
      ],
    ];

    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: ListView(
          controller: controller,
          physics: physics ?? const WatchOSScrollPhysics(),
          padding: padding ?? const EdgeInsets.fromLTRB(6, 4, 6, 24),
          children: items,
        ),
      ),
    );
  }
}
