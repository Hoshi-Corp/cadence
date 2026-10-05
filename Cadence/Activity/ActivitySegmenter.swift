import Foundation

/// Pure operations that turn app spans into segments and apply the user's edits.
enum ActivitySegmenter {
    /// Spans with the same key belong in one segment: a rule's task, or else the app.
    static func key(for span: AppSpan, rules: [ActivityRule]) -> String {
        if let task = rules.task(for: span) { return "task:\(task.lowercased())" }
        return "app:\(span.bundleID ?? span.appName)"
    }

    /// Adds a finished span to a day's segments.
    ///
    /// It extends the last segment when it's the same activity, or when it's a
    /// switch shorter than `minimum`. A longer switch starts a new segment, taking
    /// along any short spans of the same activity that were just folded in.
    static func append(
        _ span: AppSpan,
        to segments: [ActivitySegment],
        rules: [ActivityRule],
        minimum: TimeInterval,
        newID: UUID = UUID()
    ) -> [ActivitySegment] {
        guard span.duration > 0 else { return segments }
        var segments = segments
        guard var last = segments.popLast() else { return [ActivitySegment(id: newID, spans: [span])] }

        let gap = span.start.timeIntervalSince(last.end)
        guard gap >= 0, gap < minimum else {
            return segments + [last, ActivitySegment(id: newID, spans: [span])]
        }

        let key = key(for: span, rules: rules)
        let lastKey = last.mainKey(rules: rules)
        if lastKey == key {
            last.add([span])
            return segments + [last]
        }

        // The same activity may already have started at the end of the last
        // segment, folded in while it still looked like a short switch.
        var run = [span]
        if !last.isEdited {
            while last.spans.count > 1, let tail = last.spans.last, Self.key(for: tail, rules: rules) == key {
                run.insert(last.spans.removeLast(), at: 0)
            }
        }
        let runDuration = run.reduce(0) { $0 + $1.duration }

        if runDuration < minimum {
            last.add(run)
            return segments + [last]
        }
        if !last.isEdited && last.duration < minimum {
            // A short segment before a new activity was only passing through.
            last.add(run)
            return segments + [last]
        }
        return segments + [last, ActivitySegment(id: newID, spans: run)]
    }

    /// Joins segments that sit next to each other. Returns nil unless `ids`
    /// picks out two or more neighbouring segments.
    static func merging(_ ids: Set<UUID>, in segments: [ActivitySegment]) -> [ActivitySegment]? {
        let indices = segments.indices.filter { ids.contains(segments[$0].id) }
        guard indices.count >= 2, indices.last! - indices.first! == indices.count - 1 else { return nil }
        let picked = indices.map { segments[$0] }
        var merged = picked[0]
        merged.add(picked.dropFirst().flatMap(\.spans))
        merged.task = picked.lazy.compactMap(\.task).first
        merged.isExcluded = picked.allSatisfy(\.isExcluded)
        merged.isEdited = true
        var result = segments
        result.replaceSubrange(indices.first!...indices.last!, with: [merged])
        return result
    }

    /// Cuts a segment in two at `date`. Returns nil unless `date` falls inside it.
    static func splitting(_ id: UUID, at date: Date, in segments: [ActivitySegment], newID: UUID = UUID())
        -> [ActivitySegment]? {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let segment = segments[index]
        guard date > segment.start, date < segment.end else { return nil }

        var before: [AppSpan] = []
        var after: [AppSpan] = []
        for span in segment.spans {
            if span.end <= date {
                before.append(span)
            } else if span.start >= date {
                after.append(span)
            } else {
                var head = span, tail = span
                head.end = date
                tail.start = date
                before.append(head)
                after.append(tail)
            }
        }
        guard !before.isEmpty, !after.isEmpty else { return nil }

        var first = segment
        first.spans = before
        first.isEdited = true
        var second = segment
        second.id = newID
        second.spans = after
        second.isEdited = true
        var result = segments
        result.replaceSubrange(index...index, with: [first, second])
        return result
    }

    /// Names a segment, or clears its name when `task` is blank.
    static func renaming(_ id: UUID, to task: String, in segments: [ActivitySegment]) -> [ActivitySegment] {
        segments.map { segment in
            guard segment.id == id else { return segment }
            var renamed = segment
            let task = LogEntry.singleLine(task)
            renamed.task = task.isEmpty ? nil : task
            renamed.isEdited = true
            return renamed
        }
    }

    static func settingExcluded(_ excluded: Bool, for ids: Set<UUID>, in segments: [ActivitySegment])
        -> [ActivitySegment] {
        segments.map { segment in
            guard ids.contains(segment.id) else { return segment }
            var changed = segment
            changed.isExcluded = excluded
            changed.isEdited = true
            return changed
        }
    }
}
