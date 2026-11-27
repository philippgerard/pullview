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

private func decode(created: [String], review: [String] = [], merged: [String] = [], mergedTotal: Int? = nil) throws -> Sections {
    let json = """
    {"data":{"created":{"nodes":[\(created.joined(separator: ","))]},
             "assigned":{"nodes":[]},
             "review":{"nodes":[\(review.joined(separator: ","))]},
             "merged":{\(mergedTotal.map { #""totalCount":\#($0),"# } ?? "")"nodes":[\(merged.joined(separator: ","))]}}}
    """
    return try GitHubClient.decode(Data(json.utf8))
}

@Test func decodesQueueStackAndChecks() throws {
    let sections = try decode(created: [pr("""
    ,"mergeQueueEntry":{"position":3,"state":"AWAITING_CHECKS","estimatedTimeToMerge":757,"enqueuedAt":"2026-11-26T10:42:07Z"},
    "stack":{"id":"S_1","size":6,"entries":{"nodes":[{"position":5,"pullRequest":{"number":12,"title":"feat: x","state":"OPEN","url":"https://github.com/o/r/pull/12"}}]}},
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
    #expect(p.stack?.id == "S_1")
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
    #expect(behind.status.tone == .passing)
    #expect(behind.merge?.tone == .merging)
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
    #expect(sections.created[2].status.tone == .neutral)
    #expect(sections.created[2].facts.first { $0.text == "Review required" }?.tone == .waiting)
}

@Test func reviewStatesHaveTheirOwnColor() throws {
    let sections = try decode(created: [pr(#","reviewDecision":"REVIEW_REQUIRED""#), pr(#","id":"PR_2""#)])
    #expect(sections.created[0].status.tone == .waiting)
    #expect(sections.created[0].status.text == "Waiting for review")
    #expect(sections.created[1].status.tone == .passing)
    #expect(sections.created[1].facts.first?.tone == .passing) // "Approved"
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
    print("merged: \(sections.merged.count) of \(sections.mergedTotal)")
    for p in sections.merged {
        print("#\(p.number) \(p.repository.name): \(p.status.text) | \(p.facts.map(\.text).joined(separator: " · "))")
        #expect(p.mergedAt != nil)
    }
    if let first = sections.all.first {
        let all = try await GitHubClient(token: TokenSource.resolve()).fetchDetails(ids: sections.all.map(\.id))
        #expect(all.count == Set(sections.all.map(\.id)).count)
        let d = try #require(all[first.id])
        print("detail #\(first.number): \(d.changedFiles) files, \(d.commits.totalCount) commits, \(d.reviewers.count) reviewers, \(d.unresolvedThreads) unresolved, \(d.requiredChecks.count) required")
    }
}

@Test func nullNodesAndPartialErrorsKeepTheRest() throws {
    let json = """
    {"data":{"created":{"totalCount":60,"nodes":[null,\(pr(""))]},
             "assigned":{"nodes":[]},"review":{"nodes":[]},"merged":{"nodes":[]}},
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

/// A minimal detail node wrapped in a response; `extra` is ",key:value,..." overriding the defaults.
private func detail(_ extra: String) throws -> PRDetail {
    let json = """
    {"changedFiles":24,"commits":{"totalCount":4},"labels":{"totalCount":0,"nodes":[]},
     "latestOpinionatedReviews":{"nodes":[]},"reviewRequests":{"totalCount":0,"nodes":[]},
     "reviewThreads":{"totalCount":0,"nodes":[]},"viewerLatestReview":null,
     "timelineItems":{"nodes":[]},"statusCheckRollup":null}
    """
    let base = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    let overrides = try JSONSerialization.jsonObject(with: Data("{\(extra.dropFirst())}".utf8)) as! [String: Any]
    let node = base.merging(overrides) { $1 }
    return try #require(GitHubClient.decodeDetails(JSONSerialization.data(withJSONObject: ["data": ["p0": node]]), ids: ["x"])["x"])
}

@Test func decodesDetail() throws {
    let d = try detail("""
    ,"labels":{"totalCount":2,"nodes":[{"name":"bug"},{"name":"ci"}]},
    "reviewThreads":{"totalCount":2,"nodes":[{"isResolved":true},{"isResolved":false}]},
    "statusCheckRollup":{"contexts":{"nodes":[
      {"__typename":"CheckRun","name":"build","isRequired":true},
      {"__typename":"CheckRun","name":"lint","isRequired":false},
      {"__typename":"StatusContext","name":"legacy/ci","isRequired":false}]}}
    """)
    #expect(d.changedFiles == 24)
    #expect(d.commits.totalCount == 4)
    #expect(d.labels.nodes.map(\.name) == ["bug", "ci"])
    #expect(d.requiredChecks == ["build"])
    #expect(d.unresolvedThreads == 1)
}

@Test func reviewerOrderAndRequestOverride() throws {
    let d = try detail("""
    ,"latestOpinionatedReviews":{"nodes":[
      {"state":"APPROVED","submittedAt":"2026-11-25T10:00:00Z","author":{"login":"amy"}},
      {"state":"CHANGES_REQUESTED","submittedAt":"2026-11-25T11:00:00Z","author":{"login":"zed"}},
      {"state":"APPROVED","submittedAt":"2026-11-25T12:00:00Z","author":{"login":"bob"}}]},
    "reviewRequests":{"totalCount":3,"nodes":[
      {"asCodeOwner":true,"requestedReviewer":{"combinedSlug":"o/core"}},
      {"asCodeOwner":false,"requestedReviewer":{"login":"bob"}},
      {"asCodeOwner":false,"requestedReviewer":{"login":"cat"}}]}
    """)
    #expect(d.reviewers.map(\.name) == ["zed", "amy", "bob", "cat", "o/core"])
    #expect(d.reviewers.map(\.state) == [.changesRequested, .approved, .pendingUser, .pendingUser, .pendingTeam])
    #expect(d.reviewers.filter { $0.name == "bob" }.count == 1)
    #expect(d.reviewers.last?.codeOwner == true)
}

@Test func requestedByPrefersViewerThenTeam() throws {
    let events = """
    ,"timelineItems":{"nodes":[
      {"createdAt":"2026-11-26T07:00:00Z","actor":{"login":"dan"},"requestedReviewer":{"combinedSlug":"o/frontend"}},
      {"createdAt":"2026-11-26T08:00:00Z","actor":{"login":"amy"},"requestedReviewer":{"login":"me"}},
      {"createdAt":"2026-11-26T09:00:00Z","actor":{"login":"bob"},"requestedReviewer":{"combinedSlug":"o/core"}},
      {"createdAt":"2026-11-26T10:00:00Z","actor":{"login":"cat"},"requestedReviewer":{"login":"other"}}]}
    """
    func pending(_ reviewers: String...) -> String {
        #","reviewRequests":{"nodes":["# + reviewers.map { #"{"asCodeOwner":false,"requestedReviewer":\#($0)}"# }.joined(separator: ",") + "]}"
    }
    let me = #"{"login":"me"}"#, core = #"{"combinedSlug":"o/core"}"#, frontend = #"{"combinedSlug":"o/frontend"}"#

    let d = try detail(events + pending(me, core))
    let own = try #require(d.request(viewer: "me"))
    #expect(own.by == "amy")
    #expect(own.team == nil)
    #expect(!d.reRequested(viewer: "me")) // no review

    // Only pending teams count: o/core is newer but no longer requested.
    let team = try #require(try detail(events + pending(frontend)).request(viewer: "me"))
    #expect(team.by == "dan")
    #expect(team.team == "o/frontend")
    // Two pending teams: the newest event's time, no name.
    let either = try #require(try detail(events + pending(frontend, core)).request(viewer: "me"))
    #expect(either.team == nil && either.by == nil)
    #expect(either.at == ISO8601DateFormatter().date(from: "2026-11-26T09:00:00Z"))
    // A direct request that was removed is ignored.
    #expect(try detail(events).request(viewer: "me") == nil)

    let earlier = try detail(events + pending(me) + #","viewerLatestReview":{"submittedAt":"2026-11-26T07:00:00Z"}"#)
    #expect(earlier.reRequested(viewer: "me"))
    let later = try detail(events + pending(me) + #","viewerLatestReview":{"submittedAt":"2026-11-26T08:30:00Z"}"#)
    #expect(!later.reRequested(viewer: "me"))
    #expect(try detail("").request(viewer: "me") == nil)
}

@Test func detailCapsAreFlagged() throws {
    let d = try detail("""
    ,"reviewThreads":{"totalCount":140,"nodes":[{"isResolved":false}]},
    "latestOpinionatedReviews":{"totalCount":23,"nodes":[{"state":"APPROVED","submittedAt":null,"author":{"login":"amy"}}]}
    """)
    #expect(d.unresolvedThreadsCapped)
    #expect(d.unfetchedReviews == 22)
    #expect(try !detail("").unresolvedThreadsCapped)
}

@Test func detailNullNodeAndMissingPR() throws {
    let d = try detail("""
    ,"reviewRequests":{"totalCount":2,"nodes":[
      {"asCodeOwner":false,"requestedReviewer":null},
      {"asCodeOwner":false,"requestedReviewer":{"login":"cat"}}]}
    """)
    #expect(d.reviewers.map(\.name) == ["cat"])
    // One unresolvable PR drops out; the others in the same request still decode.
    let partial = try GitHubClient.decodeDetails(Data(#"{"data":{"p0":null,"p1":null},"errors":[{"message":"Could not resolve to a node with the global id of 'x'"}]}"#.utf8), ids: ["x", "y"])
    #expect(partial.isEmpty)
    #expect(throws: GitHubError.graphQL("Bad credentials")) {
        try GitHubClient.decodeDetails(Data(#"{"data":null,"errors":[{"message":"Bad credentials"}]}"#.utf8), ids: ["x"])
    }
    #expect(GitHubClient.detailsQuery(count: 2).contains("p1: node(id: $id1)"))
    #expect(GitHubClient.detailsQuery(count: 2).contains("isRequired(pullRequestId: $id1)"))
}

@Test func groupsListedStackMembers() throws {
    func member(_ id: String, stack: String?, position: Int?) -> String {
        let s = stack.map { #"{"id":"\#($0)","size":4,"entries":{"nodes":[]}}"# } ?? "null"
        return pr(#","id":"\#(id)","stack":\#(s),"stackEntry":\#(position.map { #"{"position":\#($0)}"# } ?? "null")"#)
    }
    let sections = try decode(created: [
        member("A", stack: "S", position: 2), member("B", stack: nil, position: nil), member("C", stack: "S", position: 1),
        member("D", stack: "T", position: 1), member("E", stack: "S", position: nil),
    ])
    #expect(sections.created.groupedByStack().map { $0.map(\.id) } == [["C", "A"], ["B"], ["D"], ["E"]])
}

@Test func mostUrgentPicksFailingThenMergingThenRunning() throws {
    let sections = try decode(created: [
        pr(#","id":"passed""#),
        pr(#","id":"running","statusCheckRollup":{"state":"PENDING","contexts":{"nodes":[]}}"#),
        pr(#","id":"merging","mergeQueueEntry":{"position":1,"state":"MERGEABLE","estimatedTimeToMerge":null,"enqueuedAt":"2026-11-26T10:42:07Z"}"#),
        pr(#","id":"failing","statusCheckRollup":{"state":"FAILURE","contexts":{"nodes":[]}}"#),
    ])
    let all = sections.created
    #expect(all.mostUrgent?.id == "failing")
    #expect(Array(all.dropLast()).mostUrgent?.id == "merging")
    #expect([all[0], all[0]].mostUrgent?.id == "passed")
    #expect([PullRequest]().mostUrgent == nil)
}

@Test func mergedSearchWindow() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-11-26T15:00:00Z"))
    let query = GitHubClient.mergedSearch(days: 3, now: now)
    #expect(query.hasPrefix("is:pr is:merged author:@me"))
    #expect(query.contains("merged:>=2026-11-23T15:00:00Z"))
    #expect(GitHubClient.query.contains("merged: search(query: $merged"))
}

@Test func mergedPRsIgnoreStaleState() throws {
    let sections = try decode(created: [], merged: [pr("""
    ,"mergedAt":"2026-11-26T12:00:00Z","mergedBy":{"login":"me"},
    "reviewDecision":"REVIEW_REQUIRED","mergeStateStatus":"DIRTY",
    "stack":{"id":"S","size":2,"entries":{"nodes":[]}},"stackEntry":{"position":2},
    "statusCheckRollup":{"state":"FAILURE","contexts":{"nodes":[
      {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":null}]}}
    """)])
    let p = try #require(sections.merged.first)
    #expect(p.mergedBy?.login == "me")
    #expect(p.status.symbol == "arrow.triangle.merge")
    #expect(p.status.tone == .merging)
    #expect(p.status.text == "Merged")
    #expect(p.facts.map(\.text) == ["Stack 2/2"])
    #expect(p.merge == nil)
    // Open PRs decode without the merge fields.
    #expect(try decode(created: [pr("")]).created[0].mergedAt == nil)
}

@Test func mergedSortsNewestFirstAndGroups() throws {
    func member(_ id: String, position: Int) -> String {
        pr(#","id":"\#(id)","mergedAt":"2026-11-26T12:00:00Z","stack":{"id":"S","size":2,"entries":{"nodes":[]}},"stackEntry":{"position":\#(position)}"#)
    }
    let older = pr(#","id":"B","mergedAt":"2026-11-25T09:00:00Z""#)
    let sections = try decode(created: [pr(#","id":"open""#)],
                              merged: [older, member("S2", position: 2), member("S1", position: 1)], mergedTotal: 7)
    #expect(sections.merged.groupedByStack().map { $0.map(\.id) } == [["S1", "S2"], ["B"]])
    #expect(sections.mergedTotal == 7)
    #expect(sections.all.map(\.id) == ["open"])
}
