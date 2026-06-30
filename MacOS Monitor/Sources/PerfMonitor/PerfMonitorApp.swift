import SwiftUI
import PerfKit

@main
struct PerfMonitorApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        WindowGroup("Performance") {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 480, idealWidth: 520, minHeight: 480, idealHeight: 540)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Single source of truth. One timer drives all sampling; history buffers are bounded.
@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var cpu: Double = 0          // 0...1 overall
    @Published private(set) var cores: [Double] = []
    @Published private(set) var memory: MemoryStats = .zero
    @Published private(set) var sensors: [TempSensor] = []
    @Published private(set) var cpuTemp: Double? = nil
    @Published private(set) var gpuTemp: Double? = nil

    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []
    @Published private(set) var cpuTempHistory: [Double] = []

    /// Seconds between samples. Changing it restarts the timer.
    @Published var interval: Double = 1.0 {
        didSet { if interval != oldValue { start() } }
    }

    let coreCount = SystemStats.coreCount
    let cpuBrand = SystemStats.cpuBrand
    let smcAvailable: Bool

    private let cpuSampler = CPUSampler()
    private let smc = SMC()
    private var tempKeys: [String] = []
    private var timer: Timer?
    private let maxHistory = 60

    init() {
        smcAvailable = smc.available
        // Discover temperature sensors once; only re-read these keys per tick.
        let discovered = smc.discoverTemperatureSensors()
        sensors = discovered
        tempKeys = discovered.map(\.id)
        updateTempSummary()
        _ = cpuSampler.sampleCores()   // establish CPU baseline
        start()
    }

    private func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so we are already on the main actor.
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keep updating during resize/menus
        timer = t
    }

    private func tick() {
        let coreUsages = cpuSampler.sampleCores()
        cores = coreUsages
        cpu = coreUsages.isEmpty ? 0 : coreUsages.reduce(0, +) / Double(coreUsages.count)
        memory = SystemStats.memory()

        if !tempKeys.isEmpty {
            sensors = smc.readTemperatures(keys: tempKeys)
            updateTempSummary()
        }

        push(&cpuHistory, cpu)
        push(&memHistory, memory.usedFraction)
        if let cpuTemp { push(&cpuTempHistory, cpuTemp) }
    }

    private func updateTempSummary() {
        // Prefer the package/PECI die reading; fall back to other CPU sensors.
        cpuTemp = pickTemp(priority: ["TCXC", "TC0E", "TC0F", "TCAD", "TC0D", "TC0P", "TCMX"],
                           category: .cpu)
        // Prefer the discrete GPU die; fall back to proximity.
        gpuTemp = pickTemp(priority: ["TGDD", "TGDE", "TG0D", "TG0P", "TG0H"],
                           category: .gpu)
    }

    /// Prefer a specific sensor key; otherwise average all sensors in the category.
    private func pickTemp(priority: [String], category: TempCategory) -> Double? {
        for key in priority {
            if let s = sensors.first(where: { $0.id == key }) { return s.celsius }
        }
        let group = sensors.filter { $0.category == category }
        guard !group.isEmpty else { return nil }
        return group.map(\.celsius).reduce(0, +) / Double(group.count)
    }

    private func push(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > maxHistory { buffer.removeFirst(buffer.count - maxHistory) }
    }
}
