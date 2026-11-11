import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func networkAndAudioDevices() {
        check("network: format", NetworkRate.format(512) == "512 B/s" && NetworkRate.format(1_500) == "1.5 KB/s" && NetworkRate.format(2_300_000) == "2.3 MB/s")
        let a = ["en0": (rx: UInt32.max - 99, tx: UInt32(0))], b = ["en0": (rx: UInt32(100), tx: UInt32(500)), "new": (rx: UInt32(9), tx: UInt32(9))]
        let r = NetworkRate.rate(from: a, to: b, seconds: 2)
        check("network: rate survives counter wrap and ignores new interfaces", r.down == 100 && r.up == 250, "\(r)")
        check("network: counters are readable", !NetworkRate.counters().isEmpty)

        let devs = AudioControl.outputDevices()
        check("audio: output devices listed with names", !devs.isEmpty && devs.allSatisfy { !$0.name.isEmpty }, "\(devs.count)")
        check("audio: the current output is one of them", AudioControl.currentOutput().map { id in devs.contains { $0.id == id } } == true)
    }

    static func bluetoothBatteries() {
        // Bluetooth batteries
        let bt = #"{"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro":{"device_batteryLevelLeft":"85%","device_batteryLevelRight":"80%","device_batteryLevelCase":"60%"}},{"Magic Mouse":{"device_batteryLevelMain":"42%"}},{"Keyboard":{"device_address":"x"}}]}]}"#
        let lines = BluetoothBattery.parse(Data(bt.utf8))
        check("bluetooth: AirPods per bud and case, others by main level, no battery means no line", lines == ["AirPods Pro: L 85% · R 80% · Case 60%", "Magic Mouse: 42%"], "\(lines)")
        check("bluetooth: garbage gives nothing", BluetoothBattery.parse(Data("{}".utf8)).isEmpty && BluetoothBattery.parse(Data("x".utf8)).isEmpty)
        _ = BluetoothBattery.read()   // crash test only: the real system_profiler call must not crash or hang, no value is checked
    }

    static func displayOptions() {
        // Display options
        check("display: an unknown display name falls back to automatic", { UserDefaults.standard.set("No Such Display", forKey: "targetDisplay"); defer { UserDefaults.standard.removeObject(forKey: "targetDisplay") }; return NotchGeometry.detect().screen != nil }())
    }

    static func externalBrightness() {
        let ddc = ExternalBrightness.packet(percent: 50)
        let checksum: UInt8 = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 50
        check("ddc: brightness packet is 0x84 0x03 0x10 with the value and a checksum over both addresses",
              ddc == [0x84, 0x03, 0x10, 0x00, 50, checksum] && ExternalBrightness.packet(percent: 250)[4] == 100, "\(ddc)")
    }

    static func extraBrightness() {
        check("extra brightness: off in low power, on a low battery off the charger, or when hot",
              ExtraBrightness.allowed(lowPower: false, batteryLevel: 80, pluggedIn: false, thermal: .nominal) && !ExtraBrightness.allowed(lowPower: true, batteryLevel: 80, pluggedIn: true, thermal: .nominal)
              && !ExtraBrightness.allowed(lowPower: false, batteryLevel: 15, pluggedIn: false, thermal: .nominal) && ExtraBrightness.allowed(lowPower: false, batteryLevel: 15, pluggedIn: true, thermal: .fair)
              && !ExtraBrightness.allowed(lowPower: false, batteryLevel: 80, pluggedIn: true, thermal: .serious))
    }

    static func terminalEnvironment() {
        let env = TerminalSession.sanitized(["PATH=/usr/bin", "PWD=/somewhere", "OLDPWD=/else", "CLAUDE_PROJECT_DIR=/proj", "TERM=xterm", "INIT_CWD=/x"], home: "/Users/me")
        check("terminal: inherited directory variables are dropped and PWD is the home folder", env.sorted() == ["PATH=/usr/bin", "PWD=/Users/me", "TERM=xterm"], "\(env)")
    }

    static func battery() {
        let now = Date()
        func at(_ min: Double, _ level: Int, _ ch: Bool = false) -> BatterySample { BatterySample(t: now.addingTimeInterval(-min * 60), level: level, charging: ch) }
        let h = BatteryMath.trimmed([at(10, 50), at(49 * 60, 90), at(5, 49), at(47 * 60, 80), at(-30, 10)], now: now)
        check("battery history: keeps 48 h, oldest first, drops the future", h.map(\.level) == [80, 50, 49], "\(h.map(\.level))")
        check("battery drain: points lost per 10 min off the charger", BatteryMath.drainPer10Min([at(12, 60), at(6, 57), at(0, 54)], now: now) == 5)
        check("battery drain: only the run since unplugging counts", BatteryMath.drainPer10Min([at(14, 40, true), at(10, 60), at(0, 55)], now: now) == 5)
        check("battery drain: too little data or charging gives nil", BatteryMath.drainPer10Min([at(3, 60), at(0, 55)], now: now) == nil && BatteryMath.drainPer10Min([at(12, 50, true), at(0, 60, true)], now: now) == nil)
        check("battery health: Apple Silicon raw mAh, Intel mAh, percentage alone, capped at 100",
              BatteryMath.healthPercent(rawMax: 4_600, max: 100, design: 5_000) == 92 && BatteryMath.healthPercent(rawMax: nil, max: 4_000, design: 5_000) == 80
              && BatteryMath.healthPercent(rawMax: nil, max: 88, design: nil) == 88 && BatteryMath.healthPercent(rawMax: 5_200, max: 100, design: 5_000) == 100
              && BatteryMath.healthPercent(rawMax: nil, max: nil, design: nil) == nil)
        check("battery: time remaining as h:mm, nil while unknown", BatteryMath.remaining(12_000) == "3:20" && BatteryMath.remaining(-1) == nil && BatteryMath.remaining(59) == "0:00")
        let sp = BatteryHealth.parse(Data(#"{"SPPowerDataType":[{"sppower_battery_charge_info":{}},{"sppower_battery_health_info":{"sppower_battery_cycle_count":412,"sppower_battery_health_maximum_capacity":"87 %"}}]}"#.utf8))
        check("battery health: read from System Information as Settings shows it", sp?.percent == 87 && sp?.cycles == 412)
        check("battery health: a desktop report gives nil", BatteryHealth.parse(Data(#"{"SPPowerDataType":[{"sppower_ac_charger_information":{}}]}"#.utf8)) == nil)
        _ = BatteryHealth.registry(); _ = BatteryHealth.hasBattery()   // crash test only: real IOKit reads must not crash, with or without a battery
        var net: [NetSample] = []
        for i in 0..<400 { net = NetworkRate.appending(net, NetSample(t: now.addingTimeInterval(Double(i * 2)), down: Double(i), up: 0)) }
        check("network history: keeps the last 10 minutes", net.count == 301 && net.first?.down == 99, "\(net.count)")
        check("bluetooth island: AirPods symbol and battery line", BluetoothIslands.symbol(for: "Tom's AirPods Pro") == "airpodspro" && BluetoothIslands.symbol(for: "WH-1000XM5") == "headphones"
              && BluetoothIslands.battery(of: "AirPods Pro", in: ["AirPods Pro: L 85% · R 80%", "Magic Mouse: 42%"]) == "L 85% · R 80%" && BluetoothIslands.battery(of: "AirPods", in: ["AirPods Pro: L 1%"]) == nil)
    }
}
