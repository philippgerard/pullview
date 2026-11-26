import Foundation

public struct CheckSummary: Sendable, Equatable {
    public var failed = 0, pending = 0, passed = 0, skipped = 0
    public var total: Int { failed + pending + passed + skipped }
}

public struct Badge: Sendable, Hashable {
    /// Color is reserved for these three states. Everything else renders secondary.
    public enum Tone: Sendable { case neutral, failing, running, merging }
    public var symbol: String? = nil
    public let text: String
    public var tone: Tone = .neutral
    /// Full wording for the tooltip and VoiceOver when `text` is abbreviated.
    public var help: String? = nil
}

extension PullRequest {
    public var checkSummary: CheckSummary {
        checks.reduce(into: CheckSummary()) { s, check in
            switch check.outcome {
            case .failed: s.failed += 1
            case .pending: s.pending += 1
            case .passed: s.passed += 1
            case .skipped: s.skipped += 1
            }
        }
    }

    /// GitHub's rollup covers every context, including those past the fetched page.
    public var checksFailing: Bool {
        checkSummary.failed > 0 || ["FAILURE", "ERROR"].contains(statusCheckRollup?.state)
    }

    public var checksPending: Bool {
        !checksFailing && (checkSummary.pending > 0 || ["PENDING", "EXPECTED"].contains(statusCheckRollup?.state))
    }

    /// Contexts GitHub reported beyond the fetched page.
    public var unfetchedCheckCount: Int {
        max((statusCheckRollup?.contexts.totalCount ?? 0) - checks.count, 0)
    }

    /// Failing and running checks, failing first. Passed and skipped checks are left out.
    public var attentionChecks: [Check] {
        checks.filter { $0.outcome <= .pending }.sorted { ($0.outcome, $0.name) < ($1.outcome, $1.name) }
    }

    /// The leading-column glyph. The most urgent state wins: failing, merging, running, then quiet states.
    public var status: Badge {
        let s = checkSummary
        var problems: [String] = []
        if mergeQueueEntry?.state == "UNMERGEABLE" { problems.append("Unmergeable in merge queue") }
        if checksFailing {
            let names = attentionChecks.filter { $0.outcome == .failed }.map(\.name)
            problems.append(names.isEmpty ? "Checks failed" : "Failed: " + names.joined(separator: ", "))
        }
        if mergeQueueEntry == nil, mergeStateStatus == "DIRTY" { problems.append("Conflicts") }
        if reviewDecision == "CHANGES_REQUESTED" { problems.append("Changes requested") }
        if !problems.isEmpty {
            return Badge(symbol: "xmark.circle.fill", text: problems.joined(separator: "\n"), tone: .failing)
        }
        if mergeQueueEntry?.state == "MERGEABLE" { return Badge(symbol: "arrow.triangle.merge", text: "Merging", tone: .merging) }
        if checksPending {
            return Badge(text: s.pending > 0 ? "\(s.total - s.pending) of \(s.total) checks done" : "Checks running", tone: .running)
        }
        if isDraft { return Badge(symbol: "circle.dashed", text: "Draft") }
        if reviewDecision == "REVIEW_REQUIRED" { return Badge(symbol: "circle", text: "Waiting for review") }
        return Badge(symbol: "checkmark.circle", text: s.total > 0 ? "Checks passed, no blockers" : "No blockers")
    }

    /// Short facts for the secondary line. Passing checks are omitted; the details list them.
    public var facts: [Badge] {
        var out: [Badge] = []
        if isDraft { out.append(Badge(text: "Draft")) }
        switch reviewDecision {
        case "APPROVED": out.append(Badge(text: "Approved"))
        case "CHANGES_REQUESTED": out.append(Badge(text: "Changes requested", tone: .failing))
        case "REVIEW_REQUIRED": out.append(Badge(text: "Review required"))
        default: break
        }
        let s = checkSummary
        if checksFailing { out.append(Badge(text: s.failed > 0 ? "\(s.failed) failed" : "Checks failed", tone: .failing)) }
        if s.pending > 0 { out.append(Badge(text: "\(s.pending) running", tone: .running)) }
        if let stack, let stackEntry { out.append(Badge(text: "Stack \(stackEntry.position)/\(stack.size)")) }
        if mergeQueueEntry == nil {
            switch mergeStateStatus {
            case "DIRTY": out.append(Badge(text: "Conflicts", tone: .failing))
            case "BEHIND": out.append(Badge(text: "Behind base"))
            default: break
            }
        }
        return out
    }

    /// The trailing slot: merge queue position and ETA, or the pending auto-merge.
    public var merge: Badge? {
        if let q = mergeQueueEntry {
            let state = [
                "QUEUED": "queued", "AWAITING_CHECKS": "awaiting checks", "MERGEABLE": "merging",
                "UNMERGEABLE": "unmergeable", "LOCKED": "locked",
            ][q.state] ?? q.state.lowercased()
            let eta = q.estimatedTimeToMerge.map { " · ~\(Self.duration($0))" } ?? ""
            let tone: Badge.Tone = switch q.state {
            case "UNMERGEABLE": .failing
            case "MERGEABLE": .merging
            default: .neutral
            }
            return Badge(symbol: "list.number", text: "\(q.position)\(eta)", tone: tone,
                         help: "Merge queue #\(q.position) · \(state)\(eta)")
        }
        guard let auto = autoMergeRequest else { return nil }
        // With a merge queue, "merge when ready" is the auto-merge request that enqueues the PR.
        return isMergeQueueEnabled
            ? Badge(symbol: "bolt.fill", text: "When ready", help: "Merge when ready")
            : Badge(symbol: "bolt.fill", text: "Auto-merge", help: "Auto-merge (\(auto.mergeMethod.lowercased()))")
    }

    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}
