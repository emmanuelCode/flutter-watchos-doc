# CI Result Sheet — `2026-11-15` (`740962b`)

- **Date (UTC):** `2026-11-15T19:25:45Z`
- **Commit:** `740962b92ace508d651221e9ba3b513a3efcb2da`
- **Branch / PR:** `fix/report-metadata-header`
- **Run ID:** `43749925381`
- **Source:** GitHub Actions (`proofs.yml` `results-sheet` artifact)

## `watchos-proofs` (`RESULTS` job output)

```text
======== WATCHOS PROOFS RESULT SHEET ========
Date (UTC): 2026-11-15T19:25:45Z
Commit: 740962b92ace508d651221e9ba3b513a3efcb2da
Branch / PR: fix/report-metadata-header
Run ID: 43749925381
Event: push
Source: GitHub Actions (proofs.yml results-sheet)

ENVIRONMENT
  proof run: commit 740962b, run 43749925381  <- if this is the same as the previous sheet, nothing new ran
  runner image: macos26 20261102.0473.1 (arm64)
  macOS 26.7.2
  Xcode 26.6 Build version 17F113 
  watchsimulator SDK 26.5
  Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "macos_arm64"
  runner image: macos26 20261102.0473.1 (arm64)
  macOS 26.7.2
  Flutter 3.50.0 • channel stable • https://github.com/flutter/flutter.git
  Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "macos_arm64"
  runner image: macos26 20261102.0473.1 (arm64)
  macOS 26.7.2
  Xcode 26.6 Build version 17F113 
  watchsimulator SDK 26.5
  Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "macos_arm64"
  runner image: macos26 20261102.0473.1 (arm64)
  macOS 26.7.2
  Flutter 3.50.0 • channel stable • https://github.com/flutter/flutter.git
  Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "macos_arm64"
  runner image: macos26 20261102.0473.1 (arm64)
  macOS 26.7.2
  Flutter 3.50.0 • channel stable • https://github.com/flutter/flutter.git
  Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "macos_arm64"
  runner image: macos26 20261102.0473.1 (arm64)
  macOS 26.7.2
  Xcode 26.6 Build version 17F113 
  watchsimulator SDK 26.5
  Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "macos_arm64"
  runner image: macos26 20261102.0473.1 (arm64)
  macOS 26.7.2
  Flutter 3.50.0 • channel stable • https://github.com/flutter/flutter.git
  Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "macos_arm64"

RESULTS
  ✅ F0  Flutter dependencies resolve
  ✅ P1  A watchOS Simulator exists and boots
  ✅ P0  Swift code compiles for watchOS
  ✅ P2  Flutter captures a frame headless (toImage -> RGBA, sizes match)
  ✅ P3  Injected tap changes the next frame
  ✅ P4  RGBA bytes -> CGImage with correct pixels
  ✅ P5  SwiftUI Canvas draws the frame (pixels checked)
  ✅ P6  Dart WebSocket server <-> watchOS client (frame down, tap up)
  ✅ A1  [App.A] Canvas text .topLeading vs .center
  ✅ A2  [App.A] Triple-buffer mailbox
  ✅ A3  [App.A] Dart-written bytes parse correctly in Swift
  ✅ A4  [App.A] @_cdecl symbol found by dlsym
  ✅ P9  Sustained transport: 100 frames x (1.0, 2.0) x (raw, zlib, delta)
  ✅ X1  [spec code] Dart classes extracted from the spec
  ✅ S1  [spec code] real WatchFrameStreamer + WatchInputInjector: capture, tap, next frame
  ✅ S7  [spec code] captureNow() pushes the current frame from an idle app
  ✅ X2  [spec code] Swift code extracted from the spec
  ✅ S0  [spec code] Spec Swift code compiles for watchOS
  ✅ S2  [spec code] Color(argb:) renders the right channels
  ✅ S3  [spec code] WatchFrameStore + WatchFrameView draw a frame, stretched to fill
  ✅ S4  [spec code] WatchFrameView redraws when a new frame is published
  ✅ S5  [spec code] WatchRenderStore + @_cdecl slab API + WatchCanvasView draw Dart-style bytes
  ✅ S6  [spec code] WatchCanvasView redraws on frameTick, no TimelineView (experimental)
  ✅ E0  [e2e] Simulator boots, spec code extracted, Flutter deps resolved
  ✅ E1  [e2e] Whole loop: real streamer -> WebSocket -> real WatchFrameView; tap back -> next frame
  ✅ Q0  [engine] What a hosted runner offers (cpu, memory, disk)
  ✅ Q1  [engine] Real engine source: facts + does the engine base layer (fml) compile for watchOS
  ✅ Q2  [engine] Official engine pieces gathered (embedder library, icu data, iOS engine, probe bundle)
  ✅ Q2s [engine] A watch simulator boots
  ✅ Q3  [engine] Gap analysis: what the official engines import that watchOS lacks
  ✅ Q4  [engine] EXPERIMENT: retagged embedder library loads in a watchOS process and exports the embedder API
  ✅ Q5  [engine] EXPERIMENT: Flutter runs in a watchOS process via embedder.h (software renderer); pixels checked
  ✅ Q6  [engine] EXPERIMENT: Interactive loop (tap -> setState -> frame 2) + memory logged
  ✅ Q7  [engine] EXPERIMENT: Crown scroll input (signal_kind=scroll -> setState -> frame 3) + low memory hook
  => 34/34 passed

MEASUREMENTS / INFO
  [E0] INFO: watch simulator Apple Watch Series 11 (46mm) (watchOS-26-5) C5E1D47B-37DC-46A5-9DDA-907CAC9587CD
  [E0] INFO: extracted swift_spec/Sources/SpecCode/ColorARGB.swift (12 lines)
  [E0] INFO: extracted swift_spec/Sources/SpecCode/WatchFrame.swift (25 lines)
  [E0] INFO: extracted swift_spec/Sources/SpecCode/WatchRender.swift (178 lines)
  [E0] INFO: extracted flutter_proofs/lib/spec/watch_frame_streamer.dart (90 lines)
  [E0] INFO: extracted flutter_proofs/lib/spec/watch_input_injector.dart (26 lines)
  [E1] E1: server sent 2 frames, handled 1 tap(s), app state taps=1
  [SIM] E1: frame 0 (red) -> tap(99,121) -> frame 1 (green); view showed both
  [Q0] Q0: cpu cores: 5, memory: 14 GB, arch: arm64
  [Q0] Q0: free disk on the runner volume: 93 GB
  [Q0] Q0: hosted job time limit is 6 h; this job is capped at 60 min. A from-source Flutter engine build (gclient sync + ninja) is expected to need far more than that: not attempted here
  [Q1] Q1: engine version of this Flutter SDK: 371f77202a73e8dff57a8b3bff75bca55c090aee
  [Q1] Q1: embedder.h: 47 exported functions; software renderer config present: 3 mentions
  [Q1] Q1: build tool target-OS options (tools/gn):
  [Q1] Q1:   23:  if args.target_os is not None:
  [Q1] Q1:   24:    target_dir = [args.target_os]
  [Q1] Q1:   53:  if args.target_os == 'fuchsia' and args.fuchsia_cpu is not None:
  [Q1] Q1:   92:  # If target_os == None, then this is a host build.
  [Q1] Q1:   93:  if args.target_os is None:
  [Q1] Q1:   96:  # target_os='linux' and linux-cpu='arm64'
  [Q1] Q1:   97:  if args.target_os == 'linux' and args.linux_cpu == 'arm64':
  [Q1] Q1:   101:  if args.target_os == 'mac':
  [Q1] Q1: mentions of watchOS in the sampled engine source (fml, embedder, tools): 0
  [Q1] Q1: how fml/build_config.h tells iOS from macOS:
  [Q1] Q1:   7://    FML_OS_WIN / FML_OS_MACOSX / FML_OS_LINUX / FML_OS_POSIX (MACOSX or LINUX)
  [Q1] Q1:   28:#define FML_OS_MACOSX 1
  [Q1] Q1:   29:#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  [Q1] Q1:   30:#define FML_OS_IOS 1
  [Q1] Q1:   31:#endif  // defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  [Q1] Q1:   33:#define FML_OS_IOS_SIMULATOR 1
  [Q1] Q1:   34:#endif  // defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  [Q1] Q1:   67:#if defined(FML_OS_MACOSX) || defined(FML_OS_LINUX) ||    \
  [Q1] Q1: how Apple's headers describe a watchOS Simulator target (TargetConditionals.h):
  [Q1] Q1:   TARGET_OS_IOS 0
  [Q1] Q1:   TARGET_OS_IPHONE 1
  [Q1] Q1:   TARGET_OS_MAC 1
  [Q1] Q1:   TARGET_OS_OSX 0
  [Q1] Q1:   TARGET_OS_SIMULATOR 1
  [Q1] Q1:   TARGET_OS_WATCH 1
  [Q1] Q1: how Apple's headers describe a watchOS device target (TargetConditionals.h):
  [Q1] Q1:   TARGET_OS_IOS 0
  [Q2] Q2: HEAD darwin-arm64/FlutterEmbedder.framework.zip -> HTTP 404
  [Q2] Q2: HEAD darwin-x64/FlutterEmbedder.framework.zip -> HTTP 200
  [Q2] Q2: using darwin-x64 embedder library, 91 MB, archs: x86_64 arm64
  [Q2] Q2: icudtl.dat found (844 KB)
  [Q2] Q2: official iOS Simulator engine found (83 MB) for the gap analysis
  [Q2] Q2: probe app bundle ready (kernel_blob.bin 23141 KB)
  [Q2s] INFO: watch simulator Apple Watch Series 11 (46mm) (watchOS-26-5) C5E1D47B-37DC-46A5-9DDA-907CAC9587CD
  [Q3] Q3: [watchsimulator] key APIs exported for watchos: UIView, UIViewController, UIScreen, UIApplication, UITouch, UIImage, CALayer, CAMetalLayer, CADisplayLink, CGBitmapContextCreate, CTFontCreateWithNa
  [Q3] Q3: [watchsimulator] key APIs NOT exported for watchos: MTLCreateSystemDefaultDevice, IOSurfaceCreate
  [Q3] Q3: [watchos] key APIs exported for watchos: UIView, UIViewController, UIScreen, UIApplication, UITouch, UIImage, CALayer, CAMetalLayer, CADisplayLink, CGBitmapContextCreate, CTFontCreateWithName, CFR
  [Q3] Q3: [watchos] key APIs NOT exported for watchos: MTLCreateSystemDefaultDevice, IOSurfaceCreate
  [Q3] Q3: [headers:watchos] Metal.h / MTLCreateSystemDefaultDevice -> FAIL (<stdin>:1:9: fatal error: 'Metal/Metal.h' file not found)
  [Q3] Q3: [headers:watchos] QuartzCore / CAMetalLayer -> FAIL (<stdin>:2:25: error: unknown receiver 'CAMetalLayer'; did you mean 'CATextLayer'?)
  [Q3] Q3: [headers:watchos] UIKit / UIView -> FAIL (<stdin>:2:32: error: 'UIView' is unavailable: not available on watchOS)
  [Q3] Q3: [headers:watchos] SpriteKit / SKMutableTexture (ObjC initWithSize:) -> OK
  [Q3] Q3: [headers:watchos] SpriteKit / SKMutableTexture (Swift) -> OK
  [Q3] Q3: [headers:watchos] SpriteKit / SKTexture(data:size:) (Swift) -> OK
  [Q3] Q3: [headers:watchos] SwiftUI / SpriteView -> OK
  [Q3] Q3: [headers:watchos] CoreGraphics + CoreText -> OK
  [Q3] Q3: [headers:watchos] WatchKit / WKCrownSequencer -> OK
  [Q3] Q3: [headers:watchos] POSIX chdir -> OK
  [Q3] Q3: [headers:watchos] POSIX fork -> FAIL (<stdin>:2:24: error: 'fork' is unavailable: not available on watchOS)
  [Q3] Q3: [desktop embedder] FlutterEmbedder: 29 linked libraries, 673 imported symbols
  [Q3] Q3: [desktop embedder] libraries that exist on watchOS but at a flat path (macOS-style versioned path must be rewritten): 8
  [Q3] Q3: [desktop embedder] libraries NOT provided by the watchOS SDK at all: ApplicationServices, OpenGL, AppKit, Metal, MetalPerformanceShaders, libswiftIOKit, libswiftMetal
  [Q3] Q3: [desktop embedder] imported symbols missing on watchOS (platform-filtered): 22 of 673 (21 of those exist in the iOS Simulator SDK)
  [Q3] Q3: [desktop embedder]   Metal: 15 missing, e.g. _MTLCommandBufferEncoderInfoErrorKey, _MTLCreateSystemDefaultDevice, _OBJC_CLASS_$_MTLCaptureManager, _OBJC_CLASS_$_MTLCommandBufferDescriptor, _OBJC_C
  [Q3] Q3: [desktop embedder]   CoreVideo: 4 missing, e.g. _CVMetalTextureCacheCreate, _CVMetalTextureCacheCreateTextureFromImage, _CVMetalTextureCacheFlush, _CVMetalTextureGetTexture
  [Q3] Q3: [desktop embedder]   MetalPerformanceShaders: 1 missing, e.g. _OBJC_CLASS_$_MPSImageBilinearScale
  [Q3] Q3: [desktop embedder]   libswiftIOKit: 1 missing, e.g. __swift_FORCE_LOAD_$_swiftIOKit
  [Q3] Q3: [desktop embedder]   libswiftMetal: 1 missing, e.g. __swift_FORCE_LOAD_$_swiftMetal
  [Q3] Q3: [desktop embedder] device SDK (watchos) direct check: 22 of 673 missing; delta vs watchsimulator: +0 libs, +0 / -0 syms
  [Q3] Q3: [iOS engine] ios_Flutter: 44 linked libraries, 1077 imported symbols
  [Q3] Q3: [iOS engine] libraries that exist on watchOS but at a flat path (macOS-style versioned path must be rewritten): 0
  [Q3] Q3: [iOS engine] libraries NOT provided by the watchOS SDK at all: AudioToolbox, IOSurface, WebKit, IOKit, Metal, MetalPerformanceShaders, _Translation_SwiftUI, libswiftCoreImage, libswiftMetal, libsw
  [Q3] Q3: [iOS engine] imported symbols missing on watchOS (platform-filtered): 46 of 1077 (46 of those exist in the iOS Simulator SDK)
  [Q3] Q3: [iOS engine]   Metal: 14 missing, e.g. _MTLCommandBufferEncoderInfoErrorKey, _MTLCreateSystemDefaultDevice, _OBJC_CLASS_$_MTLCaptureManager, _OBJC_CLASS_$_MTLCommandBufferDescriptor, _OBJC_CLASS_$
  [Q4] Q4: retagged as watchOS Simulator (vtool platform 'watchossim', minos 10.0, sdk 26.5)
  [Q4] Q4: attempt 1 failed: DLOPEN FAIL: dlopen(/tmp/engine/watchos/FlutterEmbedder, 0x0006): Library not loaded: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
  [Q4] Q4: rewrote 8 macOS-style versioned framework paths to the flat watchOS layout
  [Q4] Q4: stubbing libraries the watchOS SDK lacks: ApplicationServices, OpenGL, AppKit, Metal, MetalPerformanceShaders, libswiftIOKit, libswiftMetal
  [Q4] Q4:   ApplicationServices is imported for: 
  [Q4] Q4:   stub ApplicationServices: defines 0 symbols
  [Q4] Q4:   OpenGL is imported for: 
  [Q4] Q4:   stub OpenGL: defines 0 symbols
  [Q4] Q4:   AppKit is imported for: _OBJC_CLASS_$_NSFont
  [Q4] Q4:   AppKit: real implementation for _OBJC_CLASS_$_NSFont
  [Q4] Q4:   stub AppKit: defines 1 symbols
  [Q4] Q4:   Metal is imported for: _MTLCommandBufferEncoderInfoErrorKey, _MTLCreateSystemDefaultDevice, _OBJC_CLASS_$_MTLCaptureManager, _OBJC_CLASS_$_MTLCommandBufferDescriptor, _OBJC_CLASS_$_MTLCompileOpt
  [Q4] Q4:   stub Metal: defines 15 symbols
  [Q4] Q4:   MetalPerformanceShaders is imported for: _OBJC_CLASS_$_MPSImageBilinearScale
  [Q4] Q4:   stub MetalPerformanceShaders: defines 1 symbols
  [Q4] Q4:   libswiftIOKit is imported for: __swift_FORCE_LOAD_$_swiftIOKit
  [Q4] Q4:   stub libswiftIOKit: defines 1 symbols
  [Q4] Q4:   libswiftMetal is imported for: __swift_FORCE_LOAD_$_swiftMetal
  [Q4] Q4:   stub libswiftMetal: defines 1 symbols
  [Q4] Q4: symbols missing from libraries the watchOS SDK does have: 4 e.g. _CVMetalTextureCacheCreate (in CoreVideo), _CVMetalTextureCacheCreateTextureFromImage (in CoreVideo), _CVMetalTextureCacheFlush (in
  [Q4] Q4: attempt 2 failed: DLOPEN FAIL: dlopen(/tmp/engine/watchos/FlutterEmbedder, 0x0006): Symbol not found: _CVMetalTextureCacheCreate
  [Q4] Q4:   overlay CoreVideo: now defines 1 symbol(s), re-exports the real library
  [Q4] Q4:   overlay CoreVideo: now defines 2 symbol(s), re-exports the real library
  [Q4] Q4:   overlay CoreVideo: now defines 3 symbol(s), re-exports the real library
  [Q4] Q4:   overlay CoreVideo: now defines 4 symbol(s), re-exports the real library
  [Q4] Q4: loaded after 4 overlaid symbol(s)
  [Q4] Q4: SYMBOL FlutterEngineRun: found
  [Q4] Q4: SYMBOL FlutterEngineSendWindowMetricsEvent: found
  [Q4] Q4: SYMBOL FlutterEngineShutdown: found
  [Q5] Q5: host compiled for watchOS Simulator against the real embedder.h
  [Q5] Q5: snapshot symbols exported by the engine library: _kDartSnapshotData _kDartSnapshotText 
  [Q5] Q5: host: FlutterEngineRun -> 0
  [Q5] Q5: host: [engine flutter] The Dart VM service is listening on http://127.0.0.1:50060/O6mv_rHXaog=/
  [Q5] Q5: host: frames presented: 2
  [Q5] Q5: frame is 198x242, saved as PNG (/tmp/engine_frame.png)
  [Q5] Q5: stripe 1 green: Dart executed (fib(20) == 6765): (0, 255, 0) -> ok
  [Q5] Q5: stripe 2: white 'W' glyph pixels in the middle (text shaping + fonts): 746 bright pixels -> ok
  [Q5] Q5: stripe 2: black background: (0, 0, 0) -> ok
  [Q5] Q5: stripe 3 blue: a second region painted: (0, 0, 255) -> ok
  [Q5] Q5: byte order of the software present callback in this engine build: RGBA
  [Q6] Q6: using simulator C5E1D47B-37DC-46A5-9DDA-907CAC9587CD
  [Q6] Q6: ENGINE_LIB=/tmp/engine/watchos/FlutterEmbedder
  [Q6] Q6: ASSETS_DIR=/Users/runner/work/flutter-watchos-doc/flutter-watchos-doc/watchos-proofs/engine_probe/app/build/flutter_assets
  [Q6] Q6: ICU_PATH=/tmp/engine/icudtl.dat
  [Q6] Q6: host: memory after frame 1: resident=141.64 MB (145040 KB), virtual=400648.38 MB
  [Q6] Q6: host: memory after frame 2: resident=142.89 MB (146320 KB), virtual=400648.44 MB
  [Q6] Q6: frame is 198x242 (pure byte parser; skipped PNG save)
  [Q6] Q6: stripe 1 yellow: tap injected & setState executed: (255, 255, 0) -> ok
  [Q6] Q6: stripe 2: white 'TAP' glyph pixels in the middle (text shaping + layout): 1355 bright pixels -> ok
  [Q6] Q6: stripe 2: black background: (0, 0, 0) -> ok
  [Q6] Q6: stripe 3 cyan: second region repainted post-tap: (0, 255, 255) -> ok
  [Q6] Q6: byte order of the software present callback in this engine build: RGBA
  [Q6] Q6: PASS - frame 1 and frame 2 are distinct binary frames
  [Q7] Q7: using simulator C5E1D47B-37DC-46A5-9DDA-907CAC9587CD
  [Q7] Q7: ENGINE_LIB=/tmp/engine/watchos/FlutterEmbedder
  [Q7] Q7: ASSETS_DIR=/Users/runner/work/flutter-watchos-doc/flutter-watchos-doc/watchos-proofs/engine_probe/app/build/flutter_assets
  [Q7] Q7: ICU_PATH=/tmp/engine/icudtl.dat
  [Q7] Q7: host: memory after frame 1: resident=141.41 MB (144800 KB), virtual=400647.78 MB
  [Q7] Q7: host: memory after frame 2: resident=142.41 MB (145824 KB), virtual=400647.84 MB
  [Q7] Q7: host: memory after frame 3: resident=140.86 MB (144240 KB), virtual=400646.84 MB
  [Q7] Q7: FlutterEngineNotifyLowMemoryWarning -> 0
  [Q7] Q7: host: memory after notify low memory: resident=140.53 MB (143904 KB), virtual=400646.22 MB
  [Q7] Q7: frame is 198x242 (pure byte parser; skipped PNG save)
  [Q7] Q7: stripe 1 magenta: Crown scroll injected & setState executed: (255, 0, 255) -> ok
  [Q7] Q7: stripe 2: white 'CROWN' glyph pixels in the middle (text shaping + layout): 1650 bright pixels -> ok
  [Q7] Q7: stripe 2: black background: (0, 0, 0) -> ok
  [Q7] Q7: stripe 3 purple: second region repainted post-crown: (136, 0, 255) -> ok
  [Q7] Q7: byte order of the software present callback in this engine build: RGBA
  [Q7] Q7: PASS - frame 2 and frame 3 are distinct binary frames
  [SIM] Q0: cpu cores: 5, memory: 14 GB, arch: arm64
  [SIM] Q0: free disk on the runner volume: 93 GB
  [SIM] Q0: hosted job time limit is 6 h; this job is capped at 60 min. A from-source Flutter engine build (gclient sync + ninja) is expected to need far more than that: not attempted here
  [SIM] Q1: engine version of this Flutter SDK: 371f77202a73e8dff57a8b3bff75bca55c090aee
  [SIM] Q1: embedder.h: 47 exported functions; software renderer config present: 3 mentions
  [SIM] Q1: build tool target-OS options (tools/gn):
  [SIM] Q1:   23:  if args.target_os is not None:
  [SIM] Q1:   24:    target_dir = [args.target_os]
  [SIM] Q1:   53:  if args.target_os == 'fuchsia' and args.fuchsia_cpu is not None:
  [SIM] Q1:   92:  # If target_os == None, then this is a host build.
  [SIM] Q1:   93:  if args.target_os is None:
  [SIM] Q1:   96:  # target_os='linux' and linux-cpu='arm64'
  [SIM] Q1:   97:  if args.target_os == 'linux' and args.linux_cpu == 'arm64':
  [SIM] Q1:   101:  if args.target_os == 'mac':
  [SIM] Q1: mentions of watchOS in the sampled engine source (fml, embedder, tools): 0
  [SIM] Q1: how fml/build_config.h tells iOS from macOS:
  [SIM] Q1:   7://    FML_OS_WIN / FML_OS_MACOSX / FML_OS_LINUX / FML_OS_POSIX (MACOSX or LINUX)
  [SIM] Q1:   28:#define FML_OS_MACOSX 1
  [SIM] Q1:   29:#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  [SIM] Q1:   30:#define FML_OS_IOS 1
  [SIM] Q1:   31:#endif  // defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  [SIM] Q1:   33:#define FML_OS_IOS_SIMULATOR 1
  [SIM] Q1:   34:#endif  // defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  [SIM] Q1:   67:#if defined(FML_OS_MACOSX) || defined(FML_OS_LINUX) ||    \
  [SIM] Q1: how Apple's headers describe a watchOS Simulator target (TargetConditionals.h):
  [SIM] Q1:   TARGET_OS_IOS 0
  [SIM] Q1:   TARGET_OS_IPHONE 1
  [SIM] Q1:   TARGET_OS_MAC 1
  [SIM] Q1:   TARGET_OS_OSX 0
  [SIM] Q1:   TARGET_OS_SIMULATOR 1
  [SIM] Q1:   TARGET_OS_WATCH 1
  [SIM] Q1: how Apple's headers describe a watchOS device target (TargetConditionals.h):
  [SIM] Q1:   TARGET_OS_IOS 0
  [SIM] Q1:   TARGET_OS_IPHONE 1
  [SIM] Q1:   TARGET_OS_MAC 1
  [SIM] Q1:   TARGET_OS_OSX 0
  [SIM] Q1:   TARGET_OS_SIMULATOR 0
  [SIM] Q1:   TARGET_OS_WATCH 1
  [SIM] Q1: fml files (watchsimulator): 55 checked, 49 compile, 6 fail (0 unavailable API, 6 missing external header)
  [SIM] Q1:   MISSING HEADER flutter/fml/backtrace.cc: /tmp/flutter_src/engine/src/flutter/fml/backtrace.cc:13:10: fatal error: 'third_party/abseil-cpp/absl/debugging/symbolize.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/concurrent_message_loop.cc: /tmp/flutter_src/engine/src/flutter/fml/trace_event.h:64:10: fatal error: 'third_party/dart/runtime/include/dart_tools_api.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/icu_util.cc: /tmp/flutter_src/engine/src/flutter/fml/icu_util.cc:15:10: fatal error: 'third_party/icu/source/common/unicode/udata.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/platform/posix/file_posix.cc: /tmp/flutter_src/engine/src/flutter/fml/trace_event.h:64:10: fatal error: 'third_party/dart/runtime/include/dart_tools_api.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/safe_math.cc: /tmp/flutter_src/engine/src/flutter/fml/safe_math.cc:8:10: fatal error: 'third_party/abseil-cpp/absl/numeric/int128.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/trace_event.cc: /tmp/flutter_src/engine/src/flutter/fml/trace_event.h:64:10: fatal error: 'third_party/dart/runtime/include/dart_tools_api.h' file not found
  [SIM] Q1: fml files (watchos): 55 checked, 49 compile, 6 fail (0 unavailable API, 6 missing external header)
  [SIM] Q1:   MISSING HEADER flutter/fml/backtrace.cc: /tmp/flutter_src/engine/src/flutter/fml/backtrace.cc:13:10: fatal error: 'third_party/abseil-cpp/absl/debugging/symbolize.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/concurrent_message_loop.cc: /tmp/flutter_src/engine/src/flutter/fml/trace_event.h:64:10: fatal error: 'third_party/dart/runtime/include/dart_tools_api.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/icu_util.cc: /tmp/flutter_src/engine/src/flutter/fml/icu_util.cc:15:10: fatal error: 'third_party/icu/source/common/unicode/udata.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/platform/posix/file_posix.cc: /tmp/flutter_src/engine/src/flutter/fml/trace_event.h:64:10: fatal error: 'third_party/dart/runtime/include/dart_tools_api.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/safe_math.cc: /tmp/flutter_src/engine/src/flutter/fml/safe_math.cc:8:10: fatal error: 'third_party/abseil-cpp/absl/numeric/int128.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/fml/trace_event.cc: /tmp/flutter_src/engine/src/flutter/fml/trace_event.h:64:10: fatal error: 'third_party/dart/runtime/include/dart_tools_api.h' file not found
  [SIM] Q1: embedder files (watchos): 28 checked, 1 compile, 27 fail (0 unavailable API, 27 missing external header)
  [SIM] Q1:   MISSING HEADER flutter/shell/platform/embedder/embedder_external_texture_metal.mm: /tmp/flutter_src/engine/src/flutter/shell/platform/embedder/embedder_external_texture_metal.h:8:10: fatal error: 'flutter/common/graphics/texture.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/shell/platform/embedder/embedder_external_texture_gl.cc: /tmp/flutter_src/engine/src/flutter/shell/platform/embedder/embedder_external_texture_gl.h:8:10: fatal error: 'flutter/common/graphics/texture.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/shell/platform/embedder/embedder_engine.cc: /tmp/flutter_src/engine/src/flutter/shell/platform/embedder/embedder_engine.h:12:10: fatal error: 'flutter/shell/common/shell.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/shell/platform/embedder/embedder_external_texture_resolver.cc: /tmp/flutter_src/engine/src/flutter/shell/platform/embedder/embedder_external_texture_resolver.h:10:10: fatal error: 'flutter/common/graphics/texture.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/shell/platform/embedder/embedder_external_texture_vulkan.cc: /tmp/flutter_src/engine/src/flutter/shell/platform/embedder/embedder_external_texture_vulkan.h:8:10: fatal error: 'flutter/common/graphics/texture.h' file not found
  [SIM] Q1:   MISSING HEADER flutter/shell/platform/embedder/embedder_external_view_embedder.cc: /tmp/flutter_src/engine/src/flutter/shell/platform/embedder/embedder_external_view_embedder.h:12:10: fatal error: 'flutter/flow/embedded_views.h' file not found
  [SIM] Q1: target_os list in tools/gn: android, ios, mac, linux, fuchsia, wasm, win, qnx (watchos absent)
  [SIM] Q1: precedent: qnx is software-only embedder profile (Skia GPU backends off, arm64 only)
  [SIM] Q1: Dart SDK commit/version of this Flutter SDK: 3.14.0
  [SIM] Q1: Dart tools/gn.py accepts: watchos, watchos_simulator
  [SIM] Q2: HEAD darwin-arm64/FlutterEmbedder.framework.zip -> HTTP 404
  [SIM] Q2: HEAD darwin-x64/FlutterEmbedder.framework.zip -> HTTP 200
  [SIM] Q2: using darwin-x64 embedder library, 91 MB, archs: x86_64 arm64
  [SIM] Q2: icudtl.dat found (844 KB)
  [SIM] Q2: official iOS Simulator engine found (83 MB) for the gap analysis
  [SIM] Q2: probe app bundle ready (kernel_blob.bin 23141 KB)
  [SIM] Q3: [watchsimulator] key APIs exported for watchos: UIView, UIViewController, UIScreen, UIApplication, UITouch, UIImage, CALayer, CAMetalLayer, CADisplayLink, CGBitmapContextCreate, CTFontCreateWithName, CFRunLoopRunInMode, WKInterfaceDevice, WKCrownSequencer, SKMutableTexture, SKView, CVPixelBufferCreate
  [SIM] Q3: [watchsimulator] key APIs NOT exported for watchos: MTLCreateSystemDefaultDevice, IOSurfaceCreate
  [SIM] Q3: [watchos] key APIs exported for watchos: UIView, UIViewController, UIScreen, UIApplication, UITouch, UIImage, CALayer, CAMetalLayer, CADisplayLink, CGBitmapContextCreate, CTFontCreateWithName, CFRunLoopRunInMode, WKInterfaceDevice, WKCrownSequencer, SKMutableTexture, SKView, CVPixelBufferCreate
  [SIM] Q3: [watchos] key APIs NOT exported for watchos: MTLCreateSystemDefaultDevice, IOSurfaceCreate
  [SIM] Q3: [headers:watchos] Metal.h / MTLCreateSystemDefaultDevice -> FAIL (<stdin>:1:9: fatal error: 'Metal/Metal.h' file not found)
  [SIM] Q3: [headers:watchos] QuartzCore / CAMetalLayer -> FAIL (<stdin>:2:25: error: unknown receiver 'CAMetalLayer'; did you mean 'CATextLayer'?)
  [SIM] Q3: [headers:watchos] UIKit / UIView -> FAIL (<stdin>:2:32: error: 'UIView' is unavailable: not available on watchOS)
  [SIM] Q3: [headers:watchos] SpriteKit / SKMutableTexture (ObjC initWithSize:) -> OK
  [SIM] Q3: [headers:watchos] SpriteKit / SKMutableTexture (Swift) -> OK
  [SIM] Q3: [headers:watchos] SpriteKit / SKTexture(data:size:) (Swift) -> OK
  [SIM] Q3: [headers:watchos] SwiftUI / SpriteView -> OK
  [SIM] Q3: [headers:watchos] CoreGraphics + CoreText -> OK
  [SIM] Q3: [headers:watchos] WatchKit / WKCrownSequencer -> OK
  [SIM] Q3: [headers:watchos] POSIX chdir -> OK
  [SIM] Q3: [headers:watchos] POSIX fork -> FAIL (<stdin>:2:24: error: 'fork' is unavailable: not available on watchOS)
  [SIM] Q3: [desktop embedder] FlutterEmbedder: 29 linked libraries, 673 imported symbols
  [SIM] Q3: [desktop embedder] libraries that exist on watchOS but at a flat path (macOS-style versioned path must be rewritten): 8
  [SIM] Q3: [desktop embedder] libraries NOT provided by the watchOS SDK at all: ApplicationServices, OpenGL, AppKit, Metal, MetalPerformanceShaders, libswiftIOKit, libswiftMetal
  [SIM] Q3: [desktop embedder] imported symbols missing on watchOS (platform-filtered): 22 of 673 (21 of those exist in the iOS Simulator SDK)
  [SIM] Q3: [desktop embedder]   Metal: 15 missing, e.g. _MTLCommandBufferEncoderInfoErrorKey, _MTLCreateSystemDefaultDevice, _OBJC_CLASS_$_MTLCaptureManager, _OBJC_CLASS_$_MTLCommandBufferDescriptor, _OBJC_CLASS_$_MTLCompileOptions
  [SIM] Q3: [desktop embedder]   CoreVideo: 4 missing, e.g. _CVMetalTextureCacheCreate, _CVMetalTextureCacheCreateTextureFromImage, _CVMetalTextureCacheFlush, _CVMetalTextureGetTexture
  [SIM] Q3: [desktop embedder]   MetalPerformanceShaders: 1 missing, e.g. _OBJC_CLASS_$_MPSImageBilinearScale
  [SIM] Q3: [desktop embedder]   libswiftIOKit: 1 missing, e.g. __swift_FORCE_LOAD_$_swiftIOKit
  [SIM] Q3: [desktop embedder]   libswiftMetal: 1 missing, e.g. __swift_FORCE_LOAD_$_swiftMetal
  [SIM] Q3: [desktop embedder] device SDK (watchos) direct check: 22 of 673 missing; delta vs watchsimulator: +0 libs, +0 / -0 syms
  [SIM] Q3: [iOS engine] ios_Flutter: 44 linked libraries, 1077 imported symbols
  [SIM] Q3: [iOS engine] libraries that exist on watchOS but at a flat path (macOS-style versioned path must be rewritten): 0
  [SIM] Q3: [iOS engine] libraries NOT provided by the watchOS SDK at all: AudioToolbox, IOSurface, WebKit, IOKit, Metal, MetalPerformanceShaders, _Translation_SwiftUI, libswiftCoreImage, libswiftMetal, libswiftQuartzCore
  [SIM] Q3: [iOS engine] imported symbols missing on watchOS (platform-filtered): 46 of 1077 (46 of those exist in the iOS Simulator SDK)
  [SIM] Q3: [iOS engine]   Metal: 14 missing, e.g. _MTLCommandBufferEncoderInfoErrorKey, _MTLCreateSystemDefaultDevice, _OBJC_CLASS_$_MTLCaptureManager, _OBJC_CLASS_$_MTLCommandBufferDescriptor, _OBJC_CLASS_$_MTLComputePipelineDescriptor
  [SIM] Q3: [iOS engine]   IOSurface: 10 missing, e.g. _IOSurfaceAlignProperty, _IOSurfaceCreate, _IOSurfaceSetValue, _kIOSurfaceAllocSize, _kIOSurfaceBytesPerElement
  [SIM] Q3: [iOS engine]   IOKit: 6 missing, e.g. _IOIteratorNext, _IOObjectRelease, _IORegistryEntryCreateCFProperties, _IOServiceGetMatchingServices, _IOServiceNameMatching
  [SIM] Q3: [iOS engine]   CoreVideo: 4 missing, e.g. _CVMetalTextureCacheCreate, _CVMetalTextureCacheCreateTextureFromImage, _CVMetalTextureCacheFlush, _CVMetalTextureGetTexture
  [SIM] Q3: [iOS engine]   UIKit: 3 missing, e.g. _OBJC_CLASS_$_UIEditMenuConfiguration, _OBJC_CLASS_$_UIEditMenuInteraction, _OBJC_CLASS_$_UIHoverGestureRecognizer
  [SIM] Q3: [iOS engine]   _Translation_SwiftUI: 2 missing, e.g. _$s7SwiftUI4ViewP013_Translation_aB0E23translationPresentation11isPresented4text16attachmentAnchor9arrowEdge17replacementActionQrAA7BindingVySbG_SSAA017PopoverAttachmentK0OAA0M0OySScSgtF, _$s7SwiftUI4ViewP013_Translation_aB0E23translationPresentation11isPresented4text16attachmentAnchor9arrowEdge17replacementActionQrAA7BindingVySbG_SSAA017PopoverAttachmentK0OAA0M0OySScSgtFQOMQ
  [SIM] Q3: [iOS engine]   libswiftQuartzCore: 2 missing, e.g. _$sSo16CAFrameRateRangeV10QuartzCoreE7minimum7maximum9preferredABSf_S2fSgtcfC, __swift_FORCE_LOAD_$_swiftQuartzCore
  [SIM] Q3: [iOS engine]   AudioToolbox: 1 missing, e.g. _AudioServicesPlaySystemSound
  [SIM] Q3: [iOS engine]   MetalPerformanceShaders: 1 missing, e.g. _OBJC_CLASS_$_MPSImageBilinearScale
  [SIM] Q3: [iOS engine]   WebKit: 1 missing, e.g. _OBJC_CLASS_$_WKWebView
  [SIM] Q3: [iOS engine]   libswiftCoreImage: 1 missing, e.g. __swift_FORCE_LOAD_$_swiftCoreImage
  [SIM] Q3: [iOS engine]   libswiftMetal: 1 missing, e.g. __swift_FORCE_LOAD_$_swiftMetal
  [SIM] Q3: [iOS engine] device SDK (watchos) direct check: 44 of 1077 missing; delta vs watchsimulator: +0 libs, +0 / -2 syms
  [SIM] Q3: [iOS engine]   still missed in watchsimulator: _$sSo16CAFrameRateRangeV10QuartzCoreE7minimum7maximum9preferredABSf_S2fSgtcfC (in libswiftQuartzCore), __swift_FORCE_LOAD_$_swiftQuartzCore (in libswiftQuartzCore)
  [SIM] Q4: retagged as watchOS Simulator (vtool platform 'watchossim', minos 10.0, sdk 26.5)
  [SIM] Q4: attempt 1 failed: DLOPEN FAIL: dlopen(/tmp/engine/watchos/FlutterEmbedder, 0x0006): Library not loaded: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
  [SIM] Q4: rewrote 8 macOS-style versioned framework paths to the flat watchOS layout
  [SIM] Q4: stubbing libraries the watchOS SDK lacks: ApplicationServices, OpenGL, AppKit, Metal, MetalPerformanceShaders, libswiftIOKit, libswiftMetal
  [SIM] Q4:   ApplicationServices is imported for: 
  [SIM] Q4:   stub ApplicationServices: defines 0 symbols
  [SIM] Q4:   OpenGL is imported for: 
  [SIM] Q4:   stub OpenGL: defines 0 symbols
  [SIM] Q4:   AppKit is imported for: _OBJC_CLASS_$_NSFont
  [SIM] Q4:   AppKit: real implementation for _OBJC_CLASS_$_NSFont
  [SIM] Q4:   stub AppKit: defines 1 symbols
  [SIM] Q4:   Metal is imported for: _MTLCommandBufferEncoderInfoErrorKey, _MTLCreateSystemDefaultDevice, _OBJC_CLASS_$_MTLCaptureManager, _OBJC_CLASS_$_MTLCommandBufferDescriptor, _OBJC_CLASS_$_MTLCompileOptions, _OBJC_CLASS_$_MTLComputePipelineDescriptor, _OBJC_CLASS_$_MTLDepthStencilDescriptor, _OBJC_CLASS_$_MTLFunctionConstantValues, _OBJC_CLASS_$_MTLRenderPassDescriptor, _OBJC_CLASS_$_MTLRenderPipelineColorAttachmentDescriptor, _OBJC_CLASS_$_MTLRenderPipelineDescriptor, _OBJC_CLASS_$_MTLSamplerDescriptor ...
  [SIM] Q4:   stub Metal: defines 15 symbols
  [SIM] Q4:   MetalPerformanceShaders is imported for: _OBJC_CLASS_$_MPSImageBilinearScale
  [SIM] Q4:   stub MetalPerformanceShaders: defines 1 symbols
  [SIM] Q4:   libswiftIOKit is imported for: __swift_FORCE_LOAD_$_swiftIOKit
  [SIM] Q4:   stub libswiftIOKit: defines 1 symbols
  [SIM] Q4:   libswiftMetal is imported for: __swift_FORCE_LOAD_$_swiftMetal
  [SIM] Q4:   stub libswiftMetal: defines 1 symbols
  [SIM] Q4: symbols missing from libraries the watchOS SDK does have: 4 e.g. _CVMetalTextureCacheCreate (in CoreVideo), _CVMetalTextureCacheCreateTextureFromImage (in CoreVideo), _CVMetalTextureCacheFlush (in CoreVideo), _CVMetalTextureGetTexture (in CoreVideo)
  [SIM] Q4: attempt 2 failed: DLOPEN FAIL: dlopen(/tmp/engine/watchos/FlutterEmbedder, 0x0006): Symbol not found: _CVMetalTextureCacheCreate
  [SIM] Q4:   overlay CoreVideo: now defines 1 symbol(s), re-exports the real library
  [SIM] Q4:   overlay CoreVideo: now defines 2 symbol(s), re-exports the real library
  [SIM] Q4:   overlay CoreVideo: now defines 3 symbol(s), re-exports the real library
  [SIM] Q4:   overlay CoreVideo: now defines 4 symbol(s), re-exports the real library
  [SIM] Q4: loaded after 4 overlaid symbol(s)
  [SIM] Q4: SYMBOL FlutterEngineRun: found
  [SIM] Q4: SYMBOL FlutterEngineSendWindowMetricsEvent: found
  [SIM] Q4: SYMBOL FlutterEngineShutdown: found
  [SIM] Q5: host compiled for watchOS Simulator against the real embedder.h
  [SIM] Q5: snapshot symbols exported by the engine library: _kDartSnapshotData _kDartSnapshotText 
  [SIM] Q5: host: FlutterEngineRun -> 0
  [SIM] Q5: host: [engine flutter] The Dart VM service is listening on http://127.0.0.1:50060/O6mv_rHXaog=/
  [SIM] Q5: host: frames presented: 2
  [P2] P2: pixelRatio 1.0 -> 191664 bytes, 15 ms
  [P2] P2: pixelRatio 2.0 -> 766656 bytes, 0 ms
  [X1] INFO: extracted flutter_proofs/lib/spec/watch_frame_streamer.dart (90 lines)
  [X1] INFO: extracted flutter_proofs/lib/spec/watch_input_injector.dart (26 lines)
  [S1] S1: hasScheduledFrame right after start() = false
  [S1] S1: after first settle: frames=1
  [S1] S1: after tap: taps=1 frames=2
  [S1] S1: 2 frames captured at 800x600
  [S7] S7: idle app, frames received by itself = 0
  [S7] S7: after captureNow frames received = 1
  [P1] INFO: watch simulator Apple Watch Series 11 (46mm) (watchOS-26-5) C5E1D47B-37DC-46A5-9DDA-907CAC9587CD
  [P0] INFO: scheme WatchProofs (schemes:  WatchProofs )
  [X2] INFO: extracted swift_spec/Sources/SpecCode/ColorARGB.swift (12 lines)
  [X2] INFO: extracted swift_spec/Sources/SpecCode/WatchFrame.swift (25 lines)
  [X2] INFO: extracted swift_spec/Sources/SpecCode/WatchRender.swift (178 lines)
  [SIM] P6: received 191664 bytes over loopback in 291 ms
  [SIM] A1: lit pixels topLeading=47 center=10
  [SIM] A4: symbol found via process
  [SIM] P9: ratio=1.0 mode=delta wire=922 B/frame, 38.1 ms/frame (26 fps max), decode 37.7 ms/frame
  [SIM] P9: ratio=1.0 mode=raw wire=191668 B/frame, 1.5 ms/frame (658 fps max), decode 0.1 ms/frame
  [SIM] P9: ratio=1.0 mode=zlib wire=1047 B/frame, 2.5 ms/frame (403 fps max), decode 2.2 ms/frame
  [SIM] P9: ratio=2.0 mode=delta wire=3495 B/frame, 151.3 ms/frame (6 fps max), decode 150.9 ms/frame
  [SIM] P9: ratio=2.0 mode=raw wire=766660 B/frame, 8.6 ms/frame (116 fps max), decode 0.2 ms/frame
  [SIM] P9: ratio=2.0 mode=zlib wire=3935 B/frame, 8.9 ms/frame (112 fps max), decode 8.6 ms/frame
  [SIM] S3: 2px, 4px and 16px captures of one picture all fill the view the same way
  [SIM] S4: renderer reported invalidation = true
  [SIM] S6: renderer reported invalidation after submit = true
======== END ========
```

## `watchos_ui` Linux CI *(if triggered)*

Not triggered on commit `740962b` (`packages/watchos_ui/**` unchanged; `.github/workflows/watchos_ui.yml` supports `workflow_dispatch`).
