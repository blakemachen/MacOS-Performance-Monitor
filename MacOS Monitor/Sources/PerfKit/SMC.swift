import Foundation
import IOKit

// MARK: - Public model

/// A single temperature reading from the SMC.
public struct TempSensor: Identifiable, Hashable {
    public let id: String       // raw 4-char SMC key, e.g. "TC0P"
    public let name: String     // friendly label
    public let celsius: Double

    public var category: TempCategory {
        if id.hasPrefix("TC") || id == "TCXC" || id == "TCXr" { return .cpu }
        if id.hasPrefix("TG") { return .gpu }
        return .other
    }
}

public enum TempCategory { case cpu, gpu, other }

// MARK: - SMC reader

/// Minimal, allocation-light reader for the Apple System Management Controller.
/// Reads temperature sensors over IOKit. No private frameworks; works on Intel Macs.
public final class SMC {
    private var connection: io_connect_t = 0
    private var isOpen = false

    // Kernel selectors / SMC sub-commands.
    private let kernelIndex: UInt32 = 2
    private let cmdReadBytes: UInt8 = 5
    private let cmdReadIndex: UInt8 = 8
    private let cmdReadKeyInfo: UInt8 = 9

    public init() { open() }
    deinit { close() }

    @discardableResult
    public func open() -> Bool {
        if isOpen { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        isOpen = (result == kIOReturnSuccess)
        return isOpen
    }

    public func close() {
        if isOpen {
            IOServiceClose(connection)
            isOpen = false
        }
    }

    public var available: Bool { isOpen }

    // MARK: Reading

    /// Read a single key, decoding it to a Double when the type is understood.
    public func readDouble(_ key: String) -> Double? {
        guard isOpen, let info = readKeyInfo(key) else { return nil }
        var input = SMCParam()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = cmdReadBytes
        var output = SMCParam()
        guard call(&input, &output), output.result == 0 else { return nil }

        let type = Self.string(from: info.dataType)
        let bytes = Self.toArray(output.bytes, count: Int(info.dataSize))
        return Self.decode(type: type, bytes: bytes)
    }

    /// Discover every temperature key the machine exposes and read it once.
    /// Returns only sensors with physically plausible values. Used at startup;
    /// callers should cache `id`s and use `readTemperatures(keys:)` afterwards.
    public func discoverTemperatureSensors() -> [TempSensor] {
        let keys = allKeys().filter { $0.hasPrefix("T") }
        return readTemperatures(keys: keys)
    }

    /// Read a known set of temperature keys. Cheap enough to call once per tick.
    public func readTemperatures(keys: [String]) -> [TempSensor] {
        keys.compactMap { key in
            // Internal sensors on a powered machine read well above 10°C; values
            // below that are placeholder/threshold keys, not live temperatures.
            guard let value = readDouble(key), value > 10, value < 150 else { return nil }
            return TempSensor(id: key, name: Self.friendlyName(key), celsius: value)
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: Key enumeration

    private func allKeys() -> [String] {
        guard let count = readDouble("#KEY").map({ Int($0) }), count > 0 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(count)
        for index in 0..<count {
            var input = SMCParam()
            input.data8 = cmdReadIndex
            input.data32 = UInt32(index)
            var output = SMCParam()
            if call(&input, &output), output.result == 0 {
                keys.append(Self.string(from: output.key))
            }
        }
        return keys
    }

    private func readKeyInfo(_ key: String) -> SMCKeyInfo? {
        var input = SMCParam()
        input.key = Self.fourCC(key)
        input.data8 = cmdReadKeyInfo
        var output = SMCParam()
        guard call(&input, &output), output.result == 0 else { return nil }
        return output.keyInfo
    }

    private func call(_ input: inout SMCParam, _ output: inout SMCParam) -> Bool {
        let inputSize = MemoryLayout<SMCParam>.stride
        var outputSize = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(connection, kernelIndex, &input, inputSize, &output, &outputSize)
        return r == kIOReturnSuccess
    }

    // MARK: Decoding

    private static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8 ", "si8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            // Fixed-point "spXY" (signed) / "fpXY" (unsigned): last hex digit = fractional bits.
            if (type.hasPrefix("sp") || type.hasPrefix("fp")), type.count == 4, bytes.count >= 2 {
                let fracChar = type[type.index(type.startIndex, offsetBy: 3)]
                guard let frac = Int(String(fracChar), radix: 16) else { return nil }
                let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
                if type.hasPrefix("sp") {
                    return Double(Int16(bitPattern: raw)) / Double(1 << frac)
                }
                return Double(raw) / Double(1 << frac)
            }
            return nil
        }
    }

    // MARK: FourCC helpers

    private static func fourCC(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in s.utf8.prefix(4) { result = (result << 8) | UInt32(byte) }
        return result
    }

    private static func string(from code: UInt32) -> String {
        let chars = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
                     UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: chars, encoding: .ascii) ?? ""
    }

    private static func toArray(_ tuple: SMCBytes, count: Int) -> [UInt8] {
        var copy = tuple
        return withUnsafeBytes(of: &copy) { Array($0.prefix(max(0, min(count, 32)))) }
    }

    // MARK: Friendly names (common Intel SMC keys)

    private static let names: [String: String] = [
        "TC0P": "CPU Proximity", "TC0D": "CPU Die", "TC0E": "CPU PECI Die",
        "TC0F": "CPU PECI Die Filtered", "TC0H": "CPU Heatsink", "TCXC": "CPU Package (PECI)",
        "TCAD": "CPU Package", "TCGC": "Intel GPU", "TCSA": "CPU System Agent",
        "TCMX": "CPU Max",
        "TG0P": "GPU Proximity", "TG0D": "GPU Die", "TGDD": "GPU Die (discrete)",
        "TG0H": "GPU Heatsink", "TGDE": "GPU Die 2", "TGVP": "GPU VRM", "TG1P": "GPU Proximity 2",
        "TA0P": "Ambient", "Ta0P": "Airflow", "TaLP": "Airflow Left", "TaRP": "Airflow Right",
        "Th0H": "Heatpipe 1", "Th1H": "Heatpipe 2", "Th2H": "Heatpipe 3",
        "Tm0P": "Mainboard", "TM0P": "Memory Proximity", "Tp0P": "Power Supply",
        "Ts0P": "Palm Rest", "Ts1P": "Palm Rest 2", "Ts0S": "Skin",
        "TB0T": "Battery", "TB1T": "Battery 2", "TB2T": "Battery 3",
        "TW0P": "Wireless", "TL0P": "Display", "TPCD": "Platform Controller Hub",
        "TI0P": "Thunderbolt 1", "TI1P": "Thunderbolt 2",
        "TN0D": "Northbridge Die", "TN0P": "Northbridge Proximity",
    ]

    private static func friendlyName(_ key: String) -> String {
        if let name = names[key] { return name }
        // Per-core CPU dies appear as TC1C … TC6C.
        if key.count == 4, key.hasPrefix("TC"), key.hasSuffix("C"),
           let core = Int(String(key[key.index(key.startIndex, offsetBy: 2)])) {
            return "CPU Core \(core)"
        }
        return key
    }
}

// MARK: - Raw SMC struct layout (mirrors the AppleSMC kernel struct, 80 bytes)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // Explicit trailing padding so Swift's size == C's stride (12 bytes).
    // Without this, Swift reuses the slack for later fields and the struct
    // shrinks to 76 bytes, which the AppleSMC kernel call rejects.
    private var pad0: UInt8 = 0
    private var pad1: UInt8 = 0
    private var pad2: UInt8 = 0
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCParam {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}
