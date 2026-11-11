import AppKit
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// One annotation, in image pixels with a top-left origin.
struct Mark {
    enum Kind: String, CaseIterable, Identifiable {
        case arrow, rect, pen, text, pixelate, step, loupe
        var id: String { rawValue }
        var symbol: String {
            switch self { case .arrow: "arrow.up.right"; case .rect: "rectangle"; case .pen: "scribble"; case .text: "textformat"; case .pixelate: "checkerboard.rectangle"; case .step: "1.circle"; case .loupe: "magnifyingglass.circle" }
        }
        var title: String {
            switch self { case .arrow: "Arrow"; case .rect: "Rectangle"; case .pen: "Pen"; case .text: "Text"; case .pixelate: "Pixelate"; case .step: "Step"; case .loupe: "Loupe" }
        }
    }
    var kind: Kind
    var color: CGColor
    var points: [CGPoint]
    var text = ""

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

enum Annotator {
    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black]

    nonisolated static func canAnnotate(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp", "webp"].contains(url.pathExtension.lowercased())
    }

    /// "Shot.jpg" → "Shot annotated.png", next to the original (the original is never touched).
    nonisolated static func outputURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + " annotated.png")
    }

    nonisolated static func lineWidth(for size: CGSize) -> CGFloat { max(3, min(size.width, size.height) / 220) }

    /// Shapes to stroke and to fill for a mark (arrows have a filled head), in image coordinates.
    nonisolated static func paths(_ m: Mark, lineWidth lw: CGFloat) -> (stroke: CGPath?, fill: CGPath?) {
        switch m.kind {
        case .rect: return (CGPath(rect: m.rect, transform: nil), nil)
        case .pen:
            guard let first = m.points.first else { return (nil, nil) }
            let p = CGMutablePath(); p.move(to: first); m.points.dropFirst().forEach { p.addLine(to: $0) }
            return (p, nil)
        case .arrow:
            guard let a = m.points.first, let b = m.points.last, a != b else { return (nil, nil) }
            let angle = atan2(b.y - a.y, b.x - a.x), head = min(lw * 5, hypot(b.x - a.x, b.y - a.y))
            func pt(_ d: CGFloat, _ off: CGFloat) -> CGPoint { CGPoint(x: b.x - d * cos(angle + off), y: b.y - d * sin(angle + off)) }
            let line = CGMutablePath(); line.move(to: a); line.addLine(to: pt(head * 0.8, 0))
            let tip = CGMutablePath(); tip.move(to: b); tip.addLine(to: pt(head, 0.45)); tip.addLine(to: pt(head, -0.45)); tip.closeSubpath()
            return (line, tip)
        case .text, .pixelate, .step, .loupe: return (nil, nil)
        }
    }

    nonisolated static func font(for size: CGSize) -> NSFont { .boldSystemFont(ofSize: lineWidth(for: size) * 6) }

    /// Opens an image the right way up (EXIF orientation applied).
    nonisolated static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: max(w, h)]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Big square blocks, so the hidden text cannot be read back.
    nonisolated static func pixelated(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let scale = max(10, Double(min(image.width, image.height)) / 45)
        let out = ci.clampedToExtent().applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: scale, kCIInputCenterKey: CIVector(x: 0, y: 0)]).cropped(to: ci.extent)
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(out, from: ci.extent)
    }

    /// The picture with every mark drawn on it, at full resolution.
    nonisolated static func render(_ image: CGImage, marks: [Mark], pixelated: CGImage?) -> CGImage? {
        let w = image.width, h = image.height, size = CGSize(width: w, height: h)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(origin: .zero, size: size)
        ctx.draw(image, in: full)
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)   // top-left origin, like the marks
        let lw = lineWidth(for: size)
        ctx.setLineWidth(lw); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        var stepNumber = 0
        for m in marks {
            switch m.kind {
            case .step:
                guard let c = m.points.first else { continue }
                stepNumber += 1
                let d = lw * 12
                ctx.setFillColor(m.color)
                ctx.fillEllipse(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
                // Dark figures on a light disc, light ones on a dark disc.
                let light = (NSColor(cgColor: m.color)?.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) > 0.7
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: d * 0.55), .foregroundColor: light ? NSColor.black : NSColor.white]
                let label = "\(stepNumber)" as NSString, s = label.size(withAttributes: attrs)
                let g = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
                label.draw(at: CGPoint(x: c.x - s.width / 2, y: c.y - s.height / 2), withAttributes: attrs)
                NSGraphicsContext.restoreGraphicsState()
            case .loupe:
                // The picture magnified twice inside the circle, with a ring around it.
                let r = m.rect
                guard r.width > 4, r.height > 4 else { continue }
                ctx.saveGState()
                ctx.addEllipse(in: r); ctx.clip()
                ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
                let c = CGPoint(x: r.midX, y: CGFloat(h) - r.midY)
                ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: 2, y: 2); ctx.translateBy(x: -c.x, y: -c.y)
                ctx.draw(image, in: full)
                ctx.restoreGState()
                ctx.setStrokeColor(m.color); ctx.strokeEllipse(in: r)
            case .pixelate:
                guard let pixelated else { continue }
                let r = m.rect
                ctx.saveGState()
                ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
                ctx.clip(to: CGRect(x: r.minX, y: CGFloat(h) - r.maxY, width: r.width, height: r.height))
                ctx.draw(pixelated, in: full)
                ctx.restoreGState()
            case .text:
                guard let p = m.points.first, !m.text.isEmpty else { continue }
                let g = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
                let shadow = NSShadow(); shadow.shadowBlurRadius = lw; shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
                (m.text as NSString).draw(at: p, withAttributes: [.font: font(for: size), .foregroundColor: NSColor(cgColor: m.color) ?? .red, .shadow: shadow])
                NSGraphicsContext.restoreGraphicsState()
            default:
                let (stroke, fill) = paths(m, lineWidth: lw)
                ctx.setStrokeColor(m.color); ctx.setFillColor(m.color)
                if let stroke { ctx.addPath(stroke); ctx.strokePath() }
                if let fill { ctx.addPath(fill); ctx.fillPath() }
            }
        }
        return ctx.makeImage()
    }

    nonisolated static func pngData(_ image: CGImage) -> Data? {
        let d = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(d, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? d as Data : nil
    }

    // MARK: Window

    @MainActor private static var windows: [NSWindow] = []

    @MainActor static func open(_ url: URL) {
        guard let img = load(url) else { NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: "Could not open the image", tint: .orange)); return }
        NotchModel.shared.collapse()
        let model = AnnotatorModel(source: url, image: img)
        let vis = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let k = min(1, (vis.width * 0.8) / CGFloat(img.width), (vis.height * 0.8 - 50) / CGFloat(img.height))
        let size = NSSize(width: max(560, CGFloat(img.width) * k), height: max(320, CGFloat(img.height) * k + 50))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = L("Annotate %@", url.lastPathComponent); w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: AnnotatorView(m: model))
        w.center(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        windows.append(w)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { windows.removeAll { $0 === w } }
        }
    }
}

