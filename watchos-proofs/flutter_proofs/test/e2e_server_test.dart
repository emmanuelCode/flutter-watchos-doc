// E1 (Mac side) — the real WatchFrameStreamer + WatchInputInjector behind a real WebSocket.
// `flutter test` plays the dev machine; the watchOS client test (E1_EndToEndTests.swift) plays the watch.
//
//   watch connects        -> server calls streamer.captureNow()   -> frame goes down
//   watch sends "tap:x,y" -> server maps it into app coordinates  -> WatchInputInjector.tap(...)
//                         -> app state changes -> streamer captures the next frame -> frame goes down
//   watch sends "done"    -> test ends
//
// Frame message = [uint32 LE width][uint32 LE height][uint32 LE frameId][raw RGBA]
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_proofs/spec/watch_frame_streamer.dart';
import 'package:flutter_proofs/spec/watch_input_injector.dart';
import 'package:flutter_test/flutter_test.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);

void main() {
  testWidgets(
    'E1 server: real streamer + injector behind a WebSocket',
    (tester) async {
      final boundaryKey = GlobalKey();
      final screenKey = GlobalKey();
      var taps = 0;

      // A 198x242 "watch screen" (45mm, logical points) in the middle of the test surface. Tap = red -> green.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                key: screenKey,
                width: 198,
                height: 242,
                child: StatefulBuilder(
                  builder: (context, setState) => GestureDetector(
                    onTap: () => setState(() => taps++),
                    child: ColoredBox(color: taps == 0 ? _red : _green, child: const SizedBox.expand()),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final screenOrigin = tester.getTopLeft(find.byKey(screenKey));

      // Frames the streamer produces wait here until the loop below sends them.
      final outgoing = <Uint8List>[];
      final streamer = WatchFrameStreamer(
        boundaryKey: boundaryKey,
        sink: (rgba, w, h, id) {
          final msg = Uint8List(12 + rgba.length);
          final header = ByteData.sublistView(msg);
          header.setUint32(0, w, Endian.little);
          header.setUint32(4, h, Endian.little);
          header.setUint32(8, id, Endian.little);
          msg.setRange(12, msg.length, rgba);
          outgoing.add(msg);
        },
      )..start();
      final injector = WatchInputInjector();

      WebSocket? client;
      var done = false;
      final pendingTaps = <Offset>[];

      // Real I/O must be set up in the real-async zone.
      final server = await tester.runAsync(() async {
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 8767);
        s.listen((req) async {
          if (!WebSocketTransformer.isUpgradeRequest(req)) {
            req.response.statusCode = 400;
            await req.response.close();
            return;
          }
          final ws = await WebSocketTransformer.upgrade(req);
          client = ws;
          ws.listen((msg) {
            if (msg is String && msg.startsWith('tap:')) {
              final p = msg.substring(4).split(',');
              pendingTaps.add(Offset(double.parse(p[0]), double.parse(p[1])));
            } else if (msg == 'done') {
              done = true;
            }
          });
        });
        return s;
      });

      var greeted = false;
      var framesSent = 0;
      var tapsHandled = 0;
      final deadline = DateTime.now().add(const Duration(seconds: 150));

      while (!done && DateTime.now().isBefore(deadline)) {
        await tester.pump(); // runs a frame if one is scheduled; flushes fake-async continuations
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));

        if (client != null && !greeted) {
          greeted = true; // a watch just connected: an idle app would send nothing, so push the current frame
          await tester.runAsync(() => streamer.captureNow());
        }

        while (pendingTaps.isNotEmpty) {
          final watchPoint = pendingTaps.removeAt(0); // watch-screen coordinates
          injector.tap(screenOrigin + watchPoint); //    -> app coordinates
          tapsHandled++;
        }

        final c = client;
        if (c != null && outgoing.isNotEmpty) {
          final batch = List<Uint8List>.of(outgoing);
          outgoing.clear();
          await tester.runAsync(() async {
            for (final m in batch) {
              c.add(m);
            }
          });
          framesSent += batch.length;
        }
      }

      // ignore: avoid_print
      print('E1: server sent $framesSent frames, handled $tapsHandled tap(s), app state taps=$taps');
      await tester.runAsync(() async {
        await client?.close();
        await server?.close(force: true);
      });

      expect(done, isTrue, reason: 'the watch client never finished within 150 s');
      expect(taps, 1, reason: 'the tap sent from the watch did not reach the app');
      expect(framesSent, greaterThanOrEqualTo(2), reason: 'expected at least the connect frame and the post-tap frame');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
