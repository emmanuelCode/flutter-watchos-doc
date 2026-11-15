# Gate 0d probe: watch app

Design: [`docs/gate-0d-probe.md`](../../docs/gate-0d-probe.md). Status: **built in CI only, never run on
physical hardware yet.** Dev-only; never ship to the App Store.

## Build (contributor with a Mac)
1. `brew install xcodegen` (TODO(author): verify) then `cd gate0d_probe/watch_app && xcodegen generate`.
2. Open `Gate0dProbe.xcodeproj`, pick the `Gate0dProbe-RelaxedATS` scheme, set your own signing Team.
3. Run it on your watch from Xcode, then **stop** the Xcode session and launch the app from the watch
   home screen (that is `LAUNCH_MODE=standalone_watch`).
4. In the Mac terminal: `dart run gate0d_probe/mac_echo_server/probe_server.dart`, enter the printed
   LAN IP in the watch app, and run the required suite twice (see the design's two-run matrix).

## Getting the result block off the watch
The block is shown on screen, printed to the Xcode console, saved to the app's Documents folder as
`latest_gate0d_result.txt`, and offered through a Share button.
TODO(author): verify which share targets watchOS actually offers; a future version could POST the
block to the Mac server instead.

## What CI proves
It builds both variants unsigned for the watchOS device SDK and runs the probe in the Simulator as a
negative control (the Simulator is expected to allow every low-level network API). It proves nothing
about a physical watch.
