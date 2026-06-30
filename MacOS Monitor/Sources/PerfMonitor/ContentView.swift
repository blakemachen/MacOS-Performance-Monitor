import SwiftUI
import PerfKit

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                CPUTab().tabItem { Label("CPU", systemImage: "cpu") }
                MemoryTab().tabItem { Label("Memory", systemImage: "memorychip") }
                TempsTab().tabItem { Label("Temps", systemImage: "thermometer.medium") }
            }
            .padding(14)

            Divider()
            FooterView()
        }
        .background(BackgroundView())
    }
}

// MARK: - CPU

struct CPUTab: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    HStack(spacing: 22) {
                        RingGauge(value: monitor.cpu,
                                  label: "\(Int((monitor.cpu * 100).rounded()))%",
                                  caption: "CPU",
                                  tint: Palette.heat(monitor.cpu))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(monitor.cpuBrand)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("\(monitor.coreCount) logical cores")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let t = monitor.cpuTemp {
                                Label(Format.temp(t), systemImage: "thermometer.medium")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Palette.heatTemp(t))
                            }
                            Spacer(minLength: 0)
                            Sparkline(values: monitor.cpuHistory, tint: Palette.heat(monitor.cpu))
                                .frame(height: 38)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Per-core load").font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        let columns = [GridItem(.adaptive(minimum: 130), spacing: 10)]
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(monitor.cores.enumerated()), id: \.offset) { idx, load in
                                CoreBar(index: idx, load: load)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CoreBar: View {
    let index: Int
    let load: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Core \(index)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((load * 100).rounded()))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressBar(value: load, tint: Palette.heat(load))
        }
    }
}

// MARK: - Memory

struct MemoryTab: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    HStack(spacing: 22) {
                        RingGauge(value: monitor.memory.usedFraction,
                                  label: "\(Int((monitor.memory.usedFraction * 100).rounded()))%",
                                  caption: "USED",
                                  tint: Palette.heat(monitor.memory.usedFraction))
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(Format.bytes(monitor.memory.used)) of \(Format.bytes(monitor.memory.total))")
                                .font(.headline)
                            Text("\(Format.bytes(monitor.memory.free)) free")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Sparkline(values: monitor.memHistory,
                                      tint: Palette.heat(monitor.memory.usedFraction))
                                .frame(height: 38)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Card {
                    VStack(spacing: 10) {
                        MemoryRow(label: "Wired", color: .pink,
                                  bytes: monitor.memory.wired, total: monitor.memory.total)
                        MemoryRow(label: "Active", color: .blue,
                                  bytes: monitor.memory.active, total: monitor.memory.total)
                        MemoryRow(label: "Compressed", color: .purple,
                                  bytes: monitor.memory.compressed, total: monitor.memory.total)
                        MemoryRow(label: "Cached (inactive)", color: .teal,
                                  bytes: monitor.memory.inactive, total: monitor.memory.total)
                        MemoryRow(label: "Free", color: .green,
                                  bytes: monitor.memory.free, total: monitor.memory.total)
                    }
                }
            }
        }
    }
}

struct MemoryRow: View {
    let label: String
    let color: Color
    let bytes: UInt64
    let total: UInt64

    private var fraction: Double { total > 0 ? Double(bytes) / Double(total) : 0 }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.subheadline)
                Spacer()
                Text(Format.bytes(bytes))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressBar(value: fraction, tint: color)
        }
    }
}

// MARK: - Temperatures

struct TempsTab: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !monitor.smcAvailable {
                    Card {
                        Label("Temperature sensors unavailable on this system.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 14) {
                    TempBadge(title: "CPU", value: monitor.cpuTemp,
                              history: monitor.cpuTempHistory)
                    TempBadge(title: "GPU", value: monitor.gpuTemp, history: [])
                }

                if !monitor.sensors.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("All sensors").font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(monitor.sensors) { sensor in
                                HStack {
                                    Text(sensor.name).font(.subheadline)
                                    Text(sensor.id).font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(Format.temp(sensor.celsius))
                                        .font(.subheadline.monospacedDigit().weight(.medium))
                                        .foregroundStyle(Palette.heatTemp(sensor.celsius))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TempBadge: View {
    let title: String
    let value: Double?
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let value {
                    Text(Format.temp(value))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.heatTemp(value))
                    if !history.isEmpty {
                        Sparkline(values: history.map { Palette.tempFraction($0) },
                                  tint: Palette.heatTemp(value))
                            .frame(height: 28)
                    }
                } else {
                    Text("N/A")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Text("no sensor").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 7, height: 7)
            Text("Live").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("Refresh").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $monitor.interval) {
                Text("0.5s").tag(0.5)
                Text("1s").tag(1.0)
                Text("2s").tag(2.0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Reusable components

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Solid translucent fill instead of a material: no per-frame backdrop
            // blur, so the window stays cheap to composite while idle.
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1)
            )
    }
}

struct RingGauge: View {
    let value: Double          // 0...1
    let label: String
    let caption: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.7), tint],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 116, height: 116)
    }
}

struct ProgressBar: View {
    let value: Double          // 0...1
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

struct Sparkline: View {
    let values: [Double]       // each 0...1
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    // Soft area fill under the line.
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let clamped = max(0, min(1, v))
            return CGPoint(x: CGFloat(i) * stepX,
                           y: size.height - CGFloat(clamped) * size.height)
        }
    }
}

struct BackgroundView: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.10),
                                Color(red: 0.10, green: 0.10, blue: 0.13)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

// MARK: - Formatting & color

enum Format {
    static func bytes(_ value: UInt64) -> String {
        let gb = Double(value) / (1024 * 1024 * 1024)
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(value) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }

    static func temp(_ celsius: Double) -> String {
        String(format: "%.0f°C", celsius)
    }
}

enum Palette {
    /// Green → yellow → red for a 0...1 load.
    static func heat(_ value: Double) -> Color {
        let v = max(0, min(1, value))
        let hue = (1 - v) * 0.33      // 0.33 green → 0.0 red
        return Color(hue: hue, saturation: 0.85, brightness: 0.95)
    }

    /// Map an absolute temperature (≈35–95°C) to a heat color.
    static func heatTemp(_ celsius: Double) -> Color {
        heat(tempFraction(celsius))
    }

    static func tempFraction(_ celsius: Double) -> Double {
        max(0, min(1, (celsius - 35) / 60))
    }
}
