import Foundation

/// Fields fetched on hover by `GitHubClient.fetchDetails` after each poll.
/// `isRequired` takes the PR id as an argument, so it cannot go in the shared search fragment.
public struct PRDetail: Decodable, Sendable, Hashable {
    public let changedFiles: Int
    public let commits: Count
    public let labels: Nodes<Name>
    public let latestOpinionatedReviews: Nodes<Review>
    public let reviewRequests: Nodes<Request>
    // shortcut: first 100 threads; past that `unresolvedThreadsCapped` marks the count as a minimum.
    public let reviewThreads: Nodes<Thread>
    public let viewerLatestReview: ViewerReview?
    public let timelineItems: Nodes<RequestEvent>
    public let statusCheckRollup: Rollup?

    public struct Count: Decodable, Sendable, Hashable { public let totalCount: Int }
    public struct Name: Decodable, Sendable, Hashable { public let name: String }
    public struct Thread: Decodable, Sendable, Hashable { public let isResolved: Bool }
    public struct ViewerReview: Decodable, Sendable, Hashable { public let submittedAt: Date? }

    public struct Review: Decodable, Sendable, Hashable {
        public let state: String
        public let submittedAt: Date?
        public let author: Login?
    }

    /// A User, Bot or Mannequin has a login; a Team has a combined slug such as "org/team".
    public struct Actor: Decodable, Sendable, Hashable {
        public let login: String?
        public let combinedSlug: String?
    }

    public struct Request: Decodable, Sendable, Hashable {
        public let asCodeOwner: Bool
        public let requestedReviewer: Actor?
    }

    public struct RequestEvent: Decodable, Sendable, Hashable {
        public let createdAt: Date
        public let actor: Login?
        public let requestedReviewer: Actor?
    }

    public struct Rollup: Decodable, Sendable, Hashable {
        public let contexts: Nodes<Required>
        public struct Required: Decodable, Sendable, Hashable {
            public let name: String
            public let isRequired: Bool
        }
    }

    public struct Reviewer: Sendable, Hashable {
        public enum State: Int, Sendable, Comparable {
            case changesRequested, approved, pendingUser, pendingTeam
            public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        }
        public let name: String
        public let state: State
        public var codeOwner = false
    }

    public var requiredChecks: Set<String> {
        Set(statusCheckRollup?.contexts.nodes.filter(\.isRequired).map(\.name) ?? [])
    }

    public var unresolvedThreads: Int { reviewThreads.nodes.filter { !$0.isResolved }.count }
    public var unresolvedThreadsCapped: Bool { (reviewThreads.totalCount ?? 0) > reviewThreads.nodes.count }
    /// Reviews past the first 20 that `reviewers` never saw.
    public var unfetchedReviews: Int { max((latestOpinionatedReviews.totalCount ?? 0) - latestOpinionatedReviews.nodes.count, 0) }

    /// Changes requested, approved, pending users, pending teams. A pending request replaces that login's older review.
    public var reviewers: [Reviewer] {
        let pending = reviewRequests.nodes.compactMap { request -> Reviewer? in
            if let login = request.requestedReviewer?.login {
                return Reviewer(name: login, state: .pendingUser, codeOwner: request.asCodeOwner)
            }
            if let team = request.requestedReviewer?.combinedSlug {
                return Reviewer(name: team, state: .pendingTeam, codeOwner: request.asCodeOwner)
            }
            return nil
        }
        let pendingNames = Set(pending.map(\.name))
        let reviewed = latestOpinionatedReviews.nodes.compactMap { review -> Reviewer? in
            guard let login = review.author?.login, !pendingNames.contains(login) else { return nil }
            switch review.state {
            case "CHANGES_REQUESTED": return Reviewer(name: login, state: .changesRequested)
            case "APPROVED": return Reviewer(name: login, state: .approved)
            default: return nil
            }
        }
        return (reviewed + pending).sorted { ($0.state, $0.name) < ($1.state, $1.name) }
    }

    /// The newest event for a request still pending: the viewer's own, else a pending team's.
    /// With two or more pending teams the timeline cannot tell which holds the viewer, so `team` and `by` stay nil.
    public func request(viewer: String) -> (by: String?, team: String?, at: Date)? {
        let pending = reviewRequests.nodes.compactMap(\.requestedReviewer)
        let events = timelineItems.nodes.sorted { $0.createdAt > $1.createdAt }
        if pending.contains(where: { $0.login == viewer }) {
            return events.first { $0.requestedReviewer?.login == viewer }.map { ($0.actor?.login, nil, $0.createdAt) }
        }
        let teams = Set(pending.compactMap(\.combinedSlug))
        guard let event = events.first(where: { $0.requestedReviewer?.combinedSlug.map(teams.contains) == true }) else { return nil }
        return teams.count == 1 ? (event.actor?.login, event.requestedReviewer?.combinedSlug, event.createdAt) : (nil, nil, event.createdAt)
    }

    /// True when the viewer reviewed before the latest request reached them.
    public func reRequested(viewer: String) -> Bool {
        guard let at = request(viewer: viewer)?.at, let reviewed = viewerLatestReview?.submittedAt else { return false }
        return reviewed < at
    }
}
