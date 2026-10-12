import AppKit
import AVFoundation
import Combine
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class VideoPlayerModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var videoURL: URL?
    @Published private(set) var duration: Double = 0
    @Published private(set) var videoAspectRatio: Double = 16.0 / 9.0
    @Published var currentTime: Double = 0
    @Published private(set) var shuttleRate: Float = 0
    @Published private(set) var controlsVisible = true
    @Published private(set) var isScrubbing = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPresentationReady = false
    @Published private(set) var presentationID = UUID()
    @Published private(set) var frameOperation: FrameOperation?
    @Published var alertMessage: String?
    @Published private(set) var toast: Toast?
    @Published private(set) var captureFlight: CaptureFlight?
    @Published private(set) var completedOperation: FrameOperation?
    @Published private(set) var videoDimensions: CGSize = .zero
    @Published private(set) var frameRate: Double = 30
    @Published private(set) var safeZone: SafeZone
    @Published private(set) var includesSafeZoneInCaptures: Bool

    private var asset: AVAsset?
    private var frameDuration = 1.0 / 30.0
    private var mediaStartTime = CMTime.zero
    private var timeObserver: Any?
    private var timeControlCancellable: AnyCancellable?
    private var presentationSizeCancellable: AnyCancellable?
    private var securityScopedURL: URL?
    private var rateBeforeScrub: Float = 0
    private var manualShuttleTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var previewGenerator: AVAssetImageGenerator?
    private var previewCache: [Int: CGImage] = [:]
    private var previewWarmupTask: Task<Void, Never>?
    private static let previewBucketCount = 150

    var documentOpener: ((URL) -> Void)?

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
        guard contentType?.conforms(to: .movie) == true
                || contentType?.conforms(to: .audiovisualContent) == true else {
            return false
        }
        open(url: url)
        return true
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
        showToast(zone == .off ? "Safe zone off" : "\(zone.title) safe zone", systemImage: zone == .off ? "eye.slash.fill" : "rectangle.dashed")
    }

    func open(url: URL) {
        guard url.isFileURL else {
            alertMessage = "Pluck can only open local video files."
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
        setControlsVisible(true)
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
        videoDimensions = presentationSize

        if minimumFrameDuration.isValid, minimumFrameDuration.seconds > 0 {
            frameDuration = minimumFrameDuration.seconds
        } else if nominalFrameRate > 0 {
            frameDuration = 1.0 / nominalFrameRate
        } else {
            frameDuration = 1.0 / 30.0
        }
        frameRate = nominalFrameRate > 0 ? nominalFrameRate : 1.0 / frameDuration

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        let tolerance = CMTime(seconds: max(frameDuration * 2, 0.04), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        previewGenerator = generator
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
        previewGenerator?.cancelAllCGImageGeneration()
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
        stopPlayback()
        seek(to: currentTime + (Double(count) * frameDuration))
    }

    func seekBy(_ seconds: Double) {
        guard player != nil else { return }
        stopPlayback()
        seek(to: currentTime + seconds)
    }

    func seekToStart() {
        guard player != nil else { return }
        stopPlayback()
        seek(to: 0)
    }

    func seekToEnd() {
        guard player != nil else { return }
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
        // Drop any decode still in flight; only the latest position matters.
        previewGenerator.cancelAllCGImageGeneration()
        let time = CMTime(seconds: mediaStartTime.seconds + min(max(0, seconds), duration), preferredTimescale: 600)
        return try? await previewGenerator.image(at: time).image
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
        guard frameOperation == nil, let asset, let videoURL else { return }

        let fallbackCaptureTime = CMTime(
            seconds: mediaStartTime.seconds + currentTime,
            preferredTimescale: 60_000
        )
        let captureTime = player?.rate == 0 ? fallbackCaptureTime : (player?.currentTime() ?? fallbackCaptureTime)
        let relativeCaptureSeconds = captureTime.seconds - mediaStartTime.seconds
        let captureSeconds = relativeCaptureSeconds.isFinite ? max(0, relativeCaptureSeconds) : currentTime
        frameOperation = operation
        alertMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero

                let (image, _) = try await generator.image(at: captureTime)
                let capturedImage = self.includesSafeZoneInCaptures && self.activeSafeZone != .off ? Self.drawing(self.activeSafeZone, onto: image) : image
                let thumbnail = Self.thumbnail(of: capturedImage)
                switch operation {
                case .save:
                    if let savedURL = try self.save(image: capturedImage, videoURL: videoURL, seconds: captureSeconds) {
                        self.celebrate(operation, thumbnail: thumbnail)
                        self.showToast(
                            "Saved \(savedURL.lastPathComponent)",
                            systemImage: "checkmark.circle.fill",
                            thumbnail: thumbnail,
                            revealURL: savedURL
                        )
                    }
                case .copy:
                    try self.copy(image: capturedImage)
                    self.celebrate(operation, thumbnail: thumbnail)
                    self.showToast("Copied to clipboard", systemImage: "doc.on.clipboard.fill", thumbnail: thumbnail)
                }
                self.frameOperation = nil
            } catch {
                self.frameOperation = nil
                let verb = operation == .copy ? "copied" : "saved"
                self.alertMessage = "The frame couldn’t be \(verb). \(error.localizedDescription)"
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
    private func save(image: CGImage, videoURL: URL, seconds: Double) throws -> URL? {
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
                return nil
            }
            outputURL = selectedURL
        }

        defer { accessedFolder?.stopAccessingSecurityScopedResource() }

        let quality = defaults.object(forKey: PreferenceKey.jpegQuality) as? Double ?? 0.9
        let data = try encodedData(for: image, format: format, quality: quality)
        try data.write(to: outputURL, options: .atomic)
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

    /// Burns the safe zone guide into a captured frame, matching what's shown on screen.
    private static func drawing(_ zone: SafeZone, onto image: CGImage) -> CGImage {
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

    private static func thumbnail(of image: CGImage, maxDimension: CGFloat = 480) -> NSImage {
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
            return NSImage(cgImage: image, size: size)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return NSImage(cgImage: context.makeImage() ?? image, size: size)
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

    private func showToast(
        _ message: String,
        systemImage: String = "checkmark.circle.fill",
        thumbnail: NSImage? = nil,
        revealURL: URL? = nil
    ) {
        toastTask?.cancel()
        let newToast = Toast(message: message, systemImage: systemImage, thumbnail: thumbnail, revealURL: revealURL)
        toast = newToast
        toastTask = Task { [weak self] in
            // Leave actionable toasts up long enough to reach the button.
            try? await Task.sleep(for: .seconds(revealURL == nil ? 2.4 : 4.5))
            guard !Task.isCancelled, self?.toast?.id == newToast.id else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }
}

enum FrameOperation {
    case save
    case copy
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let systemImage: String
    let thumbnail: NSImage?
    let revealURL: URL?

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
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
    case couldNotEncode
    case couldNotCopy

    var errorDescription: String? {
        switch self {
        case .notPlayable: "The file is not playable."
        case .noVideoTrack: "The file has no video track."
        case .couldNotEncode: "The image could not be encoded in the selected format."
        case .couldNotCopy: "The clipboard did not accept the image."
        }
    }
}
