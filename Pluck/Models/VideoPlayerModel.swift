import AppKit
import AVFoundation
import Combine
import DMKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class VideoPlayerModel {
    private(set) var player: AVPlayer?
    private(set) var videoURL: URL?
    private(set) var duration: Double = 0
    private(set) var videoAspectRatio: Double = 16.0 / 9.0
    var currentTime: Double = 0
    private(set) var shuttleRate: Float = 0
    private(set) var controlsVisible = true
    private(set) var isScrubbing = false
    private(set) var isLoading = false
    private(set) var isPresentationReady = false
    private(set) var presentationID = UUID()
    private(set) var frameOperation: FrameOperation?
    var alert: PlayerAlert?
    /// What just happened, shown in the window's status capsule.
    var status: StatusMessage?
    private(set) var captureFlight: CaptureFlight?
    private(set) var completedOperation: FrameOperation?
    private(set) var videoDimensions: CGSize = .zero
    private(set) var frameRate: Double = 30
    private(set) var safeZone: SafeZone
    private(set) var includesSafeZoneInCaptures: Bool
    /// Bumped by every frame step and jump, so the player can show its controls
    /// for keyboard navigation the way it does for pointer movement.
    private(set) var navigationCount = 0

    @ObservationIgnored private var asset: AVAsset?
    @ObservationIgnored private var frameDuration = 1.0 / 30.0
    @ObservationIgnored private var mediaStartTime = CMTime.zero
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var timeControlCancellable: AnyCancellable?
    @ObservationIgnored private var presentationSizeCancellable: AnyCancellable?
    @ObservationIgnored private var securityScopedURL: URL?
    /// A file opened for security-scoped access while it loads, before it becomes `securityScopedURL`.
    @ObservationIgnored private var pendingScopedURL: URL?
    @ObservationIgnored private var rateBeforeScrub: Float = 0
    @ObservationIgnored private var manualShuttleTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var previewGenerator: PreviewFrameGenerator?
    @ObservationIgnored private var previewCache: [Int: CGImage] = [:]
    @ObservationIgnored private var previewWarmupTask: Task<Void, Never>?
    private static let previewBucketCount = 150

    @ObservationIgnored var documentOpener: ((URL) -> Void)?
    /// The window this model plays in, for attaching open and save panels as sheets.
    @ObservationIgnored weak var window: NSWindow?

    /// Safe zone guides are designed for 9:16 video, so they're only offered for that (with a little tolerance for odd pixel sizes).
    var supportsSafeZone: Bool { hasVideo && abs(videoAspectRatio - 9.0 / 16.0) < 0.01 }
    /// The zone actually shown and burned into captures: off unless the video is 9:16.
    var activeSafeZone: SafeZone { supportsSafeZone ? safeZone : .off }

    var hasVideo: Bool { player != nil && videoURL != nil }
    var isPlaying: Bool { shuttleRate != 0 }
    var isCapturing: Bool { frameOperation != nil }
    var isSavingFrame: Bool { frameOperation == .save }
    var isCopyingFrame: Bool { frameOperation == .copy }
    var secondsPerFrame: Double { frameDuration }
    var currentFrameIndex: Int { frameIndex(at: currentTime) }

    func frameIndex(at seconds: Double) -> Int {
        guard frameDuration > 0, seconds.isFinite else { return 0 }
        // The epsilon keeps exact frame boundaries from rounding down a frame.
        return max(0, Int(floor(seconds / frameDuration + 0.001)))
    }

    func setControlsVisible(_ visible: Bool) {
        guard controlsVisible != visible else { return }
        controlsVisible = visible
    }

    init() {
        let defaults = UserDefaults.standard
        safeZone = SafeZone(rawValue: defaults.string(forKey: PreferenceKey.safeZone) ?? "") ?? .off
        includesSafeZoneInCaptures = defaults.bool(forKey: PreferenceKey.safeZoneInCaptures)
    }

    static func makeOpenPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Open a Video"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.movie, .audiovisualContent]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel
    }

    func presentOpenPanel() {
        let panel = Self.makeOpenPanel()
        Task {
            guard await panel.present(in: window) == .OK, let url = panel.url else { return }
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

    /// Opens the first dropped video here and the rest in new windows.
    @discardableResult
    func handleDrop(urls: [URL]) -> Bool {
        let videos = urls.filter { url in
            let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
            return contentType?.conforms(to: .movie) == true
                || contentType?.conforms(to: .audiovisualContent) == true
        }
        guard let first = videos.first else { return false }
        open(url: first)
        // This window is loading now, so the document opener sends the rest to new windows.
        for url in videos.dropFirst() {
            requestOpen(url: url)
        }
        return true
    }

    func showVideoInFinder() {
        guard let videoURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([videoURL])
    }

    func setIncludesSafeZoneInCaptures(_ included: Bool) {
        includesSafeZoneInCaptures = included
        UserDefaults.standard.set(included, forKey: PreferenceKey.safeZoneInCaptures)
    }

    /// Turns the guide off, or back on to the zone used most recently (Reels at first).
    func toggleSafeZone() {
        guard supportsSafeZone else { return }
        if safeZone != .off {
            setSafeZone(.off)
        } else {
            let last = SafeZone(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.lastSafeZone) ?? "")
            setSafeZone(last.flatMap { $0 == .off ? nil : $0 } ?? .reels)
        }
    }

    func setSafeZone(_ zone: SafeZone) {
        guard zone != safeZone else { return }
        safeZone = zone
        UserDefaults.standard.set(zone.rawValue, forKey: PreferenceKey.safeZone)
        if zone != .off {
            UserDefaults.standard.set(zone.rawValue, forKey: PreferenceKey.lastSafeZone)
        }
        status = StatusMessage(zone == .off ? "Safe zone off" : "\(zone.title) safe zone")
    }

    func open(url: URL) {
        guard url.isFileURL else {
            alert = PlayerAlert(title: "Couldn’t Open Video", message: "Pluck can only open local video files.")
            return
        }

        // Files resolved from bookmarks (restored windows, Open Recent) need access before
        // anything reads them. Dropped and chosen files already have it, and this returns false.
        endPendingAccess()
        if url.startAccessingSecurityScopedResource() {
            pendingScopedURL = url
        }

        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        guard type?.conforms(to: .movie) == true || type?.conforms(to: .audiovisualContent) == true else {
            endPendingAccess()
            alert = PlayerAlert(title: "Couldn’t Open Video", message: "That file doesn’t appear to be a video.")
            return
        }

        loadTask?.cancel()
        player?.pause()
        isLoading = true
        isPresentationReady = false
        setControlsVisible(true)
        alert = nil

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
                self.endPendingAccess()
                self.isLoading = false
                self.isPresentationReady = self.hasVideo
                self.alert = PlayerAlert(title: "Couldn’t Open Video", message: error.localizedDescription)
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

        if pendingScopedURL == url {
            securityScopedURL = url
            pendingScopedURL = nil
        }
        RecentItems.videos.note(url)

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
        videoDimensions = presentationSize

        if minimumFrameDuration.isValid, minimumFrameDuration.seconds > 0 {
            frameDuration = minimumFrameDuration.seconds
        } else if nominalFrameRate > 0 {
            frameDuration = 1.0 / nominalFrameRate
        } else {
            frameDuration = 1.0 / 30.0
        }
        frameRate = nominalFrameRate > 0 ? nominalFrameRate : 1.0 / frameDuration

        let tolerance = CMTime(seconds: max(frameDuration * 2, 0.04), preferredTimescale: 600)
        previewGenerator = PreviewFrameGenerator(asset: asset, tolerance: tolerance)
        warmPreviewCache(for: asset)

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
            .removeDuplicates()
            .sink { [weak self] rate in
                guard let self, self.manualShuttleTask == nil else { return }
                self.shuttleRate = rate
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
        stopPlayback()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeControlCancellable = nil
        presentationSizeCancellable = nil
        player = nil
        asset = nil
        previewGenerator?.cancel()
        previewGenerator = nil
        previewWarmupTask?.cancel()
        previewWarmupTask = nil
        previewCache = [:]
        videoURL = nil
        videoDimensions = .zero
        isPresentationReady = false
        videoAspectRatio = 16.0 / 9.0
        mediaStartTime = .zero
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    private func endPendingAccess() {
        pendingScopedURL?.stopAccessingSecurityScopedResource()
        pendingScopedURL = nil
    }

    func togglePlayback() {
        guard player != nil else { return }
        if isPlaying {
            stopPlayback()
        } else {
            setShuttleRate(1)
        }
    }

    func stopPlayback() {
        manualShuttleTask?.cancel()
        manualShuttleTask = nil
        player?.pause()
        shuttleRate = 0
    }

    func shuttleBackward() {
        let speed = shuttleRate < 0 ? min(abs(shuttleRate) * 2, 8) : 1
        setShuttleRate(-speed)
    }

    func shuttleForward() {
        let speed = shuttleRate > 0 ? min(shuttleRate * 2, 8) : 1
        setShuttleRate(speed)
    }

    private func setShuttleRate(_ rate: Float) {
        guard let player, let item = player.currentItem else { return }
        if rate < 0, currentTime <= 0 { stopPlayback(); return }
        if rate > 0, currentTime >= duration - frameDuration { seek(to: 0) }

        manualShuttleTask?.cancel()
        manualShuttleTask = nil

        let canPlayNatively = rate > 0
            ? (rate <= 1 || item.canPlayFastForward)
            : (rate >= -1 ? item.canPlayReverse : item.canPlayFastReverse)
        if canPlayNatively {
            player.playImmediately(atRate: rate)
        } else {
            player.pause()
            startManualShuttle(at: rate)
        }
        shuttleRate = rate
    }

    private func startManualShuttle(at rate: Float) {
        manualShuttleTask = Task { [weak self] in
            guard let self else { return }
            var position = self.currentTime
            var previousTick = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                position += (now - previousTick) * Double(rate)
                previousTick = now
                if position <= 0 || position >= self.duration {
                    self.seek(to: min(max(0, position), max(0, self.duration - self.frameDuration)))
                    self.stopPlayback()
                    return
                }
                self.seek(to: position)
            }
        }
    }

    func stepFrame(by count: Int) {
        guard player != nil else { return }
        navigationCount += 1
        stopPlayback()
        seek(to: currentTime + (Double(count) * frameDuration))
    }

    func seekBy(_ seconds: Double) {
        guard player != nil else { return }
        navigationCount += 1
        stopPlayback()
        seek(to: currentTime + seconds)
    }

    func seekToStart() {
        guard player != nil else { return }
        navigationCount += 1
        stopPlayback()
        seek(to: 0)
    }

    func seekToEnd() {
        guard player != nil else { return }
        navigationCount += 1
        stopPlayback()
        seek(to: max(0, duration - frameDuration))
    }

    func beginScrubbing() {
        guard player != nil else { return }
        isScrubbing = true
        rateBeforeScrub = shuttleRate
        stopPlayback()
    }

    func scrub(to seconds: Double) {
        currentTime = min(max(0, seconds), duration)
        seek(to: currentTime)
    }

    func endScrubbing() {
        isScrubbing = false
        if rateBeforeScrub != 0 {
            setShuttleRate(rateBeforeScrub)
        }
        rateBeforeScrub = 0
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

    /// The nearest pre-built thumbnail, available instantly while the pointer moves.
    func cachedPreview(at seconds: Double) -> CGImage? {
        guard duration > 0, !previewCache.isEmpty else { return nil }
        let bucket = previewBucket(for: seconds)
        for distance in 0..<Self.previewBucketCount {
            if let image = previewCache[bucket - distance] ?? previewCache[bucket + distance] {
                return image
            }
        }
        return nil
    }

    /// A sharper thumbnail near `seconds`, for when the pointer comes to rest.
    func previewImage(at seconds: Double) async -> CGImage? {
        guard let previewGenerator else { return nil }
        let time = CMTime(seconds: mediaStartTime.seconds + min(max(0, seconds), duration), preferredTimescale: 600)
        return await previewGenerator.image(at: time)
    }

    private func previewBucket(for seconds: Double) -> Int {
        let fraction = duration > 0 ? min(max(0, seconds / duration), 1) : 0
        return min(Self.previewBucketCount - 1, Int(fraction * Double(Self.previewBucketCount)))
    }

    /// Decodes a coarse strip of keyframe thumbnails in the background so hover previews
    /// can appear immediately instead of waiting on a full decode.
    private func warmPreviewCache(for asset: AVAsset) {
        previewWarmupTask?.cancel()
        previewCache = [:]
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let count = Self.previewBucketCount
        let times = (0..<count).map { index in
            CMTime(
                seconds: mediaStartTime.seconds + duration * (Double(index) + 0.5) / Double(count),
                preferredTimescale: 600
            )
        }
        previewWarmupTask = Task { [weak self] in
            for await result in generator.images(for: times) {
                guard let self, !Task.isCancelled else {
                    generator.cancelAllCGImageGeneration()
                    return
                }
                guard let image = try? result.image else { continue }
                let bucket = self.previewBucket(for: result.requestedTime.seconds - self.mediaStartTime.seconds)
                self.previewCache[bucket] = image
            }
        }
    }

    func captureCurrentFrame() {
        processCurrentFrame(for: .save)
    }

    func copyCurrentFrame() {
        processCurrentFrame(for: .copy)
    }

    private func processCurrentFrame(for operation: FrameOperation) {
        guard frameOperation == nil, asset != nil, let videoURL else { return }

        let fallbackCaptureTime = CMTime(
            seconds: mediaStartTime.seconds + currentTime,
            preferredTimescale: 60_000
        )
        let captureTime = player?.rate == 0 ? fallbackCaptureTime : (player?.currentTime() ?? fallbackCaptureTime)
        let relativeCaptureSeconds = captureTime.seconds - mediaStartTime.seconds
        let captureSeconds = relativeCaptureSeconds.isFinite ? max(0, relativeCaptureSeconds) : currentTime
        frameOperation = operation
        alert = nil

        let burnedInZone = includesSafeZoneInCaptures ? activeSafeZone : .off

        Task { [weak self] in
            do {
                let (capturedImage, thumbnailImage) = try await FrameRenderer.frame(ofVideoAt: videoURL, at: captureTime, safeZone: burnedInZone)
                guard let self else { return }
                let thumbnail = NSImage(cgImage: thumbnailImage, size: .zero)
                switch operation {
                case .save:
                    if let savedURL = try await self.save(image: capturedImage, videoURL: videoURL, seconds: captureSeconds) {
                        self.celebrate(operation, thumbnail: thumbnail)
                        self.status = StatusMessage(
                            "Saved “\(savedURL.lastPathComponent)”",
                            leading: .thumbnail(thumbnail),
                            action: .init("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                            }
                        )
                    }
                case .copy:
                    try self.copy(image: capturedImage)
                    self.celebrate(operation, thumbnail: thumbnail)
                    self.status = StatusMessage("Copied to clipboard", leading: .image(Image(systemName: "doc.on.clipboard")))
                }
                self.frameOperation = nil
            } catch {
                guard let self else { return }
                self.frameOperation = nil
                self.alert = PlayerAlert(
                    title: operation == .copy ? "Couldn’t Copy Frame" : "Couldn’t Save Frame",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func copy(image: CGImage) throws {
        let pasteboard = NSPasteboard.general
        let clipboardImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        pasteboard.clearContents()
        guard pasteboard.writeObjects([clipboardImage]) else {
            throw PlayerError.couldNotCopy
        }
    }

    /// Returns the written file, or nil when the user cancels the save panel.
    private func save(image: CGImage, videoURL: URL, seconds: Double) async throws -> URL? {
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
            guard await panel.present(in: window) == .OK, let selectedURL = panel.url else {
                return nil
            }
            outputURL = selectedURL
        }

        defer { accessedFolder?.stopAccessingSecurityScopedResource() }

        let quality = defaults.object(forKey: PreferenceKey.jpegQuality) as? Double ?? 0.9
        try await FrameRenderer.write(image, format: format, quality: quality, to: outputURL)
        return outputURL
    }

    private func celebrate(_ operation: FrameOperation, thumbnail: NSImage) {
        captureFlight = CaptureFlight(image: thumbnail, operation: operation)
        completedOperation = operation
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.completedOperation = nil
            self?.captureFlight = nil
        }
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
}

enum FrameOperation {
    case save
    case copy
}

/// An error alert, titled with what failed.
struct PlayerAlert {
    let title: String
    let message: String
}

struct CaptureFlight: Identifiable, Equatable {
    let id = UUID()
    let image: NSImage
    let operation: FrameOperation

    static func == (lhs: CaptureFlight, rhs: CaptureFlight) -> Bool { lhs.id == rhs.id }
}

private enum PlayerError: LocalizedError {
    case notPlayable
    case noVideoTrack
    case couldNotCopy

    var errorDescription: String? {
        switch self {
        case .notPlayable: "The file is not playable."
        case .noVideoTrack: "The file has no video track."
        case .couldNotCopy: "The clipboard did not accept the image."
        }
    }
}
