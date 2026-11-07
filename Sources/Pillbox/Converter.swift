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
        switch self { case .unsupported: "Unsupported conversion"; case .failed(let m): m }
    }
}

/// Offline conversions with the system frameworks: images (ImageIO, PDFKit, Vision), audio and video (AVFoundation).
enum Converter {
    static func convert(_ src: URL, to target: ConvertTarget) async throws -> URL {
        let out = ShelfService.uniqueURL(src.deletingPathExtension().appendingPathExtension(target.ext))
        switch target {
        case .png, .jpeg, .heic, .tiff: try image(src, to: out, type: target.imageType!)
        case .pdf: try pdf(src, to: out)
        case .cutout: try cutout(src, to: out)
        case .mp4: try await export(src, to: out, preset: AVAssetExportPresetHighestQuality, type: .mp4)
        case .hevc: try await export(src, to: out, preset: AVAssetExportPresetHEVCHighestQuality, type: .mp4)
        case .m4a: try await export(src, to: out, preset: AVAssetExportPresetAppleM4A, type: .m4a)
        case .aac: try await export(src, to: out, preset: AVAssetExportPresetAppleM4A, type: .m4a)
        case .wav, .aiff: try pcm(src, to: out, wav: target == .wav)
        }
        return out
    }

    private static func cgImage(_ url: URL) throws -> CGImage {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { throw ConvertError.failed("Cannot read the image") }
        return i
    }

    static func image(_ src: URL, to out: URL, type: UTType) throws {
        let img = try cgImage(src)
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { throw ConvertError.failed("Cannot write \(type.preferredFilenameExtension ?? "")") }
        CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw ConvertError.failed("Encoding failed") }
    }

    static func pdf(_ src: URL, to out: URL) throws {
        guard let nsimg = NSImage(contentsOf: src), let page = PDFPage(image: nsimg) else { throw ConvertError.failed("Cannot read the image") }
        let doc = PDFDocument(); doc.insert(page, at: 0)
        guard doc.write(to: out) else { throw ConvertError.failed("Cannot write the PDF") }
    }

    /// Foreground cut-out with Vision (no network); keeps the original size, transparent background.
    static func cutout(_ src: URL, to out: URL) throws {
        let handler = VNImageRequestHandler(url: src)
        let req = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([req])
        guard let obs = req.results?.first else { throw ConvertError.failed("No subject found") }
        let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent), let d = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ConvertError.failed("Cannot write the image") }
        CGImageDestinationAddImage(d, cg, nil)
        guard CGImageDestinationFinalize(d) else { throw ConvertError.failed("Encoding failed") }
    }

    static func export(_ src: URL, to out: URL, preset: String, type: AVFileType) async throws {
        let asset = AVURLAsset(url: src)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ConvertError.unsupported }
        try await session.export(to: out, as: type)
    }

    static func pcm(_ src: URL, to out: URL, wav: Bool) throws {
        let input = try AVAudioFile(forReading: src)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: input.processingFormat.sampleRate,
                                       AVNumberOfChannelsKey: input.processingFormat.channelCount, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: !wav]
        let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: input.processingFormat.commonFormat, interleaved: input.processingFormat.isInterleaved)
        guard let buf = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192) else { throw ConvertError.failed("Buffer") }
        while input.framePosition < input.length { try input.read(into: buf); try output.write(from: buf) }
    }
}

extension ShelfService {
    func convert(_ list: [ShelfItem], to target: ConvertTarget) {
        for item in list {
            Task { @MainActor in
                do {
                    let out = try await Converter.convert(item.url, to: target)
                    add([out])
                    NotchModel.shared.show(Activity(symbol: "arrow.triangle.2.circlepath", title: "Converted", subtitle: out.lastPathComponent, tint: .green))
                } catch {
                    NotchModel.shared.show(Activity(symbol: "xmark.octagon", title: "Conversion failed", subtitle: error.localizedDescription, tint: .red))
                }
            }
        }
    }
}
