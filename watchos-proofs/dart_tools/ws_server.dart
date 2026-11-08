// Tiny stand-in for the Mac-side "WatchFrameStreamer" transport.
// On connect: sends one binary frame (198x242 RGBA, solid red = one 45mm frame at pixelRatio 1.0).
// On text "tap:x,y": replies "tapped:x,y".
import 'dart:io';
import 'dart:typed_data';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
  print('ws_server listening on 127.0.0.1:8765');

  await for (final req in server) {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = 400;
      await req.response.close();
      continue;
    }
    final ws = await WebSocketTransformer.upgrade(req);

    final frame = Uint8List(198 * 242 * 4);
    for (var i = 0; i < frame.length; i += 4) {
      frame[i] = 255; // R
      frame[i + 3] = 255; // A
    }
    ws.add(frame); // binary message

    ws.listen((msg) {
      if (msg is String && msg.startsWith('tap:')) {
        ws.add('tapped:${msg.substring(4)}');
      }
    });
  }
}
