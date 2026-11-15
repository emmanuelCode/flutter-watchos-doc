import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  int tcpPort = 8770;
  int httpPort = 8771;
  bool quiet = false;
  String host = '0.0.0.0';

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--tcp-port' && i + 1 < args.length) {
      tcpPort = int.parse(args[++i]);
    } else if (args[i] == '--http-port' && i + 1 < args.length) {
      httpPort = int.parse(args[++i]);
    } else if (args[i] == '--host' && i + 1 < args.length) {
      host = args[++i];
    } else if (args[i] == '--quiet') {
      quiet = true;
    }
  }

  // 1. TCP Echo Server
  final tcpServer = await ServerSocket.bind(host, tcpPort);
  tcpServer.listen((Socket client) {
    client.listen(
      client.add,
      onError: (Object _) => client.destroy(),
      onDone: () => client.close(),
      cancelOnError: true,
    );
  });

  // 2. HTTP + WebSocket Server
  final httpServer = await HttpServer.bind(host, httpPort);
  httpServer.listen((HttpRequest request) async {
    final uri = request.uri;
    if (uri.path == '/ping' && request.method == 'GET') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('pong');
      await request.response.close();
    } else if (uri.path == '/input' && request.method == 'POST') {
      await request.drain();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('ack');
      await request.response.close();
    } else if (uri.path == '/stream' && request.method == 'GET') {
      final frames = int.tryParse(uri.queryParameters['frames'] ?? '') ?? 30;
      final bytesCount = int.tryParse(uri.queryParameters['bytes'] ?? '') ?? 4096;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.binary;

      var rng = 123456789;
      for (var f = 0; f < frames; f++) {
        final chunk = Uint8List(bytesCount);
        for (var i = 0; i < bytesCount; i++) {
          rng = (1103515245 * rng + 12345) & 0x7FFFFFFF;
          chunk[i] = rng & 0xFF;
        }
        request.response.add(chunk);
        await request.response.flush();
      }
      await request.response.close();
    } else if (uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      final ws = await WebSocketTransformer.upgrade(request);
      ws.listen((dynamic msg) => ws.add(msg));
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found');
      await request.response.close();
    }
  });

  if (!quiet) {
    stdout.writeln('==============================================');
    stdout.writeln('Gate 0d Mac Echo Server active');
    stdout.writeln('TCP Echo port : $tcpPort');
    stdout.writeln('HTTP / WS port: $httpPort');
    stdout.writeln('Available LAN IP addresses:');
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            stdout.writeln('  - ${iface.name}: ${addr.address}');
          }
        }
      }
    } catch (_) {}
    stdout.writeln('==============================================');
  } else {
    stdout.writeln('GATE0D_SERVER_READY tcp=$tcpPort http=$httpPort');
  }

  void shutdown() async {
    await tcpServer.close();
    await httpServer.close(force: true);
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }
}
