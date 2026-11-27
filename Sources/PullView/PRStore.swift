import Foundation
import Observation
import PullViewCore

enum TokenMode: String {
    static let key = "tokenMode"
    case cli, personal
}

@MainActor @Observable
final class PRStore {
    static let intervalKey = "refreshInterval"
    static let mergedDaysKey = "recentlyMergedDays"

    private(set) var sections: Sections?
    private(set) var error: String?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    /// Hover details per PR, preloaded after a poll and refetched once they are 5 minutes old.
    private(set) var details: [PullRequest.ID: (detail: PRDetail, fetchedAt: Date)] = [:]
    private(set) var failed: Set<PullRequest.ID> = []
    private var inFlight: Set<PullRequest.ID> = []
    private var token: String?
    /// Bumped on every credential change; a fetch started under an older value is discarded.
    private var generation = 0
    private var refreshAgain = false
    private var loop: Task<Void, Never>?

    init() { start() }

    /// Fixed data and no polling, for the README screenshots.
    init(sections: Sections, details: [PullRequest.ID: PRDetail]) {
        self.sections = sections
        self.details = details.mapValues { ($0, .now) }
        lastUpdated = .now
    }

    var interval: Int {
        let value = UserDefaults.standard.integer(forKey: Self.intervalKey)
        return value == 0 ? 60 : max(value, 15)
    }

    var mergedDays: Int {
        let value = UserDefaults.standard.integer(forKey: Self.mergedDaysKey)
        return (1...7).contains(value) ? value : 3
    }

    /// Distinct PRs across all sections, for the menu bar count.
    var openCount: Int { Set(sections?.all.map(\.id) ?? []).count }
    var hasFailingOwnPR: Bool { sections?.created.contains(where: \.checksFailing) ?? false }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // An unstructured task keeps an in-flight fetch alive when start() replaces this loop.
                await Task { await self?.refresh() }.value
                try? await Task.sleep(for: .seconds(self?.interval ?? 60))
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let started = generation
        do {
            let token = try await currentToken()
            let result = try await GitHubClient(token: token).fetch(mergedDays: mergedDays)
            if started == generation {
                self.token = token
                sections = result
                lastUpdated = .now
                let listed = Set((result.all + result.merged).map(\.id))
                details = details.filter { listed.contains($0.key) }
                failed.formIntersection(listed)
                error = nil
                preloadDetails(ids: listed)
            }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch let error where started == generation {
            if error as? GitHubError == .unauthorized { token = nil } // re-read from gh after `gh auth refresh`
            self.error = error.localizedDescription
        } catch {}
        isLoading = false
        if refreshAgain {
            refreshAgain = false
            await refresh()
        }
    }

    /// Drops the cached token and data after a settings change and fetches with the new credentials.
    func credentialsChanged() {
        generation += 1
        token = nil
        sections = nil
        error = nil
        details = [:]
        failed = []
        refetch()
    }

    /// Fetches now, or once more after the fetch in flight, which used the old settings.
    func refetch() {
        if isLoading { refreshAgain = true } else { Task { await refresh() } }
    }

    /// Fetches details for listed PRs that have none or are 5 minutes old, 25 PRs per request, so hovering never waits.
    /// A failure keeps the old entry and the next poll retries.
    private func preloadDetails(ids: Set<PullRequest.ID>) {
        guard let token else { return }
        let due = ids.filter { !inFlight.contains($0) && (details[$0]?.fetchedAt.timeIntervalSinceNow ?? -.infinity) < -300 }
        guard !due.isEmpty else { return }
        inFlight.formUnion(due)
        let started = generation
        for chunk in stride(from: 0, to: due.count, by: 25).map({ Array(Array(due)[$0..<min($0 + 25, due.count)]) }) {
            Task {
                defer { inFlight.subtract(chunk) }
                do {
                    let fetched = try await GitHubClient(token: token).fetchDetails(ids: chunk)
                    guard started == generation else { return }
                    for id in chunk {
                        if let detail = fetched[id] { details[id] = (detail, .now); failed.remove(id) } else { failed.insert(id) }
                    }
                } catch {
                    if started == generation { failed.formUnion(chunk) }
                }
            }
        }
    }

    private func currentToken() async throws -> String {
        if let token { return token }
        let mode = TokenMode(rawValue: UserDefaults.standard.string(forKey: TokenMode.key) ?? "") ?? .cli
        let resolved: String
        if mode == .personal {
            guard let stored = Keychain.read(), !stored.isEmpty else { throw GitHubError.noToken }
            resolved = stored
        } else {
            resolved = try await Task.detached { try TokenSource.resolve() }.value
        }
        return resolved
    }
}
