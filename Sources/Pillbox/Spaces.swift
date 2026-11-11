import Foundation
import AppKit
import SwiftUI

/// The current desktop through the private CGS API, looked up with dlsym: when a symbol is missing the island just never shows.
enum SpaceInfo {
    enum Kind: Equatable { case desktop(Int), fullScreen(String?) }

    private typealias ConnFn = @convention(c) () -> Int32
    private typealias CopyFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias ActiveFn = @convention(c) (Int32) -> UInt64
    /// CoreGraphics first, then SkyLight: newer macOS releases moved these symbols there.
    private static let handles: [UnsafeMutableRawPointer] = {
        let paths: [String] = ["/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                               "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"]
        return paths.compactMap { dlopen($0, RTLD_LAZY) }
    }()
    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? { handles.lazy.compactMap { dlsym($0, name) }.first }

    /// Spaces of each display and the active space id, or nil when the API is unavailable.
    static func read() -> (displays: [[String: Any]], active: UInt64)? {
        guard let c = symbol("CGSMainConnectionID"), let s = symbol("CGSCopyManagedDisplaySpaces"), let a = symbol("CGSGetActiveSpace") else { return nil }
        let cid = unsafeBitCast(c, to: ConnFn.self)()
        guard let arr = unsafeBitCast(s, to: CopyFn.self)(cid)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return (arr, unsafeBitCast(a, to: ActiveFn.self)(cid))
    }

    private static func id(_ d: [String: Any]) -> UInt64? { (d["ManagedSpaceID"] as? NSNumber ?? d["id64"] as? NSNumber)?.uint64Value }

    /// Desktops are numbered per display, like Mission Control; full-screen spaces (type 4) are named after their app.
    static func kind(displays: [[String: Any]], active: UInt64) -> Kind? {
        for d in displays {
            guard let spaces = d["Spaces"] as? [[String: Any]], let space = spaces.first(where: { id($0) == active }) else { continue }
            if (space["type"] as? NSNumber)?.intValue == 4 {
                let tiles = (space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]]
                return .fullScreen(tiles?.compactMap { $0["appName"] as? String }.first)
            }
            let desktops = spaces.filter { ($0["type"] as? NSNumber)?.intValue != 4 }
            return desktops.firstIndex(where: { id($0) == active }).map { .desktop($0 + 1) }
        }
        return nil
    }

    static func label(_ k: Kind, frontApp: String?) -> String {
        switch k {
        case .desktop(let n): localized("Desktop %d", n)
        case .fullScreen(let app): app ?? frontApp ?? localized("Full screen")
        }
    }
}

@MainActor
final class SpaceWatcher {
    static let shared = SpaceWatcher()
    static let symbol = "rectangle.on.rectangle"
    private var last: UInt64?
    private var observer: NSObjectProtocol?

    func start() {
        last = SpaceInfo.read()?.active
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            // The front app of a full-screen space settles a moment after the switch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { SpaceWatcher.shared.changed() } }
        }
    }

    private func changed() {
        guard let info = SpaceInfo.read() else { return }
        defer { last = info.active }
        guard UserDefaults.standard.bool(forKey: "spaceIsland"), info.active != last, let k = SpaceInfo.kind(displays: info.displays, active: info.active) else { return }
        let m = NotchModel.shared
        if m.activity?.symbol == Self.symbol { m.dismissActivity() }   // quick switches replace the label instead of queueing
        m.show(Activity(symbol: Self.symbol, title: SpaceInfo.label(k, frontApp: NSWorkspace.shared.frontmostApplication?.localizedName), tint: .cyan, duration: 1.3))
    }
}

// MARK: Camera guard
