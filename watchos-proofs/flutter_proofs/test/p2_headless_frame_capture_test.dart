// P2 — Can a stock Flutter app produce a frame with no window, and can we read it back as raw RGBA?
// Also checks the byte counts quoted in the spec's bandwidth table (4 bytes per pixel).
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RepaintBoundary.toImage returns real pixels with no window', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 198, // 45mm watch, logical points
              height: 242,
              child: ColoredBox(color: Color(0xFFFF0000)),
            ),
          ),
        ),
      ),
    );
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;

    for (final ratio in [1.0, 2.0]) {
      final sw = Stopwatch()..start();
      final result = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final out = (image.width, image.height, data!);
        image.dispose();
        return out;
      });
      sw.stop();
      final (w, h, data) = result!;

      expect(w, (198 * ratio).round());
      expect(h, (242 * ratio).round());
      expect(data.lengthInBytes, w * h * 4); // 191,664 at 1.0 / 766,656 at 2.0

      final i = ((h ~/ 2) * w + (w ~/ 2)) * 4; // centre pixel must be the red we painted
      expect(
        [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2), data.getUint8(i + 3)],
        [255, 0, 0, 255],
      );

      // ignore: avoid_print
      print('P2: pixelRatio $ratio -> ${data.lengthInBytes} bytes, ${sw.elapsedMilliseconds} ms');
    }
  });
}
