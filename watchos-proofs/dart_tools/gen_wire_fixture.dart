// Writes the Appendix A wire format exactly as ZeroCopyCanvas would (host endianness,
// 4-byte padding) into /tmp/watch_fixture/frame.bin. The Swift test must parse it back.
//   rect(24) + text "Hé" (28 + 3 bytes + 1 pad = 32) + rect(24) = 80 bytes
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main() {
  final buf = ByteData(256);
  var o = 0;

  void rect(double x, double y, double w, double h, int argb) {
    buf.setUint32(o, 1, Endian.host);
    buf.setFloat32(o + 4, x, Endian.host);
    buf.setFloat32(o + 8, y, Endian.host);
    buf.setFloat32(o + 12, w, Endian.host);
    buf.setFloat32(o + 16, h, Endian.host);
    buf.setUint32(o + 20, argb, Endian.host);
    o += 24;
  }

  void text(double x, double y, String s, double size, int argb, int flags) {
    final bytes = utf8.encode(s);
    final raw = 28 + bytes.length;
    final pad = (4 - raw % 4) % 4;
    buf.setUint32(o, 3, Endian.host);
    buf.setFloat32(o + 4, x, Endian.host);
    buf.setFloat32(o + 8, y, Endian.host);
    buf.setUint32(o + 12, argb, Endian.host);
    buf.setFloat32(o + 16, size, Endian.host);
    buf.setUint32(o + 20, flags, Endian.host);
    buf.setUint32(o + 24, bytes.length, Endian.host);
    for (var i = 0; i < bytes.length; i++) {
      buf.setUint8(o + 28 + i, bytes[i]);
    }
    for (var i = 0; i < pad; i++) {
      buf.setUint8(o + raw + i, 0);
    }
    o += raw + pad;
  }

  rect(1, 2, 3, 4, 0xFFFF0000);
  text(10, 20, 'Hé', 14, 0xFF00FF00, 0);
  rect(5, 6, 7, 8, 0xFF0000FF);

  if (o != 80) throw StateError('expected 80 bytes, wrote $o');

  Directory('/tmp/watch_fixture').createSync(recursive: true);
  File('/tmp/watch_fixture/frame.bin').writeAsBytesSync(buf.buffer.asUint8List(0, o));
  print('wrote $o bytes to /tmp/watch_fixture/frame.bin');
}
