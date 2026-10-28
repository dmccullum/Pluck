import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated enum CaptureFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case heic
    case tiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        default: rawValue
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    var bitmapType: NSBitmapImageRep.FileType? {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: nil
        case .tiff: .tiff
        }
    }
}

enum SaveDestination: String, CaseIterable, Identifiable {
    case askEveryTime
    case chosenFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askEveryTime: "Ask Every Time"
        case .chosenFolder: "Chosen Folder"
        }
    }

    /// Save Frame takes an ellipsis when it will show a save panel.
    var saveFrameTitle: String {
        self == .askEveryTime ? "Save Frame…" : "Save Frame"
    }

    static func saveFrameTitle(forRawValue rawValue: String) -> String {
        (SaveDestination(rawValue: rawValue) ?? .askEveryTime).saveFrameTitle
    }
}

enum PreferenceKey {
    static let captureFormat = "captureFormat"
    static let saveDestination = "saveDestination"
    static let jpegQuality = "jpegQuality"
    static let folderBookmark = "folderBookmark"
    static let folderDisplayPath = "folderDisplayPath"
    static let timeDisplay = "timeDisplay"
    static let safeZone = "safeZone"
    static let safeZoneInCaptures = "safeZoneInCaptures"
    static let lastSafeZone = "lastSafeZone"
    static let recentVideos = "recentVideos"
}

enum TimeDisplay: String, CaseIterable {
    case timecode
    case frames
    case clock

    var next: TimeDisplay {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    var title: String {
        switch self {
        case .timecode: "Timecode"
        case .frames: "Frame Number"
        case .clock: "Minutes and Seconds"
        }
    }
}

enum FolderBookmarkStore {
    static func save(_ folderURL: URL) throws {
        let data = try folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: PreferenceKey.folderBookmark)
        defaults.set(folderURL.path, forKey: PreferenceKey.folderDisplayPath)
    }

    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: PreferenceKey.folderBookmark) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            try? save(url)
        }
        return url
    }
}

nonisolated enum CaptureFileName {
    static func make(videoURL: URL, seconds: Double, extension fileExtension: String) -> String {
        let stem = videoURL.deletingPathExtension().lastPathComponent
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let safeStem = stem.components(separatedBy: invalidCharacters).joined(separator: "-")
        let totalMilliseconds = max(0, Int((seconds * 1_000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let secs = (totalMilliseconds / 1_000) % 60
        let millis = totalMilliseconds % 1_000
        let timecode = String(format: "%02d-%02d-%02d-%03d", hours, minutes, secs, millis)
        return "\(safeStem) — \(timecode).\(fileExtension)"
    }
}

/// Guides for where a platform's interface covers a 9:16 frame. Percentages are of the frame.
nonisolated enum SafeZone: String, CaseIterable, Identifiable, Sendable {
    case off
    /// Measured from Instagram's Edits app: 13% top, 20% bottom, 4.5% sides, plus a
    /// 17%-wide notch from 63% down for the like/comment/share buttons.
    case reels
    /// Meta's Facebook/Instagram ads guideline: 14% top, 35% bottom, 6% sides, plus a
    /// 21%-wide, 40%-tall bottom-right notch for the action buttons.
    case metaAds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .reels: "Reels"
        case .metaAds: "Meta Ads"
        }
    }

    /// The fuller name used in menus, which have room for it.
    var menuTitle: String {
        switch self {
        case .off: "Off"
        case .reels: "Instagram Reels"
        case .metaAds: "Meta Ads"
        }
    }

    /// The safe area as a closed polygon in unit coordinates (0–1, origin top-left).
    var polygon: [CGPoint] {
        switch self {
        case .off:
            []
        case .reels:
            [CGPoint(x: 0.045, y: 0.13), CGPoint(x: 0.955, y: 0.13),
             CGPoint(x: 0.955, y: 0.63), CGPoint(x: 0.83, y: 0.63),
             CGPoint(x: 0.83, y: 0.80), CGPoint(x: 0.045, y: 0.80)]
        case .metaAds:
            [CGPoint(x: 0.06, y: 0.14), CGPoint(x: 0.94, y: 0.14),
             CGPoint(x: 0.94, y: 0.60), CGPoint(x: 0.79, y: 0.60),
             CGPoint(x: 0.79, y: 0.65), CGPoint(x: 0.06, y: 0.65)]
        }
    }
}

/// A video file plus a security-scoped bookmark to it, so a sandboxed relaunch can open
/// it again. Video windows are keyed by this for state restoration, and Open Recent lists them.
nonisolated struct VideoReference: Codable, Hashable, Sendable {
    let url: URL
    let bookmark: Data?

    /// Call while the app still has access to `url`, such as right after the user opens it.
    init(url: URL) {
        self.url = url
        bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// The bookmarked file, wherever it has moved to, or the saved path if the bookmark fails.
    func resolve() -> URL {
        guard let bookmark else { return url }
        var isStale = false
        return (try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )) ?? url
    }

    static func == (lhs: VideoReference, rhs: VideoReference) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

/// The File > Open Recent list, newest first. Also feeds the Dock menu's recent items.
@Observable
final class RecentVideos {
    static let shared = RecentVideos()
    private static let limit = 10

    private(set) var videos: [VideoReference]

    private init() {
        let data = UserDefaults.standard.data(forKey: PreferenceKey.recentVideos)
        videos = data.flatMap { try? JSONDecoder().decode([VideoReference].self, from: $0) } ?? []
    }

    func note(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        videos.removeAll { $0.url == url }
        videos.insert(VideoReference(url: url), at: 0)
        videos = Array(videos.prefix(Self.limit))
        save()
    }

    func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        videos = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(videos), forKey: PreferenceKey.recentVideos)
    }
}
