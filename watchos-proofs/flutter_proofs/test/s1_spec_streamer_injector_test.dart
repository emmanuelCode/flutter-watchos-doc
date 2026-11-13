// S1 — The REAL WatchFrameStreamer and WatchInputInjector, extracted verbatim from the spec
// (scripts/extract_spec_code.py writes them to lib/spec/). If this file does not even compile, the
// spec snippets are broken as written — that is the finding.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_proofs/spec/watch_frame_streamer.dart';
import 'package:flutter_proofs/spec/watch_input_injector.dart';
import 'package:flutter_test/flutter_test.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _blue = Color(0xFF0000FF);

class _Frame {
  _Frame(this.rgba, this.w, this.h, this.id);
  final Uint8List rgba;
  final int w, h, id;
  List<int> get centre {
    final i = ((h ~/ 2) * w + (w ~/ 2)) * 4;
    return [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]];
  }
}

void main() {
  testWidgets('real streamer captures frames; real injector tap changes the next frame', (tester) async {
    final key = GlobalKey();
    var taps = 0;
    final frames = <_Frame>[];

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

    final streamer = WatchFrameStreamer(
      boundaryKey: key,
      sink: (rgba, w, h, id) => frames.add(_Frame(Uint8List.fromList(rgba), w, h, id)),
    );
    expect(streamer.pixelRatio, 1.0, reason: 'v6 defaulted to 2.0 (4x the bytes) - must stay 1.0');
    streamer.start();

    // pump() only runs a frame if one is already scheduled. The streamer registered AFTER the first
    // frame, and an idle app schedules none - so nothing would ever fire it. (The same happens in
    // real life when a watch connects to an idle app: see the spec note on sending the current frame.)
    // ignore: avoid_print
    print('S1: hasScheduledFrame right after start() = ${tester.binding.hasScheduledFrame}');
    tester.binding.scheduleFrame();

    // The streamer starts toImage from a frame callback, i.e. inside the fake-async test zone.
    // toImage completes on the REAL event loop, but the streamer's continuation waits in the FAKE
    // microtask queue — so alternate: pump (flushes fake microtasks) and a real-async wait.
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
    }

    await settle();
    // ignore: avoid_print
    print('S1: after first settle: frames=${frames.length}');
    expect(frames, isNotEmpty, reason: 'streamer produced no frame');
    expect([frames.last.w, frames.last.h], [800, 600]); // logical test surface at pixelRatio 1.0
    expect(frames.last.centre, [255, 0, 0, 255]);
    final before = frames.length;
    final lastId = frames.last.id;

    WatchInputInjector().tap(const Offset(400, 300)); // exactly the spec's injector, no viewId passed
    await settle();
    // ignore: avoid_print
    print('S1: after tap: taps=$taps frames=${frames.length}');

    expect(taps, 1, reason: 'the spec injector did not reach the GestureDetector');
    expect(frames.length, greaterThan(before));
    expect(frames.last.id, greaterThan(lastId));
    expect(frames.last.centre, [0, 255, 0, 255]);

    // ignore: avoid_print
    print('S1: ${frames.length} frames captured at ${frames.last.w}x${frames.last.h}');
  });

  testWidgets('stop() halts frame capture', (tester) async {
    final key = GlobalKey();
    var taps = 0;
    final frames = <_Frame>[];

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
    }

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

    final streamer = WatchFrameStreamer(
      boundaryKey: key,
      sink: (rgba, w, h, id) => frames.add(_Frame(Uint8List.fromList(rgba), w, h, id)),
    );
    streamer.start();
    tester.binding.scheduleFrame();
    await settle();
    expect(frames, isNotEmpty);

    streamer.stop();
    final countAtStop = frames.length;

    WatchInputInjector().tap(const Offset(400, 300));
    await settle();
    expect(taps, 1);
    expect(frames.length, countAtStop, reason: 'streamer emitted a frame after stop()');
  });

  testWidgets('coalesces invalidation that occurs while capture is in flight', (tester) async {
    final key = GlobalKey();
    var taps = 0;
    final frames = <_Frame>[];

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: StatefulBuilder(
            builder: (context, setState) => GestureDetector(
              onTap: () => setState(() => taps++),
              child: ColoredBox(color: taps == 0 ? _red : _blue, child: const SizedBox.expand()),
            ),
          ),
        ),
      ),
    );

    final streamer = WatchFrameStreamer(
      boundaryKey: key,
      sink: (rgba, w, h, id) => frames.add(_Frame(Uint8List.fromList(rgba), w, h, id)),
    );
    streamer.start();
    tester.binding.scheduleFrame();

    // First pump starts _capture() for the red frame (_captureInFlight becomes true while toImage awaits real async).
    await tester.pump();

    // Trigger a state change and pump immediately before runAsync lets the first toImage() resolve.
    WatchInputInjector().tap(const Offset(400, 300));
    await tester.pump();

    await settle();
    expect(taps, 1);
    expect(frames.length, greaterThanOrEqualTo(2), reason: 'mid-capture invalidation was dropped');
    expect(frames.last.centre, [0, 0, 255, 255], reason: 'final blue frame was dropped while capture was in flight');
  });
}
