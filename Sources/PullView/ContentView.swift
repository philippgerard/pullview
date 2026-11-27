import PullViewCore
import SwiftUI

struct ContentView: View {
    let store: PRStore
    @State private var listHeight: CGFloat = 0
    @State private var hover = DetailHover()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                list
                    .padding(8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            // Scrolls only when the list is taller than the screen leaves room for.
            .fittingScroll(contentHeight: listHeight, maxHeight: (NSScreen.main?.visibleFrame.height ?? 800) - 160)
            // Fixed height and always present, so the window never resizes; above the separator, as in an NSMenu.
            mergedItem.padding(.horizontal, 8).padding(.bottom, 4)
            Divider().padding(.horizontal, 16)
            footer.padding(8)
                .onHover { if $0 { hover.close() } } // like moving from a submenu's parent to another menu item
        }
        .frame(width: 480)
        .onAppear {
            // Opening the menu shows fresh data unless the last fetch is very recent.
            if (store.lastUpdated?.timeIntervalSinceNow ?? -.infinity) < -15 { Task { await store.refresh() } }
        }
        .onDisappear { hover.close() }
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
                section("Your Pull Requests", sections.created, total: sections.createdTotal, showRepo: showRepo, showAuthor: false)
                section("Assigned to You", sections.assigned, total: sections.assignedTotal, showRepo: showRepo)
                section("Waiting for Your Review", sections.review, total: sections.reviewTotal, showRepo: showRepo)
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
            ForEach(prs.groupedByStack(), id: \.groupID) { group in
                PRRow(pr: group[0], members: group.count > 1 ? group : [], key: "\(title)/\(group.groupID)", store: store, hover: hover,
                      showRepo: showRepo, showAuthor: showAuthor, showRequest: title == "Waiting for Your Review")
            }
        }
    }

    /// A submenu-style item. With no merged PRs it is dimmed and opens nothing, like a disabled item with an empty submenu.
    private var mergedItem: some View {
        let key = "Recently Merged"
        let merged = store.sections?.merged ?? []
        let total = store.sections?.mergedTotal ?? 0
        return Button { hover.open(key) } label: {
            Text("Recently Merged")
            Spacer()
            if !merged.isEmpty {
                Text(verbatim: total > merged.count ? "\(merged.count) of \(total)" : "\(total)").monospacedDigit().foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .buttonStyle(MenuItemStyle(selected: hover.openKey == key))
        .disabled(merged.isEmpty)
        .onContinuousHover { phase in
            // A dimmed item still closes another item's open popover, as in an NSMenu.
            if case .active = phase { if merged.isEmpty { hover.close() } else { hover.moved(key) } } else { hover.exited(key) }
        }
        // A list emptied by a poll forgets the open popover, so a later merge does not reopen it unhovered.
        .onChange(of: merged.isEmpty) { _, empty in if empty { hover.removed(key) } }
        .popover(isPresented: Binding(get: { hover.openKey == key && !merged.isEmpty }, set: { if !$0 { hover.dismissed(key) } }),
                 arrowEdge: .leading) {
            MergedList(prs: merged, store: store)
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

/// The merged PRs beside the menu, grouped by stack as in the main list. No title, as an NSMenu submenu has none.
/// A stack lists its members under a header, so details open at the third level and the chain fits left of the menu.
private struct MergedList: View {
    let prs: [PullRequest]
    let store: PRStore
    @State private var inner = DetailHover()
    @State private var height: CGFloat = 0

    var body: some View {
        let showRepo = Set(prs.map(\.repository.nameWithOwner)).count > 1
        ScrollView {
            // Same rows as the main list: a stack row opens its members, a PR row opens its details.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(prs.groupedByStack(), id: \.groupID) { group in
                    PRRow(pr: group[0], members: group.count > 1 ? group : [], key: group.groupID, store: store, hover: inner,
                          showRepo: showRepo, showAuthor: false)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading) // a fixed width overflows when the scroller takes its 15 pt and shifts rows left
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .frame(width: 400)
        .fittingScroll(contentHeight: height, maxHeight: min(560, (NSScreen.main?.visibleFrame.height ?? 800) - 160))
        .onDisappear { inner.close() } // closing this list closes the popovers beside it
    }
}

private extension Array where Element == PullRequest {
    /// A stack row and its lone survivor get different IDs, so the survivor returns as a new plain row with its popover closed.
    /// Stack and PR IDs are both GraphQL node IDs and never collide.
    var groupID: String { (count > 1 ? self[0].stack?.id : nil) ?? self[0].id }
}

extension View {
    /// Sizes a ScrollView to its content up to `maxHeight`. Below that it shows no scroller,
    /// which "Show scroll bars: Always" would otherwise draw over content that already fits.
    func fittingScroll(contentHeight: CGFloat, maxHeight: CGFloat) -> some View {
        frame(height: min(max(contentHeight, 48), maxHeight))
            .scrollIndicators(contentHeight > maxHeight ? .automatic : .never)
            .scrollBounceBehavior(.basedOnSize)
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
    /// Keeps the highlight while the item's submenu popover is open.
    var selected = false

    func makeBody(configuration: Configuration) -> some View { Item(configuration: configuration, selected: selected) }

    private struct Item: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let highlighted = (hovering || selected) && isEnabled
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
