import AppKit
@preconcurrency import AVFoundation
import SwiftUI

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView(); v.wantsLayer = true
        let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspectFill
        l.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))   // mirrored, like a real mirror
        v.layer = l; return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

/// Local camera preview that drops below the notch. Nothing is recorded or stored.
@MainActor
final class CameraMirror {
    static let shared = CameraMirror()
    private var panel: NSPanel?
    private var session: AVCaptureSession?
    /// The permission prompt is up and has not answered yet.
    private var requesting = false

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen, !requesting else { return }
        requesting = true
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.requesting = false
                    guard ok else {
                        NotchModel.shared.show(Activity(symbol: "video.slash", title: L("Camera access denied"), subtitle: L("Allow it in System Settings"), tint: .orange)); return
                    }
                    self.present()
                }
            }
        }
    }

    private func present() {
        close()   // a session left from an earlier open must not keep running behind the new one
        guard let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam) else {
            NotchModel.shared.show(Activity(symbol: "video.slash", title: L("No camera found"), tint: .orange)); return
        }
        let s = AVCaptureSession(); s.sessionPreset = .medium
        if s.canAddInput(input) { s.addInput(input) }
        session = s
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }

        let size = NSSize(width: 260, height: 195)
        let p = NotchPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .mainMenu + 2
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: CameraPreview(session: s)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topTrailing) {
                Button { CameraMirror.shared.close() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)) }.accessibilityLabel("Close")
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).padding(8)
            })
        if let sc = NotchModel.shared.geometry.screen ?? NSScreen.main {
            p.setFrameOrigin(NSPoint(x: sc.frame.midX - size.width / 2, y: sc.frame.maxY - NotchModel.shared.geometry.height - size.height - 12))
        }
        p.orderFrontRegardless()
        panel = p
        NotchModel.shared.collapse()
    }

    func close() {
        let s = session; session = nil
        DispatchQueue.global(qos: .userInitiated).async { s?.stopRunning() }
        panel?.orderOut(nil); panel = nil
    }
}
