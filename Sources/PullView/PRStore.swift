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

    private(set) var sections: Sections?
    private(set) var error: String?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private var token: String?
    /// Bumped on every credential change; a fetch started under an older value is discarded.
    private var generation = 0
    private var refreshAgain = false
    private var loop: Task<Void, Never>?

    init() { start() }

    var interval: Int {
        let value = UserDefaults.standard.integer(forKey: Self.intervalKey)
        return value == 0 ? 60 : max(value, 15)
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
            let result = try await GitHubClient(token: token).fetch()
            if started == generation {
                self.token = token
                sections = result
                lastUpdated = .now
                error = nil
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
        if isLoading { refreshAgain = true } else { Task { await refresh() } }
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
