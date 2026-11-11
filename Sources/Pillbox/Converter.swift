import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum ConvertTarget: String, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPEG", heic = "HEIC", tiff = "TIFF", pdf = "PDF"
    case cutout = "Remove background"
    case mp4 = "MP4", hevc = "HEVC", m4a = "Audio only (M4A)", aac = "AAC", wav = "WAV", aiff = "AIFF"
    var id: String { rawValue }

    var ext: String {
        switch self {
        case .png, .cutout: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .tiff: "tiff"
        case .pdf: "pdf"
        case .mp4, .hevc: "mp4"
        case .m4a, .aac: "m4a"
        case .wav: "wav"
        case .aiff: "aiff"
        }
    }

    var imageType: UTType? {
        switch self {
        case .png, .cutout: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        default: nil
        }
    }

    static func targets(for url: URL) -> [ConvertTarget] {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return [] }
        if t.conforms(to: .image) { return [.png, .jpeg, .heic, .tiff, .pdf, .cutout] }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return [.mp4, .hevc, .m4a] }
        if t.conforms(to: .audio) { return [.aac, .wav, .aiff] }
        return []
    }
}

enum ConvertError: Error, LocalizedError {
    case unsupported, failed(String)
    var errorDescription: String? {
        switch self { case .unsupported: localized("Unsupported conversion"); case .failed(let m): m }
    }
}

/// Offline conversions with the system frameworks: images (ImageIO, PDFKit, Vision), audio and video (AVFoundation).
/// Every conversion runs off the main actor: the work is slow on long files.
enum Converter {
    nonisolated static func convert(_ src: URL, to target: ConvertTarget) async throws -> URL {
        let out = ShelfService.uniqueURL(src.deletingPathExtension().appendingPathExtension(target.ext))
        switch target {
        case .png, .jpeg, .heic, .tiff: try image(src, to: out, type: target.imageType!)
        case .pdf: try pdf(src, to: out)
        case .cutout: try cutout(src, to: out)
        case .mp4: try await export(src, to: out, preset: AVAssetExportPresetHighestQuality, type: .mp4)
        case .hevc: try await export(src, to: out, preset: AVAssetExportPresetHEVCHighestQuality, type: .mp4)
        case .m4a, .aac: try await export(src, to: out, preset: AVAssetExportPresetAppleM4A, type: .m4a)
        case .wav, .aiff: try pcm(src, to: out, wav: target == .wav)
        }
        return out
    }

    /// The picture with its EXIF orientation applied (phone photos are stored sideways), as Annotator opens them.
    private nonisolated static func cgImage(_ url: URL) throws -> CGImage {
        guard let i = Annotator.load(url) else { throw ConvertError.failed(localized("Cannot read the image")) }
        return i
    }

    nonisolated static func image(_ src: URL, to out: URL, type: UTType) throws {
        let img = try cgImage(src)
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { throw ConvertError.failed(localized("Cannot write %@", type.preferredFilenameExtension ?? "")) }
        CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw ConvertError.failed(localized("Encoding failed")) }
    }

    nonisolated static func pdf(_ src: URL, to out: URL) throws {
        guard let nsimg = NSImage(contentsOf: src), let page = PDFPage(image: nsimg) else { throw ConvertError.failed(localized("Cannot read the image")) }
        let doc = PDFDocument(); doc.insert(page, at: 0)
        guard doc.write(to: out) else { throw ConvertError.failed(localized("Cannot write the PDF")) }
    }

    /// Foreground cut-out with Vision (no network); keeps the original size, transparent background.
    nonisolated static func cutout(_ src: URL, to out: URL) throws {
        let handler = VNImageRequestHandler(url: src)
        let req = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([req])
        guard let obs = req.results?.first else { throw ConvertError.failed(localized("No subject found")) }
        let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent), let d = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ConvertError.failed(localized("Cannot write the image")) }
        CGImageDestinationAddImage(d, cg, nil)
        guard CGImageDestinationFinalize(d) else { throw ConvertError.failed(localized("Encoding failed")) }
    }

    nonisolated static func export(_ src: URL, to out: URL, preset: String, type: AVFileType) async throws {
        let asset = AVURLAsset(url: src)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ConvertError.unsupported }
        try await session.export(to: out, as: type)
    }

    nonisolated static func pcm(_ src: URL, to out: URL, wav: Bool) throws {
        let input = try AVAudioFile(forReading: src)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: input.processingFormat.sampleRate,
                                       AVNumberOfChannelsKey: input.processingFormat.channelCount, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: !wav]
        let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: input.processingFormat.commonFormat, interleaved: input.processingFormat.isInterleaved)
        guard let buf = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192) else { throw ConvertError.failed(localized("Buffer")) }
        while input.framePosition < input.length { try input.read(into: buf); try output.write(from: buf) }
    }
}