@MainActor
final class AnnotatorModel: ObservableObject {
    let source: URL
    let image: CGImage
    private let pixelated: CGImage?
    @Published var marks: [Mark] = [] { didSet { rendered = Annotator.render(image, marks: marks, pixelated: pixelated) ?? image } }
    @Published var draft: Mark?
    @Published var tool: Mark.Kind = .arrow
    @Published var color = 0
    @Published var text = ""
    @Published private(set) var rendered: CGImage

    init(source: URL, image: CGImage) {
        self.source = source; self.image = image; rendered = image
        pixelated = Annotator.pixelated(image)
    }

    var size: CGSize { CGSize(width: image.width, height: image.height) }
    var cgColor: CGColor { Annotator.colors[color].cgColor }

    func drag(from a: CGPoint, to b: CGPoint) {
        guard tool != .text else { return }
        if draft == nil { draft = Mark(kind: tool, color: cgColor, points: [a]) }
        if tool == .pen { draft?.points.append(b) } else { draft?.points = [a, b] }
    }

    func end(at p: CGPoint) {
        defer { draft = nil }
        if tool == .text {
            let t = text.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { marks.append(Mark(kind: .text, color: cgColor, points: [p], text: t)) }
            return
        }
        guard let d = draft else { return }
        if d.kind == .step { marks.append(d); return }   // a step is placed with one click
        let r = d.rect
        if d.kind == .pen ? d.points.count > 2 : max(r.width, r.height) > 4 { marks.append(d) }
    }

