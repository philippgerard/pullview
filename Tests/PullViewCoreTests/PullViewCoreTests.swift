import Foundation
import Testing
@testable import PullViewCore

/// A minimal PR node; `extra` is ",key:value,..." overriding the defaults.
private func pr(_ extra: String) -> String {
    let json = """
    {"id":"PR_1","number":12,"title":"feat: x","url":"https://github.com/o/r/pull/12","isDraft":false,
     "createdAt":"2026-11-26T10:00:00Z","additions":3,"deletions":1,"author":{"login":"me"},
     "repository":{"nameWithOwner":"o/r"},"baseRefName":"main","headRefName":"x",
     "reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","isMergeQueueEnabled":true,
     "autoMergeRequest":null,"mergeQueueEntry":null,"stack":null,"stackEntry":null,
     "statusCheckRollup":null}
    """
    let base = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    let overrides = try! JSONSerialization.jsonObject(with: Data("{\(extra.dropFirst())}".utf8)) as! [String: Any]
    let merged = base.merging(overrides) { $1 }
    return String(decoding: try! JSONSerialization.data(withJSONObject: merged), as: UTF8.self)
}

private func decode(created: [String], review: [String] = []) throws -> Sections {
    let json = """
    {"data":{"created":{"nodes":[\(created.joined(separator: ","))]},
             "assigned":{"nodes":[]},
             "review":{"nodes":[\(review.joined(separator: ","))]}}}
    """
    return try GitHubClient.decode(Data(json.utf8))
}

@Test func decodesQueueStackAndChecks() throws {
    let sections = try decode(created: [pr("""
    ,"mergeQueueEntry":{"position":3,"state":"AWAITING_CHECKS","estimatedTimeToMerge":757,"enqueuedAt":"2026-11-26T10:42:07Z"},
    "stack":{"size":6,"entries":{"nodes":[{"position":5,"pullRequest":{"number":12,"title":"feat: x","state":"OPEN","url":"https://github.com/o/r/pull/12"}}]}},
    "stackEntry":{"position":5},
    "statusCheckRollup":{"state":"FAILURE","contexts":{"nodes":[
      {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://ci/1"},
      {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"TIMED_OUT","detailsUrl":"https://ci/2"},
      {"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":null,"detailsUrl":""},
      {"__typename":"CheckRun","name":"docs","status":"COMPLETED","conclusion":"SKIPPED","detailsUrl":null},
      {"__typename":"StatusContext","context":"legacy/ci","state":"ERROR","targetUrl":null}
    ]}}
    """)])

    let p = try #require(sections.created.first)
    #expect(p.checkSummary == CheckSummary(failed: 2, pending: 1, passed: 1, skipped: 1))
    #expect(p.attentionChecks.map(\.name) == ["legacy/ci", "test", "build"])
    #expect(p.checks.first { $0.name == "build" }?.url == nil)
    #expect(p.facts.map(\.text) == ["Approved", "2 failed", "1 running", "Stack 5/6"])
    #expect(p.merge?.text == "3 · ~12m")
    #expect(p.merge?.help == "Merge queue #3 · awaiting checks · ~12m")
    #expect(p.status.tone == .failing)
    #expect(p.status.text == "Failed: legacy/ci, test")
}

@Test func autoMergeConflictsAndDraftBadges() throws {
    let sections = try decode(created: [], review: [pr("""
    ,"isDraft":true,"reviewDecision":"CHANGES_REQUESTED","mergeStateStatus":"DIRTY",
    "autoMergeRequest":{"mergeMethod":"SQUASH","enabledBy":{"login":"me"}}
    """), pr("""
    ,"id":"PR_2","isMergeQueueEnabled":false,"reviewDecision":null,"mergeStateStatus":"BEHIND",
    "autoMergeRequest":{"mergeMethod":"SQUASH","enabledBy":null}
    """)])

    let draft = sections.review[0], behind = sections.review[1]
    #expect(draft.facts.map(\.text) == ["Draft", "Changes requested", "Conflicts"])
    #expect(draft.merge?.help == "Merge when ready")
    #expect(draft.status.text == "Conflicts\nChanges requested")
    #expect(behind.facts.map(\.text) == ["Behind base"])
    #expect(behind.merge?.help == "Auto-merge (squash)")
    #expect(behind.status.tone == .neutral)
}

@Test func statusPriority() throws {
    let sections = try decode(created: [pr("""
    ,"mergeQueueEntry":{"position":1,"state":"MERGEABLE","estimatedTimeToMerge":null,"enqueuedAt":"2026-11-26T10:42:07Z"},
    "statusCheckRollup":{"state":"PENDING","contexts":{"nodes":[
      {"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":null,"detailsUrl":null}]}}
    """), pr("""
    ,"id":"PR_2","statusCheckRollup":{"state":"PENDING","contexts":{"nodes":[
      {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":null},
      {"__typename":"CheckRun","name":"build","status":"QUEUED","conclusion":null,"detailsUrl":null}]}}
    """), pr(#","id":"PR_3","isDraft":true,"reviewDecision":"REVIEW_REQUIRED""#)])

    #expect(sections.created[0].status.tone == .merging)
    #expect(sections.created[0].merge?.text == "1")
    #expect(sections.created[1].status.tone == .running)
    #expect(sections.created[1].status.text == "1 of 2 checks done")
    #expect(sections.created[2].status.text == "Draft")
}

@Test func graphQLErrorWithoutDataThrows() {
    #expect(throws: GitHubError.graphQL("Bad credentials; Other")) {
        try GitHubClient.decode(Data(#"{"data":null,"errors":[{"message":"Bad credentials"},{"message":"Other"}]}"#.utf8))
    }
}

@Test func durationFormatting() {
    #expect(PullRequest.duration(42) == "42s")
    #expect(PullRequest.duration(757) == "12m")
    #expect(PullRequest.duration(3_900) == "1h 5m")
}

/// Hits the real API with your gh token: `PULLVIEW_LIVE=1 swift test --filter live`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PULLVIEW_LIVE"] != nil))
func liveFetch() async throws {
    let sections = try await GitHubClient(token: TokenSource.resolve()).fetch()
    print("viewer: \(sections.viewer?.login ?? "nil")")
    #expect(sections.viewer != nil)
    for p in sections.all {
        print("#\(p.number) \(p.repository.name): \(p.status.text) | \(p.facts.map(\.text).joined(separator: " · ")) | \(p.merge?.help ?? "")")
    }
}

@Test func nullNodesAndPartialErrorsKeepTheRest() throws {
    let json = """
    {"data":{"created":{"totalCount":60,"nodes":[null,\(pr(""))]},
             "assigned":{"nodes":[]},"review":{"nodes":[]}},
     "errors":[{"message":"Resource protected by organization SAML enforcement."}]}
    """
    let sections = try GitHubClient.decode(Data(json.utf8))
    #expect(sections.created.count == 1)
    #expect(sections.createdTotal == 60)
    #expect(sections.assignedTotal == 0)
    #expect(sections.warning == "Resource protected by organization SAML enforcement.")
}

@Test func rollupFailureBeyondFetchedPageTurnsStatusRed() throws {
    let sections = try decode(created: [pr("""
    ,"statusCheckRollup":{"state":"FAILURE","contexts":{"totalCount":130,"nodes":[
      {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":null},
      null
    ]}}
    """)])
    let p = try #require(sections.created.first)
    #expect(p.checksFailing)
    #expect(p.unfetchedCheckCount == 129)
    #expect(p.status.tone == .failing)
    #expect(p.status.text == "Checks failed")
    #expect(p.facts.map(\.text) == ["Approved", "Checks failed"])
}
