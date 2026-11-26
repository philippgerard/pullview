import Foundation

/// GitHub enum values stay as raw strings so a new server-side value never breaks decoding.
public struct PullRequest: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let createdAt: Date
    public let additions: Int
    public let deletions: Int
    public let author: Login?
    public let repository: Repository
    public let baseRefName: String
    public let headRefName: String
    public let reviewDecision: String?
    public let mergeStateStatus: String?
    public let isMergeQueueEnabled: Bool
    public let autoMergeRequest: AutoMerge?
    public let mergeQueueEntry: QueueEntry?
    public let stack: Stack?
    public let stackEntry: StackEntry?
    public let statusCheckRollup: CheckRollup?

    public var checks: [Check] { statusCheckRollup?.contexts.nodes ?? [] }
}

public struct Nodes<T: Decodable & Sendable & Hashable>: Decodable, Sendable, Hashable {
    public let nodes: [T]
    /// Size of the full connection, which can exceed `nodes.count` when the page is capped.
    public let totalCount: Int?

    private enum Key: CodingKey { case nodes, totalCount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        // GitHub nulls single nodes the token cannot read (e.g. a SAML-protected org); drop them.
        nodes = try c.decode([T?].self, forKey: .nodes).compactMap { $0 }
        totalCount = try c.decodeIfPresent(Int.self, forKey: .totalCount)
    }
}

public struct Login: Decodable, Sendable, Hashable {
    public let login: String
}

public struct Repository: Decodable, Sendable, Hashable {
    public let nameWithOwner: String
    public var name: String { nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner }
}

public struct AutoMerge: Decodable, Sendable, Hashable {
    public let mergeMethod: String
    public let enabledBy: Login?
}

public struct QueueEntry: Decodable, Sendable, Hashable {
    public let position: Int
    public let state: String
    public let estimatedTimeToMerge: Int?
    public let enqueuedAt: Date
}

public struct Stack: Decodable, Sendable, Hashable {
    public let size: Int
    public let entries: Nodes<Entry>

    public struct Entry: Decodable, Sendable, Hashable {
        public let position: Int
        public let pullRequest: Member? // nil when the viewer cannot read that PR
    }

    public struct Member: Decodable, Sendable, Hashable {
        public let number: Int
        public let title: String
        public let state: String
        public let url: URL
    }
}

public struct StackEntry: Decodable, Sendable, Hashable {
    public let position: Int
}

public struct CheckRollup: Decodable, Sendable, Hashable {
    public let state: String
    public let contexts: Nodes<Check>
}

/// One CI signal: either a GitHub Actions/App check run or a legacy commit status.
public struct Check: Decodable, Sendable, Hashable {
    public enum Outcome: Int, Sendable, Comparable {
        case failed, pending, passed, skipped
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public let name: String
    public let url: URL?
    public let outcome: Outcome

    private enum Key: String, CodingKey {
        case __typename, name, status, conclusion, detailsUrl, context, state, targetUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if try c.decode(String.self, forKey: .__typename) == "CheckRun" {
            name = try c.decode(String.self, forKey: .name)
            url = try c.decodeIfPresent(String.self, forKey: .detailsUrl).flatMap(URL.init(string:))
            outcome = Self.outcome(status: try c.decode(String.self, forKey: .status),
                                   conclusion: try c.decodeIfPresent(String.self, forKey: .conclusion))
        } else {
            name = try c.decode(String.self, forKey: .context)
            url = try c.decodeIfPresent(String.self, forKey: .targetUrl).flatMap(URL.init(string:))
            outcome = Self.outcome(statusState: try c.decode(String.self, forKey: .state))
        }
    }

    static func outcome(status: String, conclusion: String?) -> Outcome {
        guard status == "COMPLETED" else { return .pending }
        switch conclusion {
        case "SUCCESS": return .passed
        case "NEUTRAL", "SKIPPED", "STALE": return .skipped
        default: return .failed // FAILURE, TIMED_OUT, CANCELLED, ACTION_REQUIRED, STARTUP_FAILURE
        }
    }

    static func outcome(statusState: String) -> Outcome {
        switch statusState {
        case "SUCCESS": return .passed
        case "PENDING", "EXPECTED": return .pending
        default: return .failed // FAILURE, ERROR
        }
    }
}

public struct Sections: Decodable, Sendable, Hashable {
    public let created: [PullRequest]
    public let assigned: [PullRequest]
    public let review: [PullRequest]
    /// Search match counts; above the list length when a section is capped.
    public let createdTotal: Int, assignedTotal: Int, reviewTotal: Int
    /// GraphQL errors that came back next to usable data, e.g. one org blocking the token.
    public internal(set) var warning: String?
    /// The account the token belongs to.
    public let viewer: Login?

    private enum Key: CodingKey { case created, assigned, review, viewer }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        viewer = try c.decodeIfPresent(Login.self, forKey: .viewer)
        let created = try c.decode(Nodes<PullRequest>.self, forKey: .created)
        let assigned = try c.decode(Nodes<PullRequest>.self, forKey: .assigned)
        let review = try c.decode(Nodes<PullRequest>.self, forKey: .review)
        (self.created, self.assigned, self.review) = (created.nodes, assigned.nodes, review.nodes)
        createdTotal = created.totalCount ?? created.nodes.count
        assignedTotal = assigned.totalCount ?? assigned.nodes.count
        reviewTotal = review.totalCount ?? review.nodes.count
    }

    public var all: [PullRequest] { created + assigned + review }
}
