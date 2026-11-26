import PullViewCore
import SwiftUI

struct ContentView: View {
    let store: PRStore
    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                list
                    .padding(8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(max(listHeight, 48), 600))
            Divider().padding(.horizontal, 16)
            footer.padding(8)
        }
        .frame(width: 480)
        .onAppear {
            // Opening the menu shows fresh data unless the last fetch is very recent.
            if (store.lastUpdated?.timeIntervalSinceNow ?? -.infinity) < -15 { Task { await store.refresh() } }
        }
    }

    @ViewBuilder private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let sections = store.sections {
                if sections.all.isEmpty {
                    Text("No Open Pull Requests")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
                // Repo names only help when PRs come from more than one repo.
                let showRepo = Set(sections.all.map(\.repository.nameWithOwner)).count > 1
                section("Created", sections.created, total: sections.createdTotal, showRepo: showRepo, showAuthor: false)
                section("Assigned", sections.assigned, total: sections.assignedTotal, showRepo: showRepo)
                section("Review Requested", sections.review, total: sections.reviewTotal, showRepo: showRepo)
            } else if store.error == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(8)
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ prs: [PullRequest], total: Int, showRepo: Bool, showAuthor: Bool = true) -> some View {
        if !prs.isEmpty {
            HStack {
                Text(title)
                Spacer()
                Text(total > prs.count ? "\(prs.count) of \(total)" : "\(prs.count)").monospacedDigit().foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.trailing, 32) // ends at the age column, left of the row's disclosure chevron
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(prs) { PRRow(pr: $0, showRepo: showRepo, showAuthor: showAuthor) }
        }
    }

    /// Menu items as in first-party extras: Refresh, Settings, separator, Quit.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = store.error ?? store.sections?.warning {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            Button { Task { await store.refresh() } } label: {
                Text("Refresh")
                Spacer()
                if store.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("⌘R").foregroundStyle(.tertiary)
                }
            }
            .keyboardShortcut("r")
            .disabled(store.isLoading)

            SettingsItem()

            Divider().padding(.horizontal, 8).padding(.vertical, 4)

            Button { NSApplication.shared.terminate(nil) } label: {
                Text("Quit PullView")
                Spacer()
                Text("⌘Q").foregroundStyle(.tertiary)
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(MenuItemStyle())
    }
}

private struct SettingsItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
            NSApplication.shared.activate() // a menu bar app is not frontmost, so the window would open behind others
        } label: {
            Text("Settings…")
            Spacer()
            Text("⌘,").foregroundStyle(.tertiary)
        }
        .keyboardShortcut(",")
    }
}

/// Full-width row highlighted like a standard menu item: accent background, white text.
/// PR rows keep the gray list hover; only these commands behave like menu items.
private struct MenuItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Item(configuration: configuration) }

    private struct Item: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let highlighted = hovering && isEnabled
            HStack { configuration.label }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Secondary and tertiary labels derive from this style, so shortcuts turn white too.
                .foregroundStyle(highlighted ? AnyShapeStyle(Color(nsColor: .selectedMenuItemTextColor)) : AnyShapeStyle(.primary))
                .background(highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
