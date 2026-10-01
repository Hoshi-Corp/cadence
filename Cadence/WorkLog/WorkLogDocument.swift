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

    /// The list lines (`- …`) in the timeline block, in file order.
    static func timelineItems(in text: String) -> [TimelineItem] {
        itemRanges(in: text).enumerated().map { TimelineItem(index: $0.offset, line: String(text[$0.element])) }
    }

    /// Replaces the timeline item at `index`, or removes it when `new` is nil.
    /// Returns nil if that item no longer reads `expected`, which means the
    /// file changed since it was loaded.
    static func replacingTimelineItem(at index: Int, expected: String, with new: String?, in text: String) -> String? {
        let ranges = itemRanges(in: text)
        guard ranges.indices.contains(index), text[ranges[index]] == expected else { return nil }
        var result = text
        let range = ranges[index]
        if let new {
            result.replaceSubrange(range, with: new)
        } else {
            // Take the line break with it so no blank line is left behind.
            let end = range.upperBound < text.endIndex && text[range.upperBound] == "\n"
                ? text.index(after: range.upperBound) : range.upperBound
            result.removeSubrange(range.lowerBound..<end)
        }
        return result
    }

    // MARK: Helpers

    /// Ranges of the list lines inside the timeline block, without line breaks.
    private static func itemRanges(in text: String) -> [Range<String.Index>] {
        guard let inner = innerRange(of: .timeline, in: text) else { return [] }
        var ranges: [Range<String.Index>] = []
        var lineStart = inner.lowerBound
        while lineStart < inner.upperBound {
            let lineEnd = text[lineStart..<inner.upperBound].firstIndex(of: "\n") ?? inner.upperBound
            if text[lineStart..<lineEnd].hasPrefix("- ") {
                ranges.append(lineStart..<lineEnd)
            }
            lineStart = lineEnd < inner.upperBound ? text.index(after: lineEnd) : inner.upperBound
        }
        return ranges
    }

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
