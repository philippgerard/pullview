import PullViewCore
import SwiftUI

/// Two lines per PR: a fixed status glyph, the title with the merge slot, then facts with the age.
/// With `members`, the row stands for a stack led by `pr` and its popover lists the members.
struct PRRow: View {
    let pr: PullRequest
    var members: [PullRequest] = []
    let key: String
    let store: PRStore
    let hover: DetailHover
    var showRepo = true
    var showAuthor = true
    var showRequest = false
    /// False inside a stack list, whose header names the stack and whose rows run in stack order.
    var showStack = true
    @State private var hovering = false
    @FocusState private var chevronFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        let isOpen = hover.openKey == key
        let isStack = !members.isEmpty
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // A stack row names the member its glyph describes, since the title is the first member's.
            StatusGlyph(pr: members.mostUrgent ?? pr, number: isStack ? (members.mostUrgent ?? pr).number : nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pr.title)
                        .lineLimit(1)
                        .help(pr.title)
                        .accessibilityLabel(isStack ? Text(verbatim: stackLabel) : Text(verbatim: pr.title))
                        .accessibilityAddTraits(isStack ? .isButton : .isLink)
                        .accessibilityAction { if isStack { openDetails() } else { openURL(pr.url) } }
                        .accessibilityAction(named: isStack ? "Show Pull Requests" : "Show Details") { openDetails() }
                    Spacer(minLength: 0)
                    if let merge = pr.merge {
                        Label(merge.text, systemImage: merge.symbol ?? "list.number")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(merge.tone.style)
                            .help(merge.help ?? merge.text)
                            .accessibilityLabel(merge.help ?? merge.text)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    secondaryLine.lineLimit(1)
                    Spacer(minLength: 0)
                    // A merged stack sorts by its newest merge, so its row shows that time.
                    Text(members.compactMap(\.mergedAt).max() ?? pr.mergedAt ?? pr.createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            // The trackpad-click and VoiceOver path; hover opens the same popover.
            Button { openDetails() } label: {
                Label(isStack ? "Show pull requests in stack" : "Show details for #\(pr.number)", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .focused($chevronFocused)
            .opacity(hovering || isOpen || chevronFocused ? 1 : 0)
            .help(isStack ? "Show pull requests" : "Show details")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.fill.tertiary.opacity(hovering || isOpen ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovering = true
                hover.moved(key)
            case .ended:
                hovering = false
                hover.exited(key)
            }
        }
        .onTapGesture {
            if isStack { openDetails(); return } // a stack has no single URL
            hover.close() // a click that beats the hover timer opens only the browser
            openURL(pr.url)
        }
        .onDisappear { hover.removed(key) }
        // Opens beside the menu like a submenu, so rows keep their height and the menu never resizes.
        .popover(isPresented: Binding(get: { hover.openKey == key }, set: { if !$0 { hover.dismissed(key) } }),
                 arrowEdge: .leading) {
            if isStack {
                StackList(members: members, store: store, showAuthor: showAuthor, showRequest: showRequest)
            } else {
                PRDetails(pr: pr, store: store, showRequest: showRequest)
            }
        }
    }

    private func openDetails() {
        hover.open(key)
    }

    /// A count, so "N of M" stays a position, as in the details' Stack section.
    private var stackSize: Int { pr.stack?.size ?? members.count }

    /// The glyph reads the status, so the label leaves it out.
    private var stackLabel: String { "Stack of \(stackSize) pull requests, \(pr.title)" }

    private var secondaryLine: Text {
        var parts: [Text]
        if members.isEmpty {
            parts = [Text(verbatim: showRepo ? "\(pr.repository.name) #\(pr.number)" : "#\(pr.number)")]
            if showAuthor, let author = pr.author { parts.append(Text(verbatim: author.login)) }
            parts += pr.facts.filter { showStack || !$0.text.hasPrefix("Stack ") }.map { Text($0.text).foregroundStyle($0.tone.style) }
        } else {
            parts = showRepo ? [Text(verbatim: pr.repository.name)] : []
            parts.append(Text(verbatim: "Stack of \(stackSize)"))
            // The failing tone covers failed checks, conflicts, changes requested and an unmergeable queue entry.
            for (tone, word) in [(Badge.Tone.failing, "blocked"), (.running, "running"), (.merging, "merging")] where pr.mergedAt == nil {
                let n = members.filter { $0.status.tone == tone }.count
                if n > 0 { parts.append(Text(verbatim: "\(n) \(word)").foregroundStyle(tone.style)) }
            }
        }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }
}

extension Badge.Tone {
    var style: AnyShapeStyle {
        switch self {
        case .neutral: AnyShapeStyle(.secondary)
        default: AnyShapeStyle(color)
        }
    }

    /// System green measures 1.6:1 and system purple 2.9:1 on the light menu material, too faint to read as text.
    /// These shades keep at least 4.5:1 on the menu and on its gray hover, in light and in dark mode.
    var color: Color {
        switch self {
        case .neutral: Color.secondary
        case .failing: Self.adaptive(light: 0xB0201A, dark: 0xFF8278)
        case .running: Self.adaptive(light: 0x964400, dark: 0xFFA94D)
        case .merging: Self.adaptive(light: 0x7F26A6, dark: 0xD592FF)
        case .passing: Self.adaptive(light: 0x166B2B, dark: 0x5EDB7C)
        case .waiting: Self.adaptive(light: 0x0855B0, dark: 0x7AB8FF)
        }
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func rgb(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light) })
    }
}

