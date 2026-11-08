// S7 — captureNow(): an IDLE app produces no frames, so a client that connects late needs the
// current frame on demand. Checks both halves: (1) idle => nothing arrives by itself,
// (2) captureNow() pushes the current frame. Uses the spec's real WatchFrameStreamer.
import 'package:flutter/widgets.dart';
import 'package:flutter_proofs/spec/watch_frame_streamer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captureNow pushes the current frame from an idle app', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: const ColoredBox(color: Color(0xFFFF0000), child: SizedBox.expand()),
        ),
      ),
    );

    final received = <List<int>>[]; // [width, height, centre r, g, b, a]
    final streamer = WatchFrameStreamer(
      boundaryKey: key,
      sink: (rgba, w, h, id) {
        final i = ((h ~/ 2) * w + (w ~/ 2)) * 4;
        received.add([w, h, rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]]);
      },
    );
    streamer.start();

    // (1) Idle app: nothing is scheduled, so nothing is captured on its own.
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    }
    // ignore: avoid_print
    print('S7: idle app, frames received by itself = ${received.length}');
    expect(received, isEmpty, reason: 'an idle app should produce no frames (this is the gap captureNow fills)');

    // (2) A client connects -> captureNow() pushes the current frame.
    await tester.runAsync(() => streamer.captureNow());
    // ignore: avoid_print
    print('S7: after captureNow frames received = ${received.length}');
    expect(received, hasLength(1));
    expect(received.single, [800, 600, 255, 0, 0, 255]);
  });
}
