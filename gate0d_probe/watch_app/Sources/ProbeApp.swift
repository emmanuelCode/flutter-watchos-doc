import Gate0dProbeCore
import SwiftUI

@main
struct Gate0dProbeApp: App {
    @StateObject private var runner = ProbeRunner()

    var body: some Scene {
        WindowGroup {
            ProbeRootView(runner: runner)
        }
    }
}

struct ProbeRootView: View {
    @ObservedObject var runner: ProbeRunner
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var hostIP = ""
    @State private var localHost = ""
    @State private var tcpPortText = "8770"
    @State private var httpPortText = "8771"
    @State private var iphoneLink: IPhoneLinkState = .available
    @State private var lanInternet: LanRouterInternetState = .yes
    @State private var confirmRamp = false

    private var currentConfig: ProbeRunConfig {
        ProbeRunConfig(
            hostIP: hostIP,
            localHost: localHost,
            tcpPort: UInt16(tcpPortText) ?? 8770,
            httpPort: UInt16(httpPortText) ?? 8771,
            httpsPort: nil,
            iphoneLink: iphoneLink,
            lanRouterInternet: lanInternet
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gate 0d Hardware Probe")
                        .font(.headline)

                    Group {
                        Text("Model: \(runner.currentContext.deviceModel)")
                        Text("Screen: \(runner.currentContext.screenPtString) @\(runner.currentContext.screenScaleString)x")
                        Text("Launch: \(runner.currentContext.launchMode)")
                        Text("ATS: \(runner.currentContext.atsProfile)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Divider()

                    TextField("Mac LAN IP (optional)", text: $hostIP)
                    TextField("Mac .local (optional)", text: $localHost)
                    HStack {
                        TextField("TCP", text: $tcpPortText)
                        TextField("HTTP", text: $httpPortText)
                    }

                    Picker("iPhone Link", selection: $iphoneLink) {
                        ForEach(IPhoneLinkState.allCases, id: \.self) { state in
                            Text(state.rawValue).tag(state)
                        }
                    }

                    Picker("Router Net", selection: $lanInternet) {
                        ForEach(LanRouterInternetState.allCases, id: \.self) { state in
                            Text(state.rawValue).tag(state)
                        }
                    }

                    Button(runner.isRunning ? "Running..." : "Run Required Suite") {
                        Task { await runner.runRequiredSuite(config: currentConfig, luminanceReduced: isLuminanceReduced) }
                    }
                    .disabled(runner.isRunning)
                    .buttonStyle(.borderedProminent)

                    HStack {
                        Button("JIT") {
                            Task { await runner.rerunJit(config: currentConfig, luminanceReduced: isLuminanceReduced) }
                        }
                        Button("Net") {
                            Task { await runner.rerunNetwork(config: currentConfig, luminanceReduced: isLuminanceReduced) }
                        }
                        Button("Decode") {
                            Task { await runner.rerunDecode(config: currentConfig, luminanceReduced: isLuminanceReduced) }
                        }
                    }
                    .font(.caption2)
                    .disabled(runner.isRunning)

                    Button("Run Memory Ramp (Will Crash)") {
                        confirmRamp = true
                    }
                    .font(.caption2)
                    .tint(.red)
                    .disabled(runner.isRunning)
                    .confirmationDialog("Run Memory Ramp?", isPresented: $confirmRamp) {
                        Button("Start Crash Ramp", role: .destructive) {
                            Task { await runner.runOptInMemoryRamp(config: currentConfig, luminanceReduced: isLuminanceReduced) }
                        }
                    }

                    Text("Status: \(runner.statusMessage)")
                        .font(.caption2)

                    if !runner.latestReportText.isEmpty {
                        ShareLink(item: runner.latestReportText) {
                            Label("Share Result Block", systemImage: "square.and.arrow.up")
                        }
                        .font(.caption)

                        // NOTE: .textSelection is not available on watchOS, so the block is shown
                        // read-only here; use Share, the Xcode console, or the saved file.
                        Text(runner.latestReportText)
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Gate 0d")
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    runner.abortDueToSceneExit()
                } else {
                    runner.refreshContext(luminanceReduced: isLuminanceReduced)
                }
            }
            .onChange(of: isLuminanceReduced) { _, newVal in
                runner.refreshContext(luminanceReduced: newVal)
            }
        }
    }
}
