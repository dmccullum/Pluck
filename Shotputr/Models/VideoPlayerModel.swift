import AppKit
import AVFoundation
import Combine
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class VideoPlayerModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var videoURL: URL?
    @Published private(set) var duration: Double = 0
    @Published private(set) var videoAspectRatio: Double = 16.0 / 9.0
    @Published var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPresentationReady = false
    @Published private(set) var presentationID = UUID()
    @Published private(set) var isCapturing = false
    @Published var alertMessage: String?
    @Published private(set) var toastMessage: String?
    @Published private(set) var overlayImage: NSImage?
    @Published private(set) var overlayURL: URL?
    @Published private(set) var isOverlayEnabled: Bool
    @Published private(set) var overlaySizing: OverlaySizing

    private var asset: AVAsset?
    private var frameDuration = 1.0 / 30.0
    private var mediaStartTime = CMTime.zero
    private var timeObserver: Any?
    private var timeControlCancellable: AnyCancellable?
    private var presentationSizeCancellable: AnyCancellable?
    private var securityScopedURL: URL?
    private var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    private var loadTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var overlaySecurityScopedURL: URL?
    private let overlayContext = CIContext(options: [.cacheIntermediates: false])

    var documentOpener: ((URL) -> Void)?

    var hasVideo: Bool { player != nil && videoURL != nil }
    var hasOverlay: Bool { overlayImage != nil && overlayURL != nil }
    var overlayName: String? { overlayURL?.lastPathComponent }

    init() {
        let defaults = UserDefaults.standard
        isOverlayEnabled = defaults.object(forKey: PreferenceKey.overlayEnabled) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.overlayEnabled)
        overlaySizing = OverlaySizing(
            rawValue: defaults.string(forKey: PreferenceKey.overlaySizing) ?? ""
        ) ?? .fit
        restoreOverlay()
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open a Video"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.movie, .audiovisualContent]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            requestOpen(url: url)
        }
    }

    func requestOpen(url: URL) {
        if let documentOpener {
            documentOpener(url)
        } else {
            open(url: url)
        }
    }

    @discardableResult
    func handleDrop(url: URL) -> Bool {
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if hasVideo, contentType?.conforms(to: .png) == true {
            installOverlay(from: url)
            return true
        }
        guard contentType?.conforms(to: .movie) == true
                || contentType?.conforms(to: .audiovisualContent) == true else {
            return false
        }
        open(url: url)
        return true
    }

    func presentOverlayPanel() {
        let panel = NSOpenPanel()
        panel.title = hasOverlay ? "Replace PNG Overlay" : "Choose a PNG Overlay"
        panel.prompt = hasOverlay ? "Replace" : "Choose"
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            installOverlay(from: url)
        }
    }

    func setOverlayEnabled(_ enabled: Bool) {
        guard hasOverlay, enabled != isOverlayEnabled else { return }
        isOverlayEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: PreferenceKey.overlayEnabled)
        showToast(enabled ? "Overlay on" : "Overlay off")
    }

    func setOverlaySizing(_ sizing: OverlaySizing) {
        guard sizing != overlaySizing else { return }
        overlaySizing = sizing
        UserDefaults.standard.set(sizing.rawValue, forKey: PreferenceKey.overlaySizing)
    }

    func removeOverlay() {
        overlaySecurityScopedURL?.stopAccessingSecurityScopedResource()
        overlaySecurityScopedURL = nil
        overlayImage = nil
        overlayURL = nil
        OverlayBookmarkStore.clear()
        showToast("Overlay removed")
    }

    func open(url: URL) {
        guard url.isFileURL else {
            alertMessage = "Shotgrabber can only open local video files."
            return
        }

        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        guard type?.conforms(to: .movie) == true || type?.conforms(to: .audiovisualContent) == true else {
            alertMessage = "That file doesn’t appear to be a video."
            return
        }

        loadTask?.cancel()
        player?.pause()
        isLoading = true
        isPresentationReady = false
        alertMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            let newAsset = AVURLAsset(url: url)

            do {
                let isPlayable = try await newAsset.load(.isPlayable)
                guard isPlayable else {
                    throw PlayerError.notPlayable
                }

                let assetDuration = try await newAsset.load(.duration)
                let videoTracks = try await newAsset.loadTracks(withMediaType: .video)
                guard let track = videoTracks.first else {
                    throw PlayerError.noVideoTrack
                }

                let nominalFrameRate = try await track.load(.nominalFrameRate)
                let minimumFrameDuration = try await track.load(.minFrameDuration)
                let naturalSize = try await track.load(.naturalSize)
                let preferredTransform = try await track.load(.preferredTransform)
                let trackTimeRange = try await track.load(.timeRange)
                guard !Task.isCancelled else { return }

                let transformedBounds = CGRect(origin: .zero, size: naturalSize)
                    .applying(preferredTransform)
                let presentationSize = CGSize(
                    width: abs(transformedBounds.width),
                    height: abs(transformedBounds.height)
                )

                self.install(
                    asset: newAsset,
                    url: url,
                    duration: trackTimeRange.duration.seconds.isFinite ? trackTimeRange.duration.seconds : assetDuration.seconds,
                    startTime: trackTimeRange.start,
                    nominalFrameRate: Double(nominalFrameRate),
                    minimumFrameDuration: minimumFrameDuration,
                    presentationSize: presentationSize
                )
            } catch is CancellationError {
                return
            } catch {
                self.isLoading = false
                self.isPresentationReady = self.hasVideo
                self.alertMessage = "This video couldn’t be opened. \(error.localizedDescription)"
            }
        }
    }

    private func install(
        asset: AVAsset,
        url: URL,
        duration: Double,
        startTime: CMTime,
        nominalFrameRate: Double,
        minimumFrameDuration: CMTime,
        presentationSize: CGSize
    ) {
        tearDownPlayer()

        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }

        self.asset = asset
        self.videoURL = url
        self.duration = duration.isFinite ? max(0, duration) : 0
        mediaStartTime = startTime.isValid ? startTime : .zero
        if presentationSize.width > 0, presentationSize.height > 0 {
            videoAspectRatio = presentationSize.width / presentationSize.height
        } else {
            videoAspectRatio = 16.0 / 9.0
        }
        currentTime = 0

        if minimumFrameDuration.isValid, minimumFrameDuration.seconds > 0 {
            frameDuration = minimumFrameDuration.seconds
        } else if nominalFrameRate > 0 {
            frameDuration = 1.0 / nominalFrameRate
        } else {
            frameDuration = 1.0 / 30.0
        }

        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer
        presentationID = UUID()
        observe(newPlayer, item: playerItem)
    }

    func finishPresentation(id: UUID) {
        guard id == presentationID, hasVideo else { return }
        isPresentationReady = true
        isLoading = false
    }

    private func observe(_ player: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.isScrubbing else { return }
                let seconds = time.seconds - self.mediaStartTime.seconds
                if seconds.isFinite {
                    self.currentTime = min(max(0, seconds), self.duration)
                }
            }
        }

        timeControlCancellable = player.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .map { $0 > 0 }
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                self?.isPlaying = isPlaying
            }

        presentationSizeCancellable = item.publisher(for: \.presentationSize)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                guard size.width > 0, size.height > 0 else { return }
                guard let self, !self.isPresentationReady else { return }
                self.videoAspectRatio = size.width / size.height
            }
    }

    private func tearDownPlayer() {
        player?.pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeControlCancellable = nil
        presentationSizeCancellable = nil
        player = nil
        asset = nil
        videoURL = nil
        isPresentationReady = false
        videoAspectRatio = 16.0 / 9.0
        mediaStartTime = .zero
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    func togglePlayback() {
        guard let player else { return }
        if player.rate > 0 {
            player.pause()
        } else {
            if currentTime >= duration - frameDuration {
                seek(to: 0)
            }
            player.play()
        }
    }

    func stopPlayback() {
        player?.pause()
        isPlaying = false
    }

    func stepFrame(by count: Int) {
        guard player != nil else { return }
        player?.pause()
        seek(to: currentTime + (Double(count) * frameDuration))
    }

    func beginScrubbing() {
        guard let player else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = player.rate > 0
        player.pause()
    }

    func scrub(to seconds: Double) {
        currentTime = min(max(0, seconds), duration)
        seek(to: currentTime)
    }

    func endScrubbing() {
        isScrubbing = false
        if wasPlayingBeforeScrub {
            player?.play()
        }
    }

    private func seek(to seconds: Double) {
        let clamped = min(max(0, seconds), duration)
        currentTime = clamped
        let time = CMTime(
            seconds: mediaStartTime.seconds + clamped,
            preferredTimescale: 60_000
        )
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func captureCurrentFrame() {
        guard !isCapturing, let asset, let videoURL else { return }

        let fallbackCaptureTime = CMTime(
            seconds: mediaStartTime.seconds + currentTime,
            preferredTimescale: 60_000
        )
        let captureTime = player?.currentTime() ?? fallbackCaptureTime
        let relativeCaptureSeconds = captureTime.seconds - mediaStartTime.seconds
        let captureSeconds = relativeCaptureSeconds.isFinite ? max(0, relativeCaptureSeconds) : currentTime
        isCapturing = true
        alertMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero

                let (image, _) = try await generator.image(at: captureTime)
                let capturedImage = try self.applyingOverlay(to: image)
                try self.save(image: capturedImage, videoURL: videoURL, seconds: captureSeconds)
                self.isCapturing = false
            } catch {
                self.isCapturing = false
                self.alertMessage = "The frame couldn’t be saved. \(error.localizedDescription)"
            }
        }
    }

    private func save(image: CGImage, videoURL: URL, seconds: Double) throws {
        let defaults = UserDefaults.standard
        let format = CaptureFormat(rawValue: defaults.string(forKey: PreferenceKey.captureFormat) ?? "png") ?? .png
        let destination = SaveDestination(rawValue: defaults.string(forKey: PreferenceKey.saveDestination) ?? "askEveryTime") ?? .askEveryTime
        let filename = CaptureFileName.make(videoURL: videoURL, seconds: seconds, extension: format.fileExtension)

        let outputURL: URL
        var accessedFolder: URL?

        if destination == .chosenFolder, let folder = FolderBookmarkStore.resolve() {
            if folder.startAccessingSecurityScopedResource() {
                accessedFolder = folder
            }
            outputURL = uniqueURL(in: folder, filename: filename)
        } else {
            let panel = NSSavePanel()
            panel.title = "Save Frame"
            panel.prompt = "Save"
            panel.nameFieldStringValue = filename
            panel.allowedContentTypes = [format.contentType]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let selectedURL = panel.url else {
                isCapturing = false
                return
            }
            outputURL = selectedURL
        }

        defer { accessedFolder?.stopAccessingSecurityScopedResource() }

        let quality = defaults.object(forKey: PreferenceKey.jpegQuality) as? Double ?? 0.9
        let data = try encodedData(for: image, format: format, quality: quality)
        try data.write(to: outputURL, options: .atomic)
        showToast("Saved \(outputURL.lastPathComponent)")
    }

    private func encodedData(for image: CGImage, format: CaptureFormat, quality: Double) throws -> Data {
        if format == .heic {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                format.contentType.identifier as CFString,
                1,
                nil
            ) else {
                throw PlayerError.couldNotEncode
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw PlayerError.couldNotEncode
            }
            return data as Data
        }

        guard let bitmapType = format.bitmapType else {
            throw PlayerError.couldNotEncode
        }
        let representation = NSBitmapImageRep(cgImage: image)
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if format == .jpeg {
            properties[.compressionFactor] = min(max(quality, 0.1), 1)
        }
        guard let data = representation.representation(using: bitmapType, properties: properties) else {
            throw PlayerError.couldNotEncode
        }
        return data
    }

    private func restoreOverlay() {
        guard let url = OverlayBookmarkStore.resolve() else { return }
        do {
            try loadOverlay(from: url, persistBookmark: false)
        } catch {
            OverlayBookmarkStore.clear()
        }
    }

    private func installOverlay(from url: URL) {
        do {
            try loadOverlay(from: url, persistBookmark: true)
            isOverlayEnabled = true
            UserDefaults.standard.set(true, forKey: PreferenceKey.overlayEnabled)
            showToast("Using \(url.lastPathComponent)")
        } catch {
            alertMessage = "That PNG couldn’t be used as an overlay. \(error.localizedDescription)"
        }
    }

    private func loadOverlay(from url: URL, persistBookmark: Bool) throws {
        let contentType = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
        guard contentType?.conforms(to: .png) == true else {
            throw PlayerError.overlayMustBePNG
        }

        let gainedSecurityScope = url.startAccessingSecurityScopedResource()
        guard let image = NSImage(contentsOf: url),
              image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else {
            if gainedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
            throw PlayerError.invalidOverlay
        }

        do {
            if persistBookmark {
                try OverlayBookmarkStore.save(url)
            }
        } catch {
            if gainedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }

        overlaySecurityScopedURL?.stopAccessingSecurityScopedResource()
        overlaySecurityScopedURL = gainedSecurityScope ? url : nil
        overlayImage = image
        overlayURL = url
    }

    private func applyingOverlay(to image: CGImage) throws -> CGImage {
        guard isOverlayEnabled, let overlayImage else { return image }
        guard let overlayCGImage = overlayImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            throw PlayerError.invalidOverlay
        }

        let outputExtent = CGRect(
            x: 0,
            y: 0,
            width: image.width,
            height: image.height
        )
        let overlayExtent = CGRect(
            x: 0,
            y: 0,
            width: overlayCGImage.width,
            height: overlayCGImage.height
        )
        guard !outputExtent.isEmpty, !overlayExtent.isEmpty else {
            throw PlayerError.invalidOverlay
        }

        let horizontalScale = outputExtent.width / overlayExtent.width
        let verticalScale = outputExtent.height / overlayExtent.height
        let scale = overlaySizing == .fit
            ? min(horizontalScale, verticalScale)
            : max(horizontalScale, verticalScale)
        let scaledSize = CGSize(
            width: overlayExtent.width * scale,
            height: overlayExtent.height * scale
        )
        let overlayTransform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(
                x: (outputExtent.width - scaledSize.width) / (2 * scale),
                y: (outputExtent.height - scaledSize.height) / (2 * scale)
            )

        let base = CIImage(cgImage: image)
        let overlay = CIImage(cgImage: overlayCGImage)
            .transformed(by: overlayTransform)
            .cropped(to: outputExtent)
        let result = overlay.composited(over: base).cropped(to: outputExtent)

        guard let compositedImage = overlayContext.createCGImage(result, from: outputExtent) else {
            throw PlayerError.couldNotCompositeOverlay
        }
        return compositedImage
    }

    private func uniqueURL(in folder: URL, filename: String) -> URL {
        let proposed = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: proposed.path) else { return proposed }

        let extensionName = proposed.pathExtension
        let stem = proposed.deletingPathExtension().lastPathComponent
        for number in 2...999 {
            let candidate = folder.appendingPathComponent("\(stem) \(number).\(extensionName)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return proposed
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }
}

private enum PlayerError: LocalizedError {
    case notPlayable
    case noVideoTrack
    case couldNotEncode
    case overlayMustBePNG
    case invalidOverlay
    case couldNotCompositeOverlay

    var errorDescription: String? {
        switch self {
        case .notPlayable: "The file is not playable."
        case .noVideoTrack: "The file has no video track."
        case .couldNotEncode: "The image could not be encoded in the selected format."
        case .overlayMustBePNG: "Choose a PNG file."
        case .invalidOverlay: "The overlay image is invalid."
        case .couldNotCompositeOverlay: "The overlay could not be composited onto the frame."
        }
    }
}