/// Unit conversions for the command palette: "10 km in mi", "100 C to F". Offline and fixed: length, mass, volume,
/// speed and temperature. Currencies are left out on purpose: their rates change daily and the Mac has none offline.
enum UnitConverter {
    enum Kind { case length, mass, volume, speed, temperature }

    /// A unit and its size in the base unit of its kind (metres, grams, millilitres, metres per second). Temperatures
    /// have no factor: they convert through kelvin.
    struct Unit: Equatable {
        /// The symbol shown ("°F", "fl oz").
        let name: String, kind: Kind, factor: Double
        /// What a typed name is compared with: lowercase, without the degree sign.
        var key: String { name.lowercased().replacingOccurrences(of: "°", with: "") }
        static let all: [Unit] = [
            Unit(name: "mm", kind: .length, factor: 0.001), Unit(name: "cm", kind: .length, factor: 0.01),
            Unit(name: "m", kind: .length, factor: 1), Unit(name: "km", kind: .length, factor: 1000),
            Unit(name: "in", kind: .length, factor: 0.0254), Unit(name: "ft", kind: .length, factor: 0.3048),
            Unit(name: "yd", kind: .length, factor: 0.9144), Unit(name: "mi", kind: .length, factor: 1609.344),
            Unit(name: "mg", kind: .mass, factor: 0.001), Unit(name: "g", kind: .mass, factor: 1),
            Unit(name: "kg", kind: .mass, factor: 1000), Unit(name: "oz", kind: .mass, factor: 28.349523125),
            Unit(name: "lb", kind: .mass, factor: 453.59237), Unit(name: "t", kind: .mass, factor: 1_000_000),
            Unit(name: "ml", kind: .volume, factor: 1), Unit(name: "cl", kind: .volume, factor: 10),
            Unit(name: "l", kind: .volume, factor: 1000), Unit(name: "fl oz", kind: .volume, factor: 29.5735295625),
            Unit(name: "cup", kind: .volume, factor: 236.5882365), Unit(name: "pt", kind: .volume, factor: 473.176473),
            Unit(name: "qt", kind: .volume, factor: 946.352946), Unit(name: "gal", kind: .volume, factor: 3785.411784),
            Unit(name: "m/s", kind: .speed, factor: 1), Unit(name: "km/h", kind: .speed, factor: 1 / 3.6),
            Unit(name: "mph", kind: .speed, factor: 0.44704), Unit(name: "kn", kind: .speed, factor: 0.514444),
            Unit(name: "°C", kind: .temperature, factor: 0), Unit(name: "°F", kind: .temperature, factor: 0),
            Unit(name: "K", kind: .temperature, factor: 0),
        ]
        /// The unit for a typed name ("km", "°C", "fl oz"), case-insensitive. Nil when it is not a known unit.
        static func named(_ s: String) -> Unit? {
            let typed = s.lowercased().replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
            return all.first { $0.key == typed }
        }
    }

    struct Request: Equatable { let value: Double, from: Unit, to: Unit }

    /// The request in "<number> <unit> in|to <unit>", or nil when it is not one or the units do not measure the same thing.
    static func parse(_ query: String) -> Request? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let m = q.firstMatch(of: #/^([0-9]+(?:[.,][0-9]+)?)\s*([°a-zA-Z/ ]+?)\s+(?:in|to)\s+([°a-zA-Z/ ]+)$/#) else { return nil }
        let number = String(m.1).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number), let from = Unit.named(String(m.2)), let to = Unit.named(String(m.3)), from.kind == to.kind else { return nil }
        return Request(value: value, from: from, to: to)
    }

    /// The converted number.
    static func convert(_ r: Request) -> Double {
        if r.from.kind == .temperature {
            let kelvin: Double
            switch r.from.key {
            case "c": kelvin = r.value + 273.15
            case "f": kelvin = (r.value - 32) * 5 / 9 + 273.15
            default: kelvin = r.value
            }
            switch r.to.key {
            case "c": return kelvin - 273.15
            case "f": return (kelvin - 273.15) * 9 / 5 + 32
            default: return kelvin
            }
        }
        return r.value * r.from.factor / r.to.factor
    }

    /// The text the palette shows and copies, with the same number formatting as palette maths: "6.21371 mi".
    /// Nil when the query is not a conversion.
    static func answer(_ query: String) -> String? {
        guard let r = parse(query) else { return nil }
        let v = convert(r)
        guard v.isFinite else { return nil }
        let number = v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(format: "%.6g", v)
        return "\(number) \(r.to.name)"
    }
}
