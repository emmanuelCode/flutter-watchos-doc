// P3 — The watch sends a tap; we replay it through GestureBinding (same calls as WatchInputInjector).
// Proves: injected pointer events reach a GestureDetector, setState runs, and the next frame differs.
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);

void main() {
  testWidgets('a tap injected via GestureBinding changes the next captured frame', (tester) async {
    final key = GlobalKey();
    var taps = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: StatefulBuilder(
            builder: (context, setState) => GestureDetector(
              onTap: () => setState(() => taps++),
              child: ColoredBox(color: taps == 0 ? _red : _green, child: const SizedBox.expand()),
            ),
          ),
        ),
      ),
    );

    Future<List<int>> centrePixel() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final r = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final i = ((image.height ~/ 2) * image.width + (image.width ~/ 2)) * 4;
        image.dispose();
        return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2), data.getUint8(i + 3)];
      });
      return r!;
    }

    expect(await centrePixel(), [255, 0, 0, 255]); // before: red

    // --- what WatchInputInjector.tap() does ---
    final binding = GestureBinding.instance;
    const pos = Offset(400, 300); // centre of the 800x600 logical test surface
    final view = tester.view.viewId;
    binding.handlePointerEvent(PointerDownEvent(pointer: 1, position: pos, viewId: view));
    binding.handlePointerEvent(PointerUpEvent(pointer: 1, position: pos, viewId: view));
    await tester.pump();

    expect(taps, 1);
    expect(await centrePixel(), [0, 255, 0, 255]); // after: green
  });
}
