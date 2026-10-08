import Foundation

/// Owns the Qingyu Application Support directory layout used by Core Data and
/// large clipboard resources.
struct AssistantFileSystem: Hashable {
    var rootDirectory: URL

    /// A historical Application Support directory/store pair kept for migration.
    struct LegacySource: Hashable {
        let directoryName: String
        let storeFileName: String
    }

    /// The Application Support subdirectory name for the active data root.
    /// Renamed from "Qingniao" (and before that "Assistant"). Migration of an
    /// existing legacy directory is handled by `DataDirectoryMigrator`.
    static let directoryName = "Qingyu"

    /// The Core Data SQLite store file name for the active data root.
    static let storeFileName = "Qingyu.sqlite"

    /// Legacy Application Support sources, newest first. Migration tries each
    /// until one directory is found.
    static let legacySources: [LegacySource] = [
        LegacySource(directoryName: "Qingniao", storeFileName: "Qingniao.sqlite"),
        LegacySource(directoryName: "Assistant", storeFileName: "Assistant.sqlite"),
    ]

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var `default`: AssistantFileSystem {
        AssistantFileSystem(rootDirectory: applicationSupportDirectory.appendingPathComponent(directoryName, isDirectory: true))
    }

    var storeURL: URL {
        rootDirectory.appendingPathComponent(Self.storeFileName, isDirectory: false)
    }

    var clipboardDirectory: URL {
        rootDirectory.appendingPathComponent("Clipboard", isDirectory: true)
    }

    var imagesDirectory: URL {
        clipboardDirectory.appendingPathComponent("Images", isDirectory: true)
    }

    var thumbnailsDirectory: URL {
        clipboardDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    var richTextDirectory: URL {
        clipboardDirectory.appendingPathComponent("RichText", isDirectory: true)
    }

    var logsDirectory: URL {
        rootDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    func ensureDirectoryStructure(fileManager: FileManager = .default) throws {
        for directory in [rootDirectory, clipboardDirectory, imagesDirectory, thumbnailsDirectory, richTextDirectory, logsDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func resourcePath(for id: UUID, type: AssistantClipboardResourceType) -> String {
        "Clipboard/\(type.directoryName)/\(id.uuidString).\(type.fileExtension)"
    }

    func resourceURL(relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }
}

enum AssistantClipboardResourceType: String, CaseIterable {
    case imageOriginal
    case imageThumbnail
    case richTextRTF
    case richTextHTML

    var directoryName: String {
        switch self {
        case .imageOriginal:
            return "Images"
        case .imageThumbnail:
            return "Thumbnails"
        case .richTextRTF, .richTextHTML:
            return "RichText"
        }
    }

    var fileExtension: String {
        switch self {
        case .imageOriginal, .imageThumbnail:
            return "png"
        case .richTextRTF:
            return "rtf"
        case .richTextHTML:
            return "html"
        }
    }

    var mimeType: String {
        switch self {
        case .imageOriginal, .imageThumbnail:
            return "image/png"
        case .richTextRTF:
            return "application/rtf"
        case .richTextHTML:
            return "text/html"
        }
    }
}
