import Foundation

public struct CheckSummary: Sendable, Equatable {
    public var failed = 0, pending = 0, passed = 0, skipped = 0
    public var total: Int { failed + pending + passed + skipped }
}

public struct Badge: Sendable, Hashable {
    /// Each state has one color: failing red, running orange, merging purple, passing green, waiting for review blue.
    /// Drafts and plain facts stay gray. Every colored state also has its own symbol or word, so color is never the only cue.
    public enum Tone: Sendable { case neutral, failing, running, merging, passing, waiting }
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
        // Merged PRs keep stale DIRTY, REVIEW_REQUIRED and FAILURE values, so merged wins over all of them.
        if mergedAt != nil { return Badge(symbol: "arrow.triangle.merge", text: "Merged", tone: .merging) }
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
        if reviewDecision == "REVIEW_REQUIRED" { return Badge(symbol: "eye.circle", text: "Waiting for review", tone: .waiting) }
        return Badge(symbol: "checkmark.circle.fill", text: s.total > 0 ? "Checks passed, no blockers" : "No blockers", tone: .passing)
    }

    /// Short facts for the secondary line. Passing checks are omitted; the details list them.
    public var facts: [Badge] {
        let stackFact = stack.flatMap { s in stackEntry.map { Badge(text: "Stack \($0.position)/\(s.size)") } }
        // Review, checks and conflicts are stale after a merge.
        if mergedAt != nil { return stackFact.map { [$0] } ?? [] }
        var out: [Badge] = []
        if isDraft { out.append(Badge(text: "Draft")) }
        switch reviewDecision {
        case "APPROVED": out.append(Badge(text: "Approved", tone: .passing))
        case "CHANGES_REQUESTED": out.append(Badge(text: "Changes requested", tone: .failing))
        case "REVIEW_REQUIRED": out.append(Badge(text: "Review required", tone: .waiting))
        default: break
        }
        let s = checkSummary
        if checksFailing { out.append(Badge(text: s.failed > 0 ? "\(s.failed) failed" : "Checks failed", tone: .failing)) }
        if s.pending > 0 { out.append(Badge(text: "\(s.pending) running", tone: .running)) }
        if let stackFact { out.append(stackFact) }
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
            default: .merging
            }
            return Badge(symbol: "list.number", text: "\(q.position)\(eta)", tone: tone,
                         help: "Merge queue #\(q.position) · \(state)\(eta)")
        }
        guard let auto = autoMergeRequest else { return nil }
        // With a merge queue, "merge when ready" is the auto-merge request that enqueues the PR.
        return isMergeQueueEnabled
            ? Badge(symbol: "bolt.fill", text: "When ready", tone: .merging, help: "Merge when ready")
            : Badge(symbol: "bolt.fill", text: "Auto-merge", tone: .merging, help: "Auto-merge (\(auto.mergeMethod.lowercased()))")
    }

    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}

extension Array where Element == PullRequest {
    /// One group per stack with 2+ listed members, else one group per PR. A group keeps its first member's slot
    /// and lists members by stack position, so the PR that merges first leads.
    public func groupedByStack() -> [[PullRequest]] {
        var groups: [[PullRequest]] = []
        var slot: [String: Int] = [:]
        for pr in self {
            let key = pr.stackEntry == nil ? pr.id : pr.stack?.id ?? pr.id
            if let i = slot[key] { groups[i].append(pr) } else { slot[key] = groups.count; groups.append([pr]) }
        }
        return groups.map { $0.sorted { ($0.stackEntry?.position ?? 0) < ($1.stackEntry?.position ?? 0) } }
    }

    /// Failing, then merging, then running, as `status` ranks them. `min` keeps the first of equals.
    public var mostUrgent: PullRequest? {
        func rank(_ pr: PullRequest) -> Int { [.failing: 0, .merging: 1, .running: 2][pr.status.tone] ?? 3 }
        return self.min { rank($0) < rank($1) }
    }
}
