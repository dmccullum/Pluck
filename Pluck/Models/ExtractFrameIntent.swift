import AppIntents
import AVFoundation
import UniformTypeIdentifiers

/// Shortcuts action: the frame at a time in a video, as an image file.
struct ExtractFrameIntent: AppIntent {
    static let title: LocalizedStringResource = "Extract Frame from Video"
    static let description = IntentDescription("Returns the frame at a time in a video as a PNG, JPEG, HEIC, or TIFF image.")

    @Parameter(title: "Video", supportedContentTypes: [.movie, .audiovisualContent])
    var video: IntentFile

    @Parameter(title: "Seconds", default: 0, inclusiveRange: (0, 86_400))
    var seconds: Double

    @Parameter(title: "Format", default: .png)
    var format: CaptureFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Extract the frame at \(\.$seconds) seconds from \(\.$video) as \(\.$format)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (url, cleanUp) = try localFile(for: video)
        defer { cleanUp() }

        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractFrameError.noVideoTrack
        }
        let timeRange = try await track.load(.timeRange)
        let offset = min(max(0, seconds), max(0, timeRange.duration.seconds))
        let time = CMTime(seconds: timeRange.start.seconds + offset, preferredTimescale: 60_000)

        let (image, _) = try await FrameRenderer.frame(ofVideoAt: url, at: time)
        let data = try FrameRenderer.encodedData(for: image, format: format, quality: 0.9)
        let filename = CaptureFileName.make(
            videoURL: URL(fileURLWithPath: video.filename),
            seconds: offset,
            extension: format.fileExtension
        )
        return .result(value: IntentFile(data: data, filename: filename, type: format.contentType))
    }

    /// Reads the video in place when Shortcuts hands over a file URL; otherwise writes its
    /// data to a temporary file, since AVFoundation needs a URL.
    private func localFile(for file: IntentFile) throws -> (URL, () -> Void) {
        if let fileURL = file.fileURL {
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            return (fileURL, { if didAccess { fileURL.stopAccessingSecurityScopedResource() } })
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tempURL = folder.appendingPathComponent(file.filename.isEmpty ? "video.mov" : file.filename)
        try file.data.write(to: tempURL)
        return (tempURL, { try? FileManager.default.removeItem(at: folder) })
    }
}

extension CaptureFormat: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Image Format"
    static let caseDisplayRepresentations: [CaptureFormat: DisplayRepresentation] = [
        .png: "PNG",
        .jpeg: "JPEG",
        .heic: "HEIC",
        .tiff: "TIFF"
    ]
}

struct PluckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExtractFrameIntent(),
            phrases: ["Extract a frame with \(.applicationName)"],
            shortTitle: "Extract Frame",
            systemImageName: "photo"
        )
    }
}

private enum ExtractFrameError: LocalizedError {
    case noVideoTrack

    var errorDescription: String? {
        "The file has no video track."
    }
}
