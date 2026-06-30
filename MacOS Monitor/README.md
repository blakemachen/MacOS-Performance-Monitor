# PerfMonitor

A lightweight native macOS app showing **live system performance** — CPU usage & temperature, memory usage, and GPU temperature — in a clean tabbed SwiftUI interface.

![tabs: CPU · Memory · Temps](#)

## Features

- **CPU tab** — overall load ring, per-core load bars, CPU model, live temperature, and a sparkline history.
- **Memory tab** — used / free ring plus a breakdown of Wired / Active / Compressed / Cached / Free.
- **Temps tab** — headline CPU & GPU temperatures, plus every thermal sensor the Mac exposes, read live.
- Refresh rate selector (0.5s / 1s / 2s) in the footer.
- **Light:** ~4–5% CPU foreground, ~37 MB RAM. One timer drives all sampling; history buffers are bounded.

## How it works

| Metric | Source |
| --- | --- |
| CPU load (per-core) | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, diffed between samples |
| Memory | `host_statistics64(HOST_VM_INFO64)` + `ProcessInfo.physicalMemory` |
| Temperatures | Apple SMC over IOKit (`AppleSMC` user client), `sp78` / `flt` decoding |

No private frameworks. Temperature support works on **Intel Macs** (this is where the SMC exposes
`TC**` CPU and `TG**` GPU sensors). On Apple Silicon the SMC keys differ, so the Temps tab will
show fewer/no sensors and fall back gracefully to "N/A".

## Build & run

Requires the Swift toolchain (Xcode or Command Line Tools).

```bash
# Build a double-clickable app bundle:
./build_app.sh
open PerfMonitor.app

# …or run directly during development:
swift run PerfMonitor

# Validate the sensor layer headlessly (CPU, memory, all temps):
swift run smcdump
```

## Project layout

```
Sources/
  PerfKit/            # pure data layer (no SwiftUI)
    SMC.swift         #   SMC temperature reader over IOKit
    SystemStats.swift #   mach-based CPU + memory sampling
  PerfMonitor/        # the SwiftUI app
    PerfMonitorApp.swift  # @main App + Monitor (single 1s timer)
    ContentView.swift     # tabs + reusable gauge/sparkline components
  smcdump/            # headless CLI used to validate sensor reads
```

## Note on SMC struct layout

The `SMCKeyInfo` struct is explicitly padded to 12 bytes. Swift would otherwise reuse a nested
struct's trailing padding, shrinking the parameter struct from 80 → 76 bytes, which the AppleSMC
kernel call rejects (every read returns failure). See the comment in `SMC.swift`.
