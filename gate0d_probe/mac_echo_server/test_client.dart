import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  int tcpPort = 8770;
  int httpPort = 8771;
  String host = '127.0.0.1';

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--tcp-port' && i + 1 < args.length) {
      tcpPort = int.parse(args[++i]);
    } else if (args[i] == '--http-port' && i + 1 < args.length) {
      httpPort = int.parse(args[++i]);
    } else if (args[i] == '--host' && i + 1 < args.length) {
      host = args[++i];
    }
  }

  final client = HttpClient();

  // 1. Test /ping
  final pingReq = await client.getUrl(Uri.parse('http://$host:$httpPort/ping'));
  final pingRes = await pingReq.close();
  if (pingRes.statusCode != 200) {
    throw Exception('/ping failed: status ${pingRes.statusCode}');
  }
  final pingBody = await utf8.decodeStream(pingRes);
  if (pingBody != 'pong') {
    throw Exception('/ping returned unexpected body: $pingBody');
  }
  stdout.writeln('OK: GET /ping returned pong');

  // 2. Test /input POST
  final postReq = await client.postUrl(Uri.parse('http://$host:$httpPort/input'));
  postReq.add(Uint8List(32));
  final postRes = await postReq.close();
  if (postRes.statusCode != 200) {
    throw Exception('/input failed: status ${postRes.statusCode}');
  }
  final postBody = await utf8.decodeStream(postRes);
  if (postBody != 'ack') {
    throw Exception('/input returned unexpected body: $postBody');
  }
  stdout.writeln('OK: POST /input (32 bytes) returned ack');

  // 3. Test /stream (chunked random bytes)
  final streamReq = await client.getUrl(Uri.parse('http://$host:$httpPort/stream?frames=3&bytes=500'));
  final streamRes = await streamReq.close();
  if (streamRes.statusCode != 200) {
    throw Exception('/stream failed: status ${streamRes.statusCode}');
  }
  var totalBytes = 0;
  await for (final chunk in streamRes) {
    totalBytes += chunk.length;
  }
  if (totalBytes != 1500) {
    throw Exception('/stream expected 1500 bytes, got $totalBytes');
  }
  stdout.writeln('OK: GET /stream returned 1500 bytes chunked');

  // 4. Test /ws WebSocket echo
  final ws = await WebSocket.connect('ws://$host:$httpPort/ws');
  final wsCompleter = Completer<void>();
  ws.listen((dynamic msg) {
    if (msg == 'hello-ws') {
      ws.close();
      wsCompleter.complete();
    }
  });
  ws.add('hello-ws');
  await wsCompleter.future.timeout(const Duration(seconds: 5));
  stdout.writeln('OK: WebSocket /ws echoed message');

  // 5. Test TCP Echo
  final socket = await Socket.connect(host, tcpPort);
  final tcpCompleter = Completer<void>();
  final payload = utf8.encode('gate0d-tcp-ping');
  socket.listen((data) {
    if (utf8.decode(data) == 'gate0d-tcp-ping') {
      socket.destroy();
      tcpCompleter.complete();
    }
  });
  socket.add(payload);
  await tcpCompleter.future.timeout(const Duration(seconds: 5));
  stdout.writeln('OK: TCP echo returned exact bytes');

  client.close();
  stdout.writeln();
  stdout.writeln('ALL ECHO SERVER ENDPOINTS VERIFIED OK');
  exit(0);
}
