// P9 — streams N frames so the client can measure sustained transport.
//   ws://127.0.0.1:8766/?ratio=1|2&mode=raw|zlib|delta&frames=100
// Message = [uint32 little-endian frame index][payload]
//   raw   : payload = full RGBA frame
//   zlib  : payload = raw-deflate(full frame)            (Apple's COMPRESSION_ZLIB decodes raw deflate)
//   delta : payload = raw-deflate(frame XOR previous)    (previous = zeros for frame 0)
// All payloads are built BEFORE the first send, so the client's timing excludes server compute.
import 'dart:io';
import 'dart:typed_data';

/// Mostly-black "watch UI": static header bar + grey row + a small white square that moves 3 px per frame.
/// (Optimistic for compression: most pixels never change. Real UIs will compress worse.)
Uint8List makeFrame(int w, int h, int i) {
  final f = Uint8List(w * h * 4);
  for (var p = 3; p < f.length; p += 4) {
    f[p] = 255; // opaque
  }
  void fill(int x0, int y0, int rw, int rh, int r, int g, int b) {
    for (var y = y0; y < y0 + rh; y++) {
      for (var x = x0; x < x0 + rw; x++) {
        final k = (y * w + x) * 4;
        f[k] = r;
        f[k + 1] = g;
        f[k + 2] = b;
      }
    }
  }

  fill(0, 0, w, h ~/ 10, 0, 90, 255);
  fill(w ~/ 10, h ~/ 5, w * 8 ~/ 10, h ~/ 20, 40, 40, 40);
  final s = w ~/ 20;
  final x = (i * 3) % (w - s);
  fill(x, h ~/ 2, s, s, 255, 255, 255);
  return f;
}

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8766);
  print('ws_stream_server listening on 127.0.0.1:8766');

  await for (final req in server) {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = 400;
      await req.response.close();
      continue;
    }
    final q = req.uri.queryParameters;
    final ratio = int.parse(q['ratio'] ?? '1');
    final mode = q['mode'] ?? 'raw';
    final frames = int.parse(q['frames'] ?? '100');
    final ws = await WebSocketTransformer.upgrade(req);

    final w = 198 * ratio, h = 242 * ratio;
    final codec = ZLibCodec(raw: true, level: 1);
    var prev = Uint8List(w * h * 4);
    final messages = <Uint8List>[];

    for (var i = 0; i < frames; i++) {
      final frame = makeFrame(w, h, i);
      late final Uint8List payload;
      if (mode == 'raw') {
        payload = frame;
      } else if (mode == 'zlib') {
        payload = Uint8List.fromList(codec.encode(frame));
      } else if (mode == 'delta') {
        final diff = Uint8List(frame.length);
        for (var k = 0; k < frame.length; k++) {
          diff[k] = frame[k] ^ prev[k];
        }
        payload = Uint8List.fromList(codec.encode(diff));
        prev = frame;
      } else {
        throw ArgumentError('unknown mode $mode');
      }
      final msg = Uint8List(4 + payload.length);
      ByteData.sublistView(msg).setUint32(0, i, Endian.little);
      msg.setRange(4, msg.length, payload);
      messages.add(msg);
    }

    for (final m in messages) {
      ws.add(m);
    }
  }
}