    func undo() { if !marks.isEmpty { marks.removeLast() } }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: rendered, size: size)])
        NotchModel.shared.show(Activity(symbol: "doc.on.clipboard", title: "Image copied", tint: .green))
    }

    func save() {
        let url = ShelfService.uniqueURL(Annotator.outputURL(for: source))
        guard let d = Annotator.pngData(rendered), (try? d.write(to: url)) != nil else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: "Could not save the image", tint: .orange)); return
        }
        ShelfService.shared.add([url])
        NotchModel.shared.show(Activity(symbol: "pencil.tip.crop.circle", title: "Annotated image saved", subtitle: url.lastPathComponent, tint: .green))
    }
}

struct AnnotatorView: View {
    @ObservedObject var m: AnnotatorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Tool", selection: $m.tool) {
                    ForEach(Mark.Kind.allCases) { k in Image(systemName: k.symbol).help(LocalizedStringKey(k.title)).accessibilityLabel(LocalizedStringKey(k.title)).tag(k) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                HStack(spacing: 4) {
                    ForEach(Annotator.colors.indices, id: \.self) { i in
                        Circle().fill(Color(nsColor: Annotator.colors[i])).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: m.color == i ? 2 : 0.5))
                            .onTapGesture { m.color = i }
                    }
                }
                if m.tool == .text {
                    TextField("Text, then click the image", text: $m.text).textFieldStyle(.roundedBorder).frame(minWidth: 120, maxWidth: 220)
                }
                Spacer(minLength: 0)
                Button { m.undo() } label: { Image(systemName: "arrow.uturn.backward") }.keyboardShortcut("z").disabled(m.marks.isEmpty).hoverTip(L("Undo")).accessibilityLabel("Undo")
                Button("Copy") { m.copy() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Save") { m.save() }.keyboardShortcut("s").buttonStyle(.borderedProminent)
            }
            .controlSize(.small).padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            GeometryReader { geo in
                let k = min(geo.size.width / m.size.width, geo.size.height / m.size.height)
                let fit = CGSize(width: m.size.width * k, height: m.size.height * k)
                ZStack {
                    Image(decorative: m.rendered, scale: 1).resizable().interpolation(.high)
                    if let d = m.draft { DraftShape(mark: d, scale: k, lineWidth: Annotator.lineWidth(for: m.size)) }
                }
                .frame(width: fit.width, height: fit.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    m.drag(from: clamp(v.startLocation, k), to: clamp(v.location, k))
                }.onEnded { v in m.end(at: clamp(v.startLocation, k)) })
                .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 560, minHeight: 320)
    }

    private func clamp(_ p: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x / k, 0), m.size.width), y: min(max(p.y / k, 0), m.size.height))
    }
}

/// The shape being drawn, before the mouse is released.
private struct DraftShape: View {
    let mark: Mark
    let scale: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let t = CGAffineTransform(scaleX: scale, y: scale)
        let color = Color(cgColor: mark.color)
        if mark.kind == .pixelate || mark.kind == .loupe {
            Path(ellipseIn: mark.rect.applying(t)).stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
        } else if mark.kind == .step, let c = mark.points.first {
            let d = lineWidth * 12 * scale
            Path(ellipseIn: CGRect(x: c.x * scale - d / 2, y: c.y * scale - d / 2, width: d, height: d)).stroke(color, lineWidth: 1.5)
        } else {
            let (stroke, fill) = Annotator.paths(mark, lineWidth: lineWidth)
            ZStack {
                if let stroke { Path(stroke).applying(t).stroke(color, style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round)) }
                if let fill { Path(fill).applying(t).fill(color) }
            }
        }
    }
}
