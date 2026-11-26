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

    public func fetch(first: Int = 50) async throws -> Sections {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": Self.query, "variables": ["n": first]])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw GitHubError.unauthorized }
        guard code == 200 else { throw GitHubError.http(code, String(decoding: data, as: UTF8.self)) }
        return try Self.decode(data)
    }

    public static func decode(_ data: Data) throws -> Sections {
        struct Envelope: Decodable {
            struct Message: Decodable { let message: String }
            let data: Sections?
            let errors: [Message]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)
        let messages = envelope.errors?.map(\.message).joined(separator: "; ")
        guard var sections = envelope.data else { throw GitHubError.graphQL(messages ?? "empty response") }
        sections.warning = messages
        return sections
    }

    // shortcut: first 50 PRs per section and 100 check contexts per PR; totals and the rollup state still cover all.
    static let query = """
    query($n: Int!) {
      viewer { login }
      created: search(query: "is:open is:pr author:@me archived:false sort:updated-desc", type: ISSUE, first: $n) { totalCount: issueCount nodes { ...pr } }
      assigned: search(query: "is:open is:pr assignee:@me -author:@me archived:false sort:updated-desc", type: ISSUE, first: $n) { totalCount: issueCount nodes { ...pr } }
      review: search(query: "is:open is:pr review-requested:@me archived:false sort:updated-desc", type: ISSUE, first: $n) { totalCount: issueCount nodes { ...pr } }
    }
    fragment pr on PullRequest {
      id number title url isDraft createdAt additions deletions
      author { login }
      repository { nameWithOwner }
      baseRefName headRefName reviewDecision mergeStateStatus isMergeQueueEnabled
      autoMergeRequest { mergeMethod enabledBy { login } }
      mergeQueueEntry { position state estimatedTimeToMerge enqueuedAt }
      stack { size entries(first: 50) { nodes { position pullRequest { number title state url } } } }
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
}
