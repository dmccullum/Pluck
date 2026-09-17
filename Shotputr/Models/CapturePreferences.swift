import AppKit
import Foundation
import UniformTypeIdentifiers

enum CaptureFormat: String, CaseIterable, Identifiable {
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
        case .askEveryTime: "Ask every time"
        case .chosenFolder: "Chosen folder"
        }
    }
}

enum OverlaySizing: String, CaseIterable, Identifiable {
    case fit
    case fill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: "Fit"
        case .fill: "Fill"
        }
    }
}

enum PreferenceKey {
    static let captureFormat = "captureFormat"
    static let saveDestination = "saveDestination"
    static let jpegQuality = "jpegQuality"
    static let folderBookmark = "folderBookmark"
    static let folderDisplayPath = "folderDisplayPath"
    static let overlayBookmark = "overlayBookmark"
    static let overlayDisplayPath = "overlayDisplayPath"
    static let overlayEnabled = "overlayEnabled"
    static let overlaySizing = "overlaySizing"
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

enum OverlayBookmarkStore {
    static func save(_ fileURL: URL) throws {
        let data = try fileURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: [.contentTypeKey],
            relativeTo: nil
        )
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: PreferenceKey.overlayBookmark)
        defaults.set(fileURL.path, forKey: PreferenceKey.overlayDisplayPath)
    }

    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: PreferenceKey.overlayBookmark) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            clear()
            return nil
        }

        if isStale {
            try? save(url)
        }
        return url
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PreferenceKey.overlayBookmark)
        defaults.removeObject(forKey: PreferenceKey.overlayDisplayPath)
    }
}

enum CaptureFileName {
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
