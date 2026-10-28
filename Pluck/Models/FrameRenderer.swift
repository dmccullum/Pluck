import AppKit
import AVFoundation
import ImageIO

/// Decodes, composites and encodes frames off the main actor, for the player and for Shortcuts.
nonisolated enum FrameRenderer {
    /// The exact frame at `time`, with `zone` burned in, plus a small thumbnail of the result.
    /// Takes a URL rather than an asset because `AVAsset` can't be sent between actors.
    @concurrent
    static func frame(ofVideoAt url: URL, at time: CMTime, safeZone zone: SafeZone = .off) async throws -> (image: CGImage, thumbnail: CGImage) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let (decoded, _) = try await generator.image(at: time)
        let image = drawing(zone, onto: decoded)
        return (image, thumbnail(of: image))
    }

    @concurrent
    static func write(_ image: CGImage, format: CaptureFormat, quality: Double, to url: URL) async throws {
        let data = try encodedData(for: image, format: format, quality: quality)
        try data.write(to: url, options: .atomic)
    }

    /// Burns the safe zone guide into a captured frame, matching what's shown on screen.
    static func drawing(_ zone: SafeZone, onto image: CGImage) -> CGImage {
        guard zone != .off else { return image }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Core Graphics puts the origin bottom-left; the zone is defined top-left.
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)

        let safeArea = CGMutablePath()
        safeArea.addLines(between: zone.polygon.map { CGPoint(x: $0.x * width, y: $0.y * height) })
        safeArea.closeSubpath()

        let dimmed = CGMutablePath()
        dimmed.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        dimmed.addPath(safeArea)
        context.addPath(dimmed)
        context.setFillColor(CGColor(gray: 0, alpha: 0.42))
        context.fillPath(using: .evenOdd)

        // Scale the outline so it reads the same as on screen at any resolution.
        let lineWidth = max(1.5, width * 0.004)
        context.addPath(safeArea)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(lineWidth)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: [lineWidth * 4, lineWidth * 2.7])
        context.strokePath()

        return context.makeImage() ?? image
    }

    static func thumbnail(of image: CGImage, maxDimension: CGFloat = 480) -> CGImage {
        let scale = min(1, maxDimension / CGFloat(max(image.width, image.height)))
        let size = CGSize(width: max(1, CGFloat(image.width) * scale), height: max(1, CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
    }

    static func encodedData(for image: CGImage, format: CaptureFormat, quality: Double) throws -> Data {
        if format == .heic {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                format.contentType.identifier as CFString,
                1,
                nil
            ) else {
                throw FrameRendererError.couldNotEncode
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw FrameRendererError.couldNotEncode
            }
            return data as Data
        }

        guard let bitmapType = format.bitmapType else {
            throw FrameRendererError.couldNotEncode
        }
        let representation = NSBitmapImageRep(cgImage: image)
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if format == .jpeg {
            properties[.compressionFactor] = min(max(quality, 0.1), 1)
        }
        guard let data = representation.representation(using: bitmapType, properties: properties) else {
            throw FrameRendererError.couldNotEncode
        }
        return data
    }
}

/// Scrubber hover thumbnails. `AVAssetImageGenerator` can be used from any thread, so the
/// main-actor model can start decodes on it without giving up ownership.
nonisolated final class PreviewFrameGenerator: @unchecked Sendable {
    private let generator: AVAssetImageGenerator

    init(asset: AVAsset, tolerance: CMTime) {
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
    }

    /// Drops any decode still in flight; only the latest position matters.
    func image(at time: CMTime) async -> CGImage? {
        generator.cancelAllCGImageGeneration()
        return try? await generator.image(at: time).image
    }

    func cancel() {
        generator.cancelAllCGImageGeneration()
    }
}

nonisolated enum FrameRendererError: LocalizedError {
    case couldNotEncode

    var errorDescription: String? {
        "The image could not be encoded in the selected format."
    }
}

extension NSSavePanel {
    /// Shows the panel as a sheet on `window`, or app-modally when there's no window to attach to.
    func present(in window: NSWindow?) async -> URL? {
        guard let window else {
            return runModal() == .OK ? url : nil
        }
        let response = await beginSheetModal(for: window)
        return response == .OK ? url : nil
    }
}
