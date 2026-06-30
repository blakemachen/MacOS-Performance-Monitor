import Foundation
import Darwin

// MARK: - Memory

public struct MemoryStats {
    public let total: UInt64
    public let used: UInt64
    public let free: UInt64
    public let active: UInt64
    public let inactive: UInt64
    public let wired: UInt64
    public let compressed: UInt64

    public static let zero = MemoryStats(total: 0, used: 0, free: 0, active: 0,
                                         inactive: 0, wired: 0, compressed: 0)

    /// 0...1 fraction of physical memory in active use.
    public var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

// MARK: - Per-core CPU sampler

/// Samples per-core CPU load by diffing kernel tick counters between calls.
public final class CPUSampler {
    private var previous: [(user: Double, system: Double, idle: Double, nice: Double)] = []

    public init() {}

    /// Returns each core's busy fraction (0...1). First call returns zeros (no baseline yet).
    public func sampleCores() -> [Double] {
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else {
            return previous.map { _ in 0 }
        }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: UnsafeRawPointer(info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let n = Int(cpuCount)
        let states = Int(CPU_STATE_MAX)
        var current: [(Double, Double, Double, Double)] = []
        current.reserveCapacity(n)
        var usages: [Double] = []
        usages.reserveCapacity(n)

        for i in 0..<n {
            let base = i * states
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            current.append((user, system, idle, nice))

            if i < previous.count {
                let p = previous[i]
                let dUser = user - p.user, dSystem = system - p.system
                let dIdle = idle - p.idle, dNice = nice - p.nice
                let totalDelta = dUser + dSystem + dIdle + dNice
                usages.append(totalDelta > 0 ? (dUser + dSystem + dNice) / totalDelta : 0)
            } else {
                usages.append(0)
            }
        }

        previous = current
        return usages
    }
}

// MARK: - One-shot system queries

public enum SystemStats {
    public static func memory() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .zero }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)

        let total = ProcessInfo.processInfo.physicalMemory
        let free = UInt64(stats.free_count) * page
        let active = UInt64(stats.active_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        // Activity-Monitor-style "in use": wired + active + compressed. Inactive is cached/reclaimable.
        let used = wired + active + compressed

        return MemoryStats(total: total, used: used, free: free, active: active,
                           inactive: inactive, wired: wired, compressed: compressed)
    }

    /// Logical core count.
    public static var coreCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// Marketing CPU name, e.g. "Intel Core i7".
    public static var cpuBrand: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "CPU" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
