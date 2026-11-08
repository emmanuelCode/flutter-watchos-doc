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

    // Run a frame in the real-async zone so toImage can complete, then give the capture time to finish.
    Future<void> settle() async {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
    }

    await settle();
    expect(frames, isNotEmpty, reason: 'streamer produced no frame');
    expect([frames.last.w, frames.last.h], [800, 600]); // logical test surface at pixelRatio 1.0
    expect(frames.last.centre, [255, 0, 0, 255]);
    final before = frames.length;
    final lastId = frames.last.id;

    WatchInputInjector().tap(const Offset(400, 300)); // exactly the spec's injector, no viewId passed
    await settle();

    expect(taps, 1, reason: 'the spec injector did not reach the GestureDetector');
    expect(frames.length, greaterThan(before));
    expect(frames.last.id, greaterThan(lastId));
    expect(frames.last.centre, [0, 255, 0, 255]);

    // ignore: avoid_print
    print('S1: ${frames.length} frames captured at ${frames.last.w}x${frames.last.h}');
  });
}
