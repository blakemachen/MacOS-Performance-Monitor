import Foundation
import PerfKit

// Quick headless sanity check for the sensor layer.
let smc = SMC()
print("SMC connection open: \(smc.available)")

let sensors = smc.discoverTemperatureSensors()
print("Discovered \(sensors.count) temperature sensor(s):\n")
for s in sensors {
    print(String(format: "  %-6@ %-26@ %6.1f °C", s.id as NSString, s.name as NSString, s.celsius))
}

print("\nMemory:")
let mem = SystemStats.memory()
let gb = 1024.0 * 1024.0 * 1024.0
print(String(format: "  total %.1f GB  used %.1f GB  free %.1f GB  (%.0f%%)",
             Double(mem.total) / gb, Double(mem.used) / gb,
             Double(mem.free) / gb, mem.usedFraction * 100))

print("\nCPU (\(SystemStats.coreCount) cores — \(SystemStats.cpuBrand)):")
let cpu = CPUSampler()
_ = cpu.sampleCores()          // prime baseline
Thread.sleep(forTimeInterval: 0.5)
let cores = cpu.sampleCores()
let avg = cores.isEmpty ? 0 : cores.reduce(0, +) / Double(cores.count)
print(String(format: "  overall %.0f%%", avg * 100))
for (i, c) in cores.enumerated() {
    print(String(format: "  core %2d: %.0f%%", i, c * 100))
}
