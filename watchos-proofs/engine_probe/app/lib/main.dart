import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

int fib(int n) => n <= 1 ? n : fib(n - 1) + fib(n - 2);

void main() {
  runApp(const ProbeApp());
}

class ProbeApp extends StatefulWidget {
  const ProbeApp({super.key});

  @override
  State<ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<ProbeApp> {
  Color _stripe1Color = const Color(0xFF00FF00); // Green (Frame 1: Q5)
  Color _stripe3Color = const Color(0xFF0000FF); // Blue (Frame 1: Q5)
  String _glyph = 'W';

  void _handleTap() {
    setState(() {
      _stripe1Color = const Color(0xFFFFFF00); // Yellow (Frame 2: Q6)
      _stripe3Color = const Color(0xFF00FFFF); // Cyan (Frame 2: Q6)
      _glyph = 'TAP';
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      setState(() {
        _stripe1Color = const Color(0xFFFF00FF); // Magenta (Frame 3: Q7)
        _stripe3Color = const Color(0xFF8800FF); // Purple (Frame 3: Q7)
        _glyph = 'CROWN';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool fibOk = fib(20) == 6765;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: fibOk ? _stripe1Color : const Color(0xFFFF0000),
                ),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFF000000),
                  alignment: Alignment.center,
                  child: Text(
                    _glyph,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  color: _stripe3Color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
