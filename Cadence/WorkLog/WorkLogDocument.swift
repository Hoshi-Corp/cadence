import Foundation

/// Pure text operations on a daily Markdown log.
///
/// Cadence only touches content between its HTML-comment markers, which are
/// invisible when rendered (including Obsidian's reading view). Anything the
/// user writes outside the markers is preserved as-is.
enum WorkLogDocument {
    enum Block: String {
        case timeline, summary

        var startMarker: String { "<!-- cadence:\(rawValue):start -->" }
        var endMarker: String { "<!-- cadence:\(rawValue):end -->" }
        var heading: String {
            switch self {
            case .timeline: "## Timeline"
            case .summary: "## Summary"
            }
        }
    }

    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.md", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func newDocument(for date: Date) -> String {
        """
        # Work Log — \(date.formatted(date: .complete, time: .omitted))

        \(Block.timeline.startMarker)
        \(Block.timeline.heading)

        \(Block.timeline.endMarker)

        """
    }

    /// Adds a list line at the end of the timeline, creating the block if the
    /// user removed it (or the file is a daily note Cadence didn't create).
    static func appendingTimelineLine(_ line: String, to text: String) -> String {
        guard let inner = innerRange(of: .timeline, in: text) else {
            return appendingBlock(.timeline, content: "\(Block.timeline.heading)\n\n\(line)", to: text)
        }
        let existing = text[inner].trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if existing.isEmpty {
            body = line
        } else {
            // Keep list items contiguous; leave a blank line after a heading or paragraph.
            let lastLine = existing.split(separator: "\n").last ?? ""
            body = existing + (lastLine.hasPrefix("- ") ? "\n" : "\n\n") + line
        }

        var result = text
        result.replaceSubrange(inner, with: "\n\(body)\n\n")
        return result
    }

    /// Replaces an exact timeline line, searching from the most recent.
    /// Returns nil if the line is gone (e.g. the user edited it).
    static func replacingTimelineLine(_ old: String, with new: String, in text: String) -> String? {
        guard let inner = innerRange(of: .timeline, in: text) else { return nil }
        var searchRange = inner
        while let found = text.range(of: old, options: .backwards, range: searchRange) {
            let startsLine = found.lowerBound == text.startIndex || text[text.index(before: found.lowerBound)] == "\n"
            let endsLine = found.upperBound == text.endIndex || text[found.upperBound] == "\n"
            if startsLine && endsLine {
                var result = text
                result.replaceSubrange(found, with: new)
                return result
            }
            searchRange = inner.lowerBound..<found.lowerBound
        }
        return nil
    }

    /// Replaces the whole content of a block, appending the block if missing.
    static func replacingBlock(_ block: Block, content: String, in text: String) -> String {
        guard let inner = innerRange(of: block, in: text) else {
            return appendingBlock(block, content: content, to: text)
        }
        var result = text
        result.replaceSubrange(inner, with: "\n\(content)\n")
        return result
    }

    // MARK: Helpers

    /// Range between the end of the start marker and the start of the end marker.
    private static func innerRange(of block: Block, in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: block.startMarker),
              let end = text.range(of: block.endMarker, range: start.upperBound..<text.endIndex)
        else { return nil }
        return start.upperBound..<end.lowerBound
    }

    private static func appendingBlock(_ block: Block, content: String, to text: String) -> String {
        var result = text
        while let last = result.last, last.isWhitespace { result.removeLast() }
        if !result.isEmpty { result += "\n\n" }
        result += "\(block.startMarker)\n\(content)\n\(block.endMarker)\n"
        return result
    }
}
