import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchos_ui/watchos_ui.dart';

void main() {
  test('screen profiles cover all 7 watch sizes with positive dimensions', () {
    expect(WatchOSScreenProfile.all, hasLength(7));
    for (final p in WatchOSScreenProfile.all) {
      expect(p.width, greaterThan(150));
      expect(p.height, greaterThan(180));
      expect(p.pixelRatio, 2.0);
    }
    expect(WatchOSScreenProfile.mm40.size, const Size(162, 197));
    expect(WatchOSScreenProfile.mm44.size, const Size(184, 224));
    expect(WatchOSScreenProfile.mm46.size, const Size(208, 248));
  });

  testWidgets('WatchOSApp sets pure black background and theme without Material', (WidgetTester tester) async {
    late WatchOSThemeData capturedTheme;
    late TextStyle capturedTextStyle;

    await tester.pumpWidget(
      WatchOSApp(
        home: Builder(
          builder: (BuildContext context) {
            capturedTheme = WatchOSTheme.of(context);
            capturedTextStyle = DefaultTextStyle.of(context).style;
            return const Center(child: Text('BPM'));
          },
        ),
      ),
    );

    expect(capturedTheme.backgroundColor, const Color(0xFF000000));
    expect(capturedTheme.minTouchTarget, 44.0);
    expect(capturedTextStyle.fontSize, 16.0);
    expect(find.text('BPM'), findsOneWidget);
  });

  testWidgets('WatchOSButton enforces 44x44 minimum hit target and fires callbacks', (WidgetTester tester) async {
    var taps = 0;
    var haptics = 0;

    await tester.pumpWidget(
      WatchOSApp(
        home: Center(
          child: WatchOSButton(
            onHaptic: () => haptics++,
            onPressed: () => taps++,
            padding: EdgeInsets.zero,
            child: const SizedBox(width: 8, height: 8),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(WatchOSButton));
    expect(size.width, greaterThanOrEqualTo(44.0));
    expect(size.height, greaterThanOrEqualTo(44.0));

    await tester.tap(find.byType(WatchOSButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(haptics, 1);
  });

  testWidgets('disabled WatchOSButton ignores taps', (WidgetTester tester) async {
    var haptics = 0;

    await tester.pumpWidget(
      WatchOSApp(
        home: Center(
          child: WatchOSButton(
            onHaptic: () => haptics++,
            onPressed: null,
            child: const Text('Disabled'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(WatchOSButton));
    await tester.pumpAndSettle();
    expect(haptics, 0);
  });

  testWidgets('WatchOSPageScaffold pages vertically and updates indicator', (WidgetTester tester) async {
    var latestPage = 0;

    await tester.pumpWidget(
      WatchOSApp(
        home: WatchOSPageScaffold(
          onPageChanged: (int idx) => latestPage = idx,
          pages: const <Widget>[
            Center(child: Text('Page 1')),
            Center(child: Text('Page 2')),
          ],
        ),
      ),
    );

    expect(find.text('Page 1'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(latestPage, 1);
    expect(find.text('Page 2'), findsOneWidget);
  });

  testWidgets('WatchOSListScaffold renders header and scrolls items', (WidgetTester tester) async {
    await tester.pumpWidget(
      WatchOSPreviewFrame(
        watchSize: WatchOSSize.mm45,
        child: WatchOSApp(
          home: WatchOSListScaffold(
            header: const Text('Workouts'),
            children: List<Widget>.generate(
              10,
              (int i) => WatchOSButton(
                onPressed: () {},
                child: Text('Item $i'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('Item 0'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Item 9'), findsOneWidget);
  });

  testWidgets('WatchOSProgressRing renders and clamps out-of-range values', (WidgetTester tester) async {
    await tester.pumpWidget(
      const WatchOSApp(
        home: Center(
          child: WatchOSProgressRing(
            progress: 1.5,
            child: Text('Done'),
          ),
        ),
      ),
    );

    expect(find.text('Done'), findsOneWidget);
    final sem = tester.getSemantics(find.byType(WatchOSProgressRing));
    expect(sem.value, '100%');
  });

  testWidgets('WatchOSHigChecker flags small touch target and horizontal overflow', (WidgetTester tester) async {
    var violations = <WatchOSHigViolation>[];

    await tester.pumpWidget(
      WatchOSPreviewFrame(
        watchSize: WatchOSSize.mm40,
        showBezel: false,
        child: WatchOSApp(
          home: WatchOSHigChecker(
            onViolations: (List<WatchOSHigViolation> v) => violations = v,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                GestureDetector(
                  onTap: () {},
                  child: const SizedBox(width: 20, height: 20),
                ),
                const SizedBox(
                  width: 162,
                  height: 10,
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 240,
                    maxWidth: 240,
                    minHeight: 10,
                    maxHeight: 10,
                    child: SizedBox(width: 240, height: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(violations.any((WatchOSHigViolation v) => v.category == 'touchTarget'), isTrue);
    expect(violations.any((WatchOSHigViolation v) => v.category == 'overflow'), isTrue);
    expect(find.textContaining('HIG:'), findsOneWidget);
  });

  testWidgets('WatchOSPreviewFrame propagates watch MediaQuery size inside WatchOSApp', (WidgetTester tester) async {
    late Size capturedSize;

    await tester.pumpWidget(
      WatchOSPreviewFrame(
        watchSize: WatchOSSize.mm46,
        child: WatchOSApp(
          home: Builder(
            builder: (BuildContext context) {
              capturedSize = MediaQuery.sizeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(capturedSize, const Size(208, 248));
  });

  test('WatchOSHigConfig defaults match current behavior and opt-in rules are off', () {
    const config = WatchOSHigConfig();
    expect(config.minTouchTarget, 44.0);
    expect(config.minFontSize, 14.0);
    expect(config.maxFontSize, 34.0);
    expect(config.pureBlackColor, const Color(0xFF000000));
    expect(config.checkOverflow, isTrue);
    expect(config.checkTouchTarget, isTrue);
    expect(config.checkFontSize, isFalse);
    expect(config.checkPureBlack, isFalse);

    final updated = config.copyWith(minTouchTarget: 48.0, checkFontSize: true);
    expect(updated.minTouchTarget, 48.0);
    expect(updated.checkFontSize, isTrue);
    expect(updated, isNot(config));
  });

  testWidgets('WatchOSHigChecker ignores font-size and pure-black violations by default', (WidgetTester tester) async {
    var violations = <WatchOSHigViolation>[];

    await tester.pumpWidget(
      WatchOSApp(
        home: WatchOSHigChecker(
          onViolations: (List<WatchOSHigViolation> v) => violations = v,
          child: const ColoredBox(
            color: Color(0xFF1C1C1E),
            child: Column(
              children: <Widget>[
                Text('TooSmall', style: TextStyle(fontSize: 10)),
                Text('TooLarge', style: TextStyle(fontSize: 40)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(violations, isEmpty);
  });

  testWidgets('WatchOSHigChecker enforces configurable minTouchTarget and checkOverflow', (WidgetTester tester) async {
    var violations = <WatchOSHigViolation>[];

    await tester.pumpWidget(
      WatchOSApp(
        home: WatchOSHigChecker(
          config: const WatchOSHigConfig(minTouchTarget: 50.0, checkOverflow: false),
          onViolations: (List<WatchOSHigViolation> v) => violations = v,
          child: GestureDetector(
            onTap: () {},
            child: const SizedBox(width: 44, height: 44),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(violations.any((WatchOSHigViolation v) => v.category == 'touchTarget'), isTrue);
    expect(violations.any((WatchOSHigViolation v) => v.category == 'overflow'), isFalse);
  });

  testWidgets('WatchOSHigChecker opt-in font-size rule flags outside bounds and honors custom bounds', (WidgetTester tester) async {
    var violations = <WatchOSHigViolation>[];

    await tester.pumpWidget(
      WatchOSApp(
        home: WatchOSHigChecker(
          config: const WatchOSHigConfig(checkFontSize: true),
          onViolations: (List<WatchOSHigViolation> v) => violations = v,
          child: const Column(
            children: <Widget>[
              Text('Small', style: TextStyle(fontSize: 10)),
              Text('Huge', style: TextStyle(fontSize: 40)),
              Text('Body', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final fontViolations = violations.where((WatchOSHigViolation v) => v.category == 'fontSize').toList();
    expect(fontViolations, hasLength(2));
    expect(fontViolations.every((WatchOSHigViolation v) => v.severity == WatchOSHigViolationSeverity.warning), isTrue);

    violations = <WatchOSHigViolation>[];
    await tester.pumpWidget(
      WatchOSApp(
        home: WatchOSHigChecker(
          config: const WatchOSHigConfig(checkFontSize: true, minFontSize: 10.0, maxFontSize: 42.0),
          onViolations: (List<WatchOSHigViolation> v) => violations = v,
          child: const Column(
            children: <Widget>[
              Text('Small', style: TextStyle(fontSize: 10)),
              Text('Huge', style: TextStyle(fontSize: 40)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(violations, isEmpty);
  });

  testWidgets('WatchOSHigChecker opt-in pure-black rule flags off-black screen backgrounds only', (WidgetTester tester) async {
    var violations = <WatchOSHigViolation>[];

    await tester.pumpWidget(
      const WatchOSPreviewFrame(
        watchSize: WatchOSSize.mm40,
        showBezel: false,
        child: WatchOSApp(
          enableHigChecker: true,
          higConfig: WatchOSHigConfig(checkPureBlack: true),
          theme: WatchOSThemeData(backgroundColor: Color(0xFF121212)),
          home: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('HIG:'), findsOneWidget);

    await tester.pumpWidget(
      WatchOSApp(
        home: WatchOSHigChecker(
          config: const WatchOSHigConfig(checkPureBlack: true),
          onViolations: (List<WatchOSHigViolation> v) => violations = v,
          child: ColoredBox(
            color: const Color(0xFF000000),
            child: Center(
              child: Container(
                width: 80,
                height: 48,
                color: const Color(0xFF1C1C1E),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(violations, isEmpty);
  });
}