/// The second level: one stack's listed members, merging first. Each member row opens its details further left
/// through its own `DetailHover`, so the stack list stays open while the pointer moves between its rows.
struct StackList: View {
    let members: [PullRequest]
    let store: PRStore
    let showAuthor: Bool
    let showRequest: Bool
    @State var inner = DetailHover()
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StackHeader(members: members)
                ForEach(members) { pr in
                    PRRow(pr: pr, key: pr.id, store: store, hover: inner,
                          showRepo: false, showAuthor: showAuthor, showRequest: showRequest, showStack: false)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading) // a fixed width overflows when the scroller takes its 15 pt and shifts rows left
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .frame(width: 360)
        .fittingScroll(contentHeight: height, maxHeight: min(560, (NSScreen.main?.visibleFrame.height ?? 800) - 160))
        .onDisappear { inner.close() } // closing this list closes the details beside it
    }
}

/// Names a stack above its member rows, styled like the menu's section headers.
struct StackHeader: View {
    let members: [PullRequest]

    var body: some View {
        HStack {
            Text(verbatim: "Stack · \(members[0].repository.name)")
            Spacer()
            let size = members[0].stack?.size ?? members.count
            Text(verbatim: members.count < size ? "\(members.count) of \(size) PRs" : "\(size) PRs").monospacedDigit().foregroundStyle(.tertiary)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
        .padding(.trailing, 32)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The leading column. Running checks draw a progress ring; every other state is one SF Symbol.
private struct StatusGlyph: View {
    let pr: PullRequest
    var number: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = pr.status
        Group {
            if status.tone == .running {
                let s = pr.checkSummary
                let done = s.total > 0 ? Double(s.total - s.pending) / Double(s.total) : 0
                // The hidden symbol keeps the ring on the title's baseline and at its point size.
                Image(systemName: "circle")
                    .foregroundStyle(.quaternary)
                    .overlay {
                        // The ring turns once every 1.5 s while checks run; Reduce Motion keeps it still.
                        TimelineView(.animation(paused: reduceMotion)) { context in
                            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
                            Circle()
                                .trim(from: 0, to: max(done, 0.08))
                                .stroke(Badge.Tone.running.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(reduceMotion ? -90 : -90 + turn * 360))
                                .padding(1.5)
                        }
                    }
            } else {
                Image(systemName: status.symbol ?? "circle")
                    .symbolRenderingMode(.monochrome) // hierarchical draws filled symbols at reduced opacity, too faint in color
                    .foregroundStyle(status.tone.style)
            }
        }
        .frame(width: 16)
        .help(number.map { "#\($0): \(status.text)" } ?? status.text)
        .accessibilityLabel(number.map { "#\($0): \(status.text)" } ?? status.text)
    }
}

/// The hover inspector, laid out like Calendar's event popover: header, info grid, reviews, checks, stack.
struct PRDetails: View {
    let pr: PullRequest
    let store: PRStore
    let showRequest: Bool
    @State private var height: CGFloat = 0

    private var detail: PRDetail? { store.details[pr.id]?.detail }
    private var viewer: String? { store.sections?.viewer?.login }

    var body: some View {
        ScrollView {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading) // a fixed width overflows when the scroller takes its 15 pt and shifts rows left
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        // Fits the content, then scrolls past 560 pt or what the screen leaves room for, as ContentView does.
        .frame(width: 440)
        .fittingScroll(contentHeight: height, maxHeight: min(560, (NSScreen.main?.visibleFrame.height ?? 800) - 160))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            info
            Divider()
            reviews
            Divider()
            checks
            if let stack = pr.stack {
                Divider()
                stackSection(stack)
            }
        }
        .font(.subheadline)
        .symbolRenderingMode(.monochrome) // hierarchical draws filled symbols at reduced opacity, too faint in color
        .lineLimit(1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pr.title).font(.headline).lineLimit(3)
            Text(verbatim: ["\(pr.repository.name) #\(pr.number)", pr.author?.login, Self.age(pr.createdAt)]
                .compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatusGlyph(pr: pr).accessibilityHidden(true) // the text beside it says the same
                (Text(pr.status.text).foregroundStyle(pr.status.tone.style) + Text(verbatim: mergedSuffix).foregroundStyle(.secondary))
                    .lineLimit(nil)
            }
            if showRequest, let viewer, let detail, let request = detail.request(viewer: viewer) {
                let source = request.team.map { "Requested via \($0)" } ?? request.by.map { "Requested by \($0)" } ?? "Requested"
                Text(verbatim: "\(source) · \(Self.age(request.at))").foregroundStyle(.secondary)
                if detail.reRequested(viewer: viewer) {
                    Label("Re-requested after your review", systemImage: "arrow.clockwise").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// " by amy · 2h ago" for a merged PR; "by" is left out when the viewer merged it.
    private var mergedSuffix: String {
        guard let mergedAt = pr.mergedAt else { return "" }
        let by = pr.mergedBy.map(\.login).flatMap { $0 == viewer ? nil : " by \($0)" } ?? ""
        return "\(by) · \(Self.age(mergedAt))"
    }

    private var info: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                field("Branch")
                Text(verbatim: "\(pr.headRefName) → \(pr.baseRefName)")
                    .truncationMode(.middle)
                    .help("\(pr.headRefName) → \(pr.baseRefName)")
                    .textSelection(.enabled)
            }
            GridRow {
                field("Changes")
                let counts = detail.map { " · \(Self.count($0.changedFiles, "file")) · \(Self.count($0.commits.totalCount, "commit"))" }
                Text(verbatim: "+\(pr.additions) −\(pr.deletions)\(counts ?? "")").monospacedDigit()
            }
            if let merge {
                GridRow {
                    field("Merge")
                    Text(verbatim: merge.text).foregroundStyle(merge.tone == .neutral ? AnyShapeStyle(.primary) : merge.tone.style)
                }
            }
            if let labels = detail?.labels.nodes, !labels.isEmpty {
                GridRow {
                    field("Labels")
                    Text(verbatim: labels.map(\.name).joined(separator: ", ")).lineLimit(2)
                }
            }
        }
    }

    /// Conflicts come first because they block any queued or automatic merge.
    private var merge: (text: String, tone: Badge.Tone)? {
        if pr.mergedAt != nil { return nil } // a merged PR keeps a stale DIRTY state
        if pr.mergeQueueEntry == nil, pr.mergeStateStatus == "DIRTY" { return ("Conflicts", .failing) }
        if let merge = pr.merge { return (merge.help ?? merge.text, merge.tone) }
        if pr.mergeStateStatus == "BEHIND" { return ("Behind base", .neutral) }
        return nil
    }

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Reviews")
            if let detail {
                let reviewers = detail.reviewers
                if reviewers.isEmpty { Text("No reviews yet").foregroundStyle(.tertiary) }
                ForEach(reviewers.prefix(6), id: \.self) { reviewer($0) }
                let more = max(reviewers.count - 6, 0) + detail.unfetchedReviews
                if more > 0 { Text("+\(more) more").foregroundStyle(.secondary) }
                if detail.unresolvedThreads > 0 {
                    let count = Self.count(detail.unresolvedThreads, "unresolved conversation")
                    Label(detail.unresolvedThreadsCapped ? "At least \(count)" : count, systemImage: "bubble.left")
                        .foregroundStyle(.secondary)
                }
            } else if store.failed.contains(pr.id) {
                Text("Couldn't load reviews").foregroundStyle(.tertiary)
            } else {
                Label("Loading reviewers", systemImage: "circle").redacted(reason: .placeholder)
            }
        }
    }

    private func reviewer(_ reviewer: PRDetail.Reviewer) -> some View {
        let (symbol, state, tone): (String, String, Badge.Tone) = switch reviewer.state {
        case .changesRequested: ("xmark.circle.fill", "changes requested", .failing)
        case .approved: ("checkmark.circle.fill", "approved", .passing)
        case .pendingUser: ("circle.dashed", "review pending", .waiting)
        case .pendingTeam: ("person.2", "review pending", .waiting)
        }
        let name = reviewer.name == viewer ? "You" : reviewer.name
        return Label {
            Text(verbatim: name) + Text(verbatim: reviewer.codeOwner ? " · code owner" : "").foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tone.style)
        }
        .help("\(name): \(state)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(state)\(reviewer.codeOwner ? ", code owner" : "")")
    }

    private var checks: some View {
        let summary = pr.checkSummary
        let total = summary.total + pr.unfetchedCheckCount
        let attention = pr.attentionChecks
        let required = detail?.requiredChecks ?? []
        let more = max(attention.count - 5, 0) + pr.unfetchedCheckCount
        return VStack(alignment: .leading, spacing: 6) {
            // Skipped checks never block, so they stay out of the count: 24 passed and 12 skipped reads "24 of 24".
            sectionHeader("Checks", trailing: total > summary.skipped ? "\(summary.passed) of \(total - summary.skipped) passed" : nil)
            if total == 0 { Label("No checks reported", systemImage: "circle.slash").foregroundStyle(.secondary) }
            ForEach(attention.prefix(5), id: \.self) { check in
                let failed = check.outcome == .failed
                LinkRow(url: check.url) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(check.name, systemImage: failed ? "xmark.circle.fill" : "clock")
                            .foregroundStyle((failed ? Badge.Tone.failing : .running).color)
                        Spacer(minLength: 0)
                        if required.contains(check.name) { Text("Required").foregroundStyle(.tertiary) }
                    }
                }
                .help(check.url == nil ? "" : "Open \(check.name)")
                .accessibilityLabel("\(check.name), \(failed ? "failed" : "running")\(required.contains(check.name) ? ", required" : "")")
            }
            if more > 0 { Label("\(more) more on GitHub", systemImage: "ellipsis.circle").foregroundStyle(.secondary) }
            if summary.passed + summary.skipped > 0 {
                Label {
                    Text(summary.skipped == 0 ? "\(summary.passed) passed"
                         : summary.passed == 0 ? "\(summary.skipped) skipped"
                         : "\(summary.passed) passed, \(summary.skipped) skipped")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: summary.passed > 0 ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(summary.passed > 0 ? Badge.Tone.passing.style : Badge.Tone.neutral.style)
                }
            }
        }
    }

    /// At most 5 members, centered on this PR where the stack allows.
    private func stackSection(_ stack: Stack) -> some View {
        let members = stack.entries.nodes.filter { $0.pullRequest != nil }.sorted { $0.position < $1.position }
        let current = members.firstIndex { $0.pullRequest?.number == pr.number } ?? 0
        let start = max(0, min(current - 2, members.count - 5))
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Stack", trailing: pr.stackEntry.map { "\($0.position) of \(stack.size)" })
            ForEach(members[start..<min(start + 5, members.count)], id: \.self) { entry in
                if let member = entry.pullRequest {
                    let current = member.number == pr.number
                    LinkRow(url: member.url) {
                        Label {
                            Text(verbatim: "#\(member.number) \(member.title)")
                                .fontWeight(current ? .semibold : .regular)
                        } icon: {
                            Image(systemName: Self.stackSymbol(member.state, position: entry.position, current: current))
                        }
                        .foregroundStyle(member.state == "OPEN" ? .primary : .secondary)
                    }
                    .accessibilityLabel("Stack \(entry.position) of \(stack.size): #\(member.number) \(member.title), \(member.state.lowercased())")
                }
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing { Text(verbatim: trailing).monospacedDigit().foregroundStyle(.tertiary) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func field(_ title: LocalizedStringKey) -> some View {
        Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    /// Formatted once per render, so nothing redraws every second.
    static func age(_ date: Date) -> String { date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)) }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    static func stackSymbol(_ state: String, position: Int, current: Bool) -> String {
        switch state {
        case "MERGED": "arrow.triangle.merge" // as in the header's merged status
        case "CLOSED": "xmark.circle"
        // SF Symbols numbers circles up to 50.
        default: position > 50 ? "circle" : current ? "\(position).circle.fill" : "\(position).circle"
        }
    }
}

/// A row that opens its own URL, so a click inside the details does not also open the PR.
private struct LinkRow<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: Content
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if let url { openURL(url) } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(url == nil ? [] : .isLink)
            .accessibilityAction { if let url { openURL(url) } }
    }
}
