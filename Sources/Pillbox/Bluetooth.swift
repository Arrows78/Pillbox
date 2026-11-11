import Foundation
@preconcurrency import IOBluetooth
import AppKit
import Charts
import IOKit
import IOKit.ps
import SwiftUI

/// Registering touches Bluetooth, which asks for permission: only runs once the user turns the island on.
@MainActor
final class BluetoothIslands: NSObject {
    static let shared = BluetoothIslands()
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]
    private var since = Date()

    func apply() { UserDefaults.standard.bool(forKey: "bluetoothIsland") ? start() : stop() }

    private func start() {
        guard connectNote == nil else { return }
        since = Date()   // devices already connected are reported right away: no island for them
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    private func stop() {
        connectNote?.unregister(); connectNote = nil
        disconnectNotes.values.forEach { $0.unregister() }; disconnectNotes = [:]
    }

    nonisolated static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// "L 85% · R 80% · Case 60%" for `name` out of BluetoothBattery's lines.
    nonisolated static func battery(of name: String, in lines: [String]) -> String? {
        lines.first { $0.hasPrefix(name + ": ") }.map { String($0.dropFirst(name.count + 2)) }
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        MainActor.assumeIsolated {
            guard device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio), let addr = device.addressString else { return }
            disconnectNotes[addr]?.unregister()
            disconnectNotes[addr] = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
            guard Date().timeIntervalSince(since) > 3 else { return }
            let name = device.name ?? localized("Bluetooth device")
            // AirPods publish their battery a moment after connecting.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                let pct = Self.battery(of: name, in: BluetoothBattery.read())
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        NotchModel.shared.show(Activity(symbol: Self.symbol(for: name), title: name, subtitle: pct ?? localized("Connected"), tint: .blue, duration: 4, kind: .bluetooth))
                    }
                }
            }
        }
    }

    @objc private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        MainActor.assumeIsolated {
            note.unregister()
            if let a = device.addressString { disconnectNotes[a] = nil }
            let name = device.name ?? localized("Bluetooth device")
            NotchModel.shared.show(Activity(symbol: Self.symbol(for: name), title: name, subtitle: localized("Disconnected"), tint: .white, duration: 3, kind: .bluetooth))
        }
    }
}

// MARK: Connect a paired Bluetooth device from the menu bar

enum BluetoothConnect {
    struct Device { let id: String; let name: String }

    /// Paired devices that are not connected right now, by address.
    @MainActor static func pairedOffline() -> [Device] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { !$0.isConnected() }
            .compactMap { d in d.addressString.map { Device(id: $0, name: d.name ?? "Bluetooth") } }
    }

    @MainActor static func name(of id: String) -> String? {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first { $0.addressString == id }?.name
    }

    /// Opens the connection on a background queue: a device that does not answer can take a few seconds.
    @MainActor static func connect(_ id: String, done: @escaping @MainActor (Bool) -> Void) {
        guard let device = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first(where: { $0.addressString == id }) else { done(false); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = device.openConnection() == kIOReturnSuccess
            DispatchQueue.main.async { MainActor.assumeIsolated { done(ok) } }
        }
    }
}
