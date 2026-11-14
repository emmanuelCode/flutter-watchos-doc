import 'package:flutter/widgets.dart';
import 'package:watchos_ui/watchos_ui.dart';

void main() {
  runApp(const WatchOSExampleShell());
}

class WatchOSExampleShell extends StatefulWidget {
  const WatchOSExampleShell({super.key});

  @override
  State<WatchOSExampleShell> createState() => _WatchOSExampleShellState();
}

class _WatchOSExampleShellState extends State<WatchOSExampleShell> {
  WatchOSSize _selectedSize = WatchOSSize.mm46;
  bool _higChecker = true;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.fromView(
      view: View.of(context),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF101012),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      for (final profile in WatchOSScreenProfile.all)
                        GestureDetector(
                          onTap: () => setState(() => _selectedSize = profile.watchSize),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedSize == profile.watchSize
                                  ? const Color(0xFF0A84FF)
                                  : const Color(0xFF26262A),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              profile.label,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => setState(() => _higChecker = !_higChecker),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _higChecker
                                ? const Color(0xFF30D158)
                                : const Color(0xFF26262A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _higChecker ? 'HIG Audit: ON' : 'HIG Audit: OFF',
                            style: const TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  WatchOSPreviewFrame(
                    watchSize: _selectedSize,
                    child: WorkoutWatchApp(enableHigChecker: _higChecker),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkoutWatchApp extends StatefulWidget {
  const WorkoutWatchApp({super.key, required this.enableHigChecker});

  final bool enableHigChecker;

  @override
  State<WorkoutWatchApp> createState() => _WorkoutWatchAppState();
}

class _WorkoutWatchAppState extends State<WorkoutWatchApp> {
  int _bpm = 134;
  int _laps = 2;

  @override
  Widget build(BuildContext context) {
    return WatchOSApp(
      title: 'Workout',
      enableHigChecker: widget.enableHigChecker,
      home: WatchOSPageScaffold(
        pages: <Widget>[
          Builder(
            builder: (BuildContext context) {
              final theme = WatchOSTheme.of(context);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    WatchOSProgressRing(
                      progress: (_laps / 5).clamp(0.0, 1.0),
                      size: 62,
                      color: const Color(0xFF30D158),
                      child: Text('$_bpm', style: theme.textTheme.title),
                    ),
                    const SizedBox(height: 6),
                    Text('BPM · Lap $_laps/5', style: theme.textTheme.caption),
                    const SizedBox(height: 10),
                    WatchOSButton(
                      backgroundColor: const Color(0xFF0A84FF),
                      onPressed: () {
                        setState(() {
                          _laps = (_laps % 5) + 1;
                          _bpm = 128 + (_laps * 4);
                        });
                      },
                      child: const Text('+1 Lap'),
                    ),
                  ],
                ),
              );
            },
          ),
          WatchOSListScaffold(
            header: const Text('Laps'),
            children: List<Widget>.generate(
              _laps,
              (int i) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('Lap ${i + 1} · ${128 + ((i + 1) * 4)} BPM'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
