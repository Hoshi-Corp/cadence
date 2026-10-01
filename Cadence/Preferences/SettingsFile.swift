import Foundation

/// Reads and writes settings as a JSON file, for moving them between Macs.
enum SettingsFile {
    static let fileExtension = "json"
    private static let format = "com.masaruhoshi.cadence.settings"

    struct Contents: Codable {
        var format: String
        var version: Int
        var appVersion: String
        var exportedAt: Date
        var preferences: Preferences
    }

    enum ReadError: LocalizedError {
        case notASettingsFile
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notASettingsFile: "This file isn't a Cadence settings file."
            case .newerVersion: "This file was exported by a newer version of Cadence. Update Cadence and try again."
            }
        }
    }

    static func defaultFileName(on date: Date = Date()) -> String {
        "Cadence Settings \(WorkLogDocument.fileName(for: date).replacingOccurrences(of: ".md", with: "")).json"
    }

    static func encode(_ preferences: Preferences, appVersion: String, date: Date = Date()) throws -> Data {
        let contents = Contents(format: format, version: 1, appVersion: appVersion, exportedAt: date,
                                preferences: preferences)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(contents)
    }

    static func decode(_ data: Data) throws -> Contents {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let contents = try? decoder.decode(Contents.self, from: data), contents.format == format else {
            throw ReadError.notASettingsFile
        }
        guard contents.version <= 1 else { throw ReadError.newerVersion(contents.version) }
        var result = contents
        result.preferences = contents.preferences.sanitized()
        return result
    }

    /// The preferences to use after importing. The work log folder is per Mac,
    /// so it's only taken from the file when asked for.
    static func applying(_ imported: Preferences, to current: Preferences, includingLogFolder: Bool) -> Preferences {
        var result = imported
        if !includingLogFolder { result.logFolderPath = current.logFolderPath }
        return result
    }
}
