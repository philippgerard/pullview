import PullViewCore
import SwiftUI

/// Two lines per PR: a fixed status glyph, the title with the merge slot, then facts with the age.
struct PRRow: View {
    let pr: PullRequest
    var showRepo = true
    var showAuthor = true
    @State private var expanded = false
    @State private var hovering = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StatusGlyph(pr: pr)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pr.title)
                        .lineLimit(1)
                        .help(pr.title)
                        .accessibilityAddTraits(.isLink)
                        .accessibilityAction { openURL(pr.url) }
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
                    Text(pr.createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if expanded { PRDetails(pr: pr) }
            }
            Button { expanded.toggle() } label: {
                Label(expanded ? "Hide details" : "Show details", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(hovering || expanded ? 1 : 0)
            .help(expanded ? "Hide details" : "Show checks, branch and stack")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.fill.tertiary.opacity(hovering ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { openURL(pr.url) }
        .animation(.snappy(duration: 0.2), value: expanded)
    }

    private var secondaryLine: Text {
        var parts = [Text(verbatim: showRepo ? "\(pr.repository.name) #\(pr.number)" : "#\(pr.number)")]
        if showAuthor, let author = pr.author { parts.append(Text(verbatim: author.login)) }
        parts += pr.facts.map { Text($0.text).foregroundStyle($0.tone.style) }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }
}

extension Badge.Tone {
    var style: AnyShapeStyle {
        switch self {
        case .neutral: AnyShapeStyle(.secondary)
        case .failing: AnyShapeStyle(.red)
        case .running: AnyShapeStyle(.orange)
        case .merging: AnyShapeStyle(.purple)
        }
    }
}

/// The leading column. Running checks draw a progress ring; every other state is one SF Symbol.
private struct StatusGlyph: View {
    let pr: PullRequest

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
                        Circle()
                            .trim(from: 0, to: max(done, 0.08))
                            .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(1.5)
                    }
            } else {
                Image(systemName: status.symbol ?? "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(status.tone.style)
            }
        }
        .frame(width: 16)
        .help(status.text)
        .accessibilityLabel(status.text)
    }
}

private struct PRDetails: View {
    let pr: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(verbatim: "\(pr.headRefName) → \(pr.baseRefName)   +\(pr.additions) −\(pr.deletions)")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "arrow.triangle.branch")
            }

            if let merge = pr.merge, let symbol = merge.symbol {
                Label(merge.help ?? merge.text, systemImage: symbol).foregroundStyle(merge.tone.style)
            }

            let summary = pr.checkSummary
            if summary.total == 0, pr.unfetchedCheckCount == 0 {
                Label("No checks reported", systemImage: "circle.slash")
            } else if pr.attentionChecks.isEmpty, !pr.checksFailing, !pr.checksPending {
                Label(summary.skipped == 0 ? "All \(summary.passed) checks passed"
                      : summary.passed == 0 ? "All \(summary.skipped) checks skipped"
                      : "\(summary.passed) checks passed, \(summary.skipped) skipped",
                      systemImage: "checkmark.circle")
            }
            ForEach(pr.attentionChecks, id: \.self) { check in
                let failed = check.outcome == .failed
                LinkRow(url: check.url) {
                    Label(check.name, systemImage: failed ? "xmark.circle.fill" : "clock")
                        .foregroundStyle(failed ? Color.red : .orange)
                }
                .help(check.url == nil ? "" : "Open \(check.name)")
            }
            if pr.unfetchedCheckCount > 0 {
                Label("\(pr.unfetchedCheckCount) more checks on GitHub", systemImage: "ellipsis.circle")
            }

            if let stack = pr.stack {
                ForEach(stack.entries.nodes, id: \.self) { entry in
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
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .symbolRenderingMode(.hierarchical)
        .lineLimit(1)
        .padding(.top, 4)
    }

    static func stackSymbol(_ state: String, position: Int, current: Bool) -> String {
        switch state {
        case "MERGED": "checkmark.circle.fill"
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
    }
}
