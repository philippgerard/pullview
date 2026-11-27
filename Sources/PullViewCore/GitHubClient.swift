import Foundation

public enum GitHubError: LocalizedError, Equatable {
    case noToken, unauthorized, http(Int, String), graphQL(String)

    public var errorDescription: String? {
        switch self {
        case .noToken: "No GitHub token. Run `gh auth login` or add a token in Settings."
        case .unauthorized: "GitHub rejected the token (401)."
        case let .http(code, body): "GitHub HTTP \(code): \(body.prefix(200))"
        case let .graphQL(message): "GitHub: \(message)"
        }
    }
}

public enum TokenSource {
    /// GUI apps get no shell PATH, so the usual gh install locations are probed directly.
    public static func resolve() throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let token = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"], !token.isEmpty { return token }
        let home = NSHomeDirectory(), user = NSUserName()
        let candidates = [
            "/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh",
            "/etc/profiles/per-user/\(user)/bin/gh", "\(home)/.nix-profile/bin/gh", "/run/current-system/sw/bin/gh",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0, !token.isEmpty { return token }
        }
        throw GitHubError.noToken
    }
}

public struct GitHubClient: Sendable {
    public let token: String

    public init(token: String) { self.token = token }

    public func fetch(first: Int = 50, mergedDays: Int = 3) async throws -> Sections {
        try Self.decode(await post(query: Self.query,
                                   variables: ["n": first, "merged": Self.mergedSearch(days: mergedDays, now: .now)]))
    }

    /// Rolling window: "Last day" is the last 24 hours. Search takes a full timestamp after merged:>=.
    static func mergedSearch(days: Int, now: Date) -> String {
        "is:pr is:merged author:@me archived:false merged:>=\(now.addingTimeInterval(-Double(days) * 86_400).ISO8601Format()) sort:updated-desc"
    }

    /// Hover details for many PRs in one request, keyed by PR id. A PR that fails to resolve is left out.
    public func fetchDetails(ids: [String]) async throws -> [String: PRDetail] {
        guard !ids.isEmpty else { return [:] }
        let variables = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ("id\($0.offset)", $0.element) })
        return try Self.decodeDetails(await post(query: Self.detailsQuery(count: ids.count), variables: variables), ids: ids)
    }

    private func post(query: String, variables: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw GitHubError.unauthorized }
        guard code == 200 else { throw GitHubError.http(code, String(decoding: data, as: UTF8.self)) }
        return data
    }

    private struct Envelope<T: Decodable>: Decodable {
        struct Message: Decodable { let message: String }
        let data: T?
        let errors: [Message]?
        var messages: String? { errors?.map(\.message).joined(separator: "; ") }

        static func decode(_ data: Data) throws -> Self {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Self.self, from: data)
        }
    }

    public static func decode(_ data: Data) throws -> Sections {
        let envelope = try Envelope<Sections>.decode(data)
        guard var sections = envelope.data else { throw GitHubError.graphQL(envelope.messages ?? "empty response") }
        sections.warning = envelope.messages
        return sections
    }

    public static func decodeDetails(_ data: Data, ids: [String]) throws -> [String: PRDetail] {
        let envelope = try Envelope<[String: PRDetail?]>.decode(data)
        guard let nodes = envelope.data else { throw GitHubError.graphQL(envelope.messages ?? "empty response") }
        var details: [String: PRDetail] = [:]
        for (i, id) in ids.enumerated() { details[id] = nodes["p\(i)"] ?? nil }
        return details
    }

    /// One aliased `node` per PR, each with its own id variable, because `isRequired` needs that PR's id.
    static func detailsQuery(count: Int) -> String {
        let variables = (0..<count).map { "$id\($0): ID!" }.joined(separator: ", ")
        let nodes = (0..<count).map {
            "p\($0): node(id: $id\($0)) { ... on PullRequest {\(detailFields.replacingOccurrences(of: "$id", with: "$id\($0)"))} }"
        }
        return "query(\(variables)) {\n\(nodes.joined(separator: "\n"))\n}"
    }

    // shortcut: first 50 PRs per section, first 50 merged PRs in the window, and 100 check contexts per PR;
    // totals and the rollup state still cover all.
    static let query = """
    query($n: Int!, $merged: String!) {
      viewer { login }
      created: search(query: "is:open is:pr author:@me archived:false sort:updated-desc", type: ISSUE, first: $n) { totalCount: issueCount nodes { ...pr } }
      assigned: search(query: "is:open is:pr assignee:@me -author:@me archived:false sort:updated-desc", type: ISSUE, first: $n) { totalCount: issueCount nodes { ...pr } }
      review: search(query: "is:open is:pr review-requested:@me archived:false sort:updated-desc", type: ISSUE, first: $n) { totalCount: issueCount nodes { ...pr } }
      merged: search(query: $merged, type: ISSUE, first: $n) { totalCount: issueCount nodes { ...pr } }
    }
    fragment pr on PullRequest {
      id number title url isDraft createdAt mergedAt additions deletions
      author { login }
      mergedBy { login }
      repository { nameWithOwner }
      baseRefName headRefName reviewDecision mergeStateStatus isMergeQueueEnabled
      autoMergeRequest { mergeMethod enabledBy { login } }
      mergeQueueEntry { position state estimatedTimeToMerge enqueuedAt }
      stack { id size entries(first: 50) { nodes { position pullRequest { number title state url } } } }
      stackEntry { position }
      statusCheckRollup {
        state
        contexts(first: 100) { totalCount nodes {
          __typename
          ... on CheckRun { name status conclusion detailsUrl }
          ... on StatusContext { context state targetUrl }
        } }
      }
    }
    """

    // shortcut: 10 labels, 20 reviews and requests, 100 threads, the last 100 request events.
    static let detailFields = """
      changedFiles
      commits { totalCount }
      labels(first: 10) { totalCount nodes { name } }
      latestOpinionatedReviews(first: 20, writersOnly: true) { totalCount nodes { state submittedAt author { login } } }
      reviewRequests(first: 20) { totalCount nodes { asCodeOwner requestedReviewer {
        ... on User { login } ... on Bot { login } ... on Mannequin { login } ... on Team { combinedSlug } } } }
      reviewThreads(first: 100) { totalCount nodes { isResolved } }
      viewerLatestReview { submittedAt }
      timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 100) { nodes { ... on ReviewRequestedEvent {
        createdAt actor { login } requestedReviewer { ... on User { login } ... on Team { combinedSlug } } } } }
      statusCheckRollup { contexts(first: 100) { nodes { __typename
        ... on CheckRun { name isRequired(pullRequestId: $id) }
        ... on StatusContext { name: context isRequired(pullRequestId: $id) } } } }
    """
}
