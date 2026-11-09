// Probe app for the engine-on-watchOS experiments. Three stripes; every colour is computed by Dart at run time,
// so a captured frame proves what the engine did without any logs:
//   stripe 1: green if Dart executed (fib(20) == 6765), red if it computed something else
//   stripe 2: white letter "W" on black  -> proves text shaping + fonts work (count of bright pixels)
//   stripe 3: constant blue              -> proves a second painted region (and tells BGRA from RGBA)
// Black everywhere = the engine never produced a frame.
import 'package:flutter/widgets.dart';

int _fib(int n) => n < 2 ? n : _fib(n - 1) + _fib(n - 2);

void main() => runApp(const _Probe());

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final dartRan = _fib(20) == 6765;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: dartRan ? const Color(0xFF00FF00) : const Color(0xFFFF0000),
              child: const SizedBox.expand(),
            ),
          ),
          const Expanded(
            child: ColoredBox(
              color: Color(0xFF000000),
              child: Center(
                child: Text(
                  'W',
                  style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 80, decoration: TextDecoration.none),
                ),
              ),
            ),
          ),
          const Expanded(child: ColoredBox(color: Color(0xFF0000FF), child: SizedBox.expand())),
        ],
      ),
    );
  }
}
