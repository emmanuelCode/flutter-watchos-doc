// Probe app for the engine-on-watchOS experiments.
// Three stripes; every colour is computed by Dart at run time:
//   Before tap (_taps == 0):
//     stripe 1: green if Dart executed (fib(20) == 6765), red if it computed something else
//     stripe 2: white letter "W" on black  -> proves text shaping + fonts work
//     stripe 3: constant blue              -> proves a second painted region (and tells BGRA from RGBA)
//   After tap (_taps > 0):
//     stripe 1: yellow                     -> proves touch event reached Dart & setState() ran
//     stripe 2: white "TAP" on black       -> proves dynamic text re-shaping and layout
//     stripe 3: constant cyan              -> proves repainted second region
import 'package:flutter/widgets.dart';

int _fib(int n) => n < 2 ? n : _fib(n - 1) + _fib(n - 2);

void main() => runApp(const _Probe());

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    final dartRan = _fib(20) == 6765;
    final Color s1Color = _taps == 0
        ? (dartRan ? const Color(0xFF00FF00) : const Color(0xFFFF0000))
        : const Color(0xFFFFFF00);
    final String s2Text = _taps == 0 ? 'W' : 'TAP';
    final Color s3Color = _taps == 0 ? const Color(0xFF0000FF) : const Color(0xFF00FFFF);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _taps++;
          });
        },
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: s1Color,
                child: const SizedBox.expand(),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF000000),
                child: Center(
                  child: Text(
                    s2Text,
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: _taps == 0 ? 80 : 50,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: s3Color,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
