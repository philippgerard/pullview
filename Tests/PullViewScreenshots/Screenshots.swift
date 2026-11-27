import AppKit
import PullViewCore
import SwiftUI
import Testing
@testable import PullView

/// Redraws the README screenshots from sample data: `PULLVIEW_SCREENSHOTS=docs swift test --filter screenshots`.
/// The panels are the app's own views. The wallpaper, menu bar, panel backgrounds and arrows are drawn here,
/// because a popover and the menu's material do not render off screen.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["PULLVIEW_SCREENSHOTS"] != nil))
func screenshots() async throws {
    let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PULLVIEW_SCREENSHOTS"] ?? ".")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    NSApplication.shared.setActivationPolicy(.prohibited)

    let sample = try Sample()
    let store = PRStore(sections: sample.sections, details: sample.details)
    let created = sample.sections.created
    let single = try #require(created.first { $0.number == 4807 })
    let stack = try #require(created.groupedByStack().first { $0.count > 1 })
    let stackID = try #require(stack[0].stack?.id)

    for dark in [false, true] {
        let suffix = dark ? "dark" : "light"
        let details = try await Scene.compose(dark: dark, store: store, panels: [
            ContentView(store: store, hover: .opened("Your Pull Requests/\(single.id)")).erased,
            PRDetails(pr: single, store: store, showRequest: false).erased,
        ])
        try details.write(to: dir.appendingPathComponent("details-\(suffix).png"))
        let stacks = try await Scene.compose(dark: dark, store: store, panels: [
            ContentView(store: store, hover: .opened("Your Pull Requests/\(stackID)")).erased,
            StackList(members: stack, store: store, showAuthor: false, showRequest: false).erased,
        ])
        try stacks.write(to: dir.appendingPathComponent("stack-\(suffix).png"))
    }
}

private extension View {
    var erased: AnyView { AnyView(self) }
}

private extension DetailHover {
    static func opened(_ key: String) -> DetailHover {
        let hover = DetailHover()
        hover.open(key)
        return hover
    }
}

// MARK: - Sample data

/// Invented repositories and people, with dates relative to now so the ages read naturally.
@MainActor
private struct Sample {
    let sections: Sections
    let details: [PullRequest.ID: PRDetail]

    init() throws {
        let stackTitles = [
            (4790, "Split cart pricing into a pure module"),
            (4791, "Price bundles through the new module"),
            (4792, "Show bundle savings in the cart"),
            (4793, "Remove the legacy pricing service"),
        ]
        let entries = stackTitles.enumerated().map { i, member -> [String: Any] in
            ["position": i + 1, "pullRequest": ["number": member.0, "title": member.1, "state": "OPEN", "url": Self.url("checkout", member.0)]]
        }
        func stacked(_ position: Int, _ extra: [String: Any]) -> [String: Any] {
            let (number, title) = stackTitles[position - 1]
            return Self.pr(number, title, hours: 20 + Double(position), extra.merging([
                "stack": ["id": "S_1", "size": 4, "entries": ["nodes": entries]], "stackEntry": ["position": position],
                "headRefName": "pricing/part-\(position)", "baseRefName": position == 1 ? "main" : "pricing/part-\(position - 1)",
            ]) { a, _ in a })
        }

        let created: [[String: Any]] = [
            Self.pr(4821, "Add idempotency keys to payment retries", hours: 5, [
                "mergeQueueEntry": ["position": 1, "state": "MERGEABLE", "estimatedTimeToMerge": 140, "enqueuedAt": Self.ago(0.2)],
                "statusCheckRollup": Self.checks(passed: 24),
            ]),
            Self.pr(4807, "Cache tax rates per region", hours: 3, [
                "reviewDecision": "REVIEW_REQUIRED", "headRefName": "sam/tax-rate-cache", "additions": 412, "deletions": 87,
                "autoMergeRequest": ["mergeMethod": "SQUASH", "enabledBy": ["login": "sam"]],
                "statusCheckRollup": Self.checks(failed: ["unit (node 22)"], running: ["e2e / checkout", "bundle size"], passed: 19, skipped: 2),
            ]),
            stacked(1, ["statusCheckRollup": Self.checks(passed: 24)]),
            stacked(2, ["statusCheckRollup": Self.checks(running: ["e2e / checkout", "unit (node 22)"], passed: 22)]),
            stacked(3, ["reviewDecision": "REVIEW_REQUIRED", "statusCheckRollup": Self.checks(passed: 24)]),
            stacked(4, ["isDraft": true, "reviewDecision": NSNull(), "statusCheckRollup": Self.checks(failed: ["typecheck"], passed: 23)]),
            Self.pr(4775, "Migrate order exports to streaming CSV", hours: 26, [
                "mergeQueueEntry": ["position": 3, "state": "AWAITING_CHECKS", "estimatedTimeToMerge": 660, "enqueuedAt": Self.ago(0.1)],
                "statusCheckRollup": Self.checks(running: ["e2e / checkout", "e2e / exports", "integration"], passed: 17),
            ]),
            Self.pr(312, "Fix focus ring contrast in dark mode", repo: "design-system", hours: 50, [
                "reviewDecision": "CHANGES_REQUESTED", "mergeStateStatus": "DIRTY", "isMergeQueueEnabled": false,
                "statusCheckRollup": Self.checks(passed: 9),
            ]),
        ]
        let assigned: [[String: Any]] = [
            Self.pr(318, "Bump Storybook to 9.1", repo: "design-system", author: "deps-bot", hours: 8, [
                "isMergeQueueEnabled": false, "autoMergeRequest": ["mergeMethod": "SQUASH", "enabledBy": ["login": "sam"]],
                "statusCheckRollup": Self.checks(passed: 9),
            ]),
        ]
        let review: [[String: Any]] = [
            Self.pr(4812, "Rate-limit the address autocomplete endpoint", author: "mira", hours: 2, [
                "reviewDecision": "REVIEW_REQUIRED", "statusCheckRollup": Self.checks(passed: 24),
            ]),
            Self.pr(327, "Add range selection to DatePicker", repo: "design-system", author: "devika", hours: 6, [
                "reviewDecision": "REVIEW_REQUIRED", "isMergeQueueEnabled": false,
                "statusCheckRollup": Self.checks(running: ["visual regression", "a11y"], passed: 7),
            ]),
            Self.pr(4803, "Render the cart summary at the edge", author: "jonas-k", hours: 30, [
                "isDraft": true, "reviewDecision": NSNull(), "statusCheckRollup": Self.checks(passed: 24),
            ]),
        ]
        let merged: [[String: Any]] = [
            (4798, "Retry webhook deliveries with backoff", 4.0), (4786, "Log slow checkout queries", 22), (4779, "Drop the unused coupon table", 31),
            (305, "Add a compact Table density", 47), (4760, "Validate postcodes per country", 60),
        ].map { Self.pr($0.0, $0.1, repo: $0.0 < 1000 ? "design-system" : "checkout", hours: $0.2 + 20, ["mergedAt": Self.ago($0.2), "mergedBy": ["login": "sam"]]) }

        func connection(_ nodes: [[String: Any]]) -> [String: Any] { ["nodes": nodes] }
        let data = try JSONSerialization.data(withJSONObject: ["data": [
            "viewer": ["login": "sam"],
            "created": connection(created), "assigned": connection(assigned), "review": connection(review), "merged": connection(merged),
        ]])
        sections = try GitHubClient.decode(data)

        let single = created[1]["id"] as! String
        let detail: [String: Any] = [
            "changedFiles": 14, "commits": ["totalCount": 6],
            "labels": ["nodes": [["name": "payments"], ["name": "performance"]]],
            "latestOpinionatedReviews": ["nodes": [["state": "APPROVED", "submittedAt": Self.ago(1), "author": ["login": "mira"]]]],
            "reviewRequests": ["nodes": [
                ["asCodeOwner": true, "requestedReviewer": ["login": "jonas-k"]],
                ["asCodeOwner": false, "requestedReviewer": ["combinedSlug": "northwind/payments"]],
            ]],
            "reviewThreads": ["nodes": [["isResolved": false], ["isResolved": false], ["isResolved": true]]],
            "viewerLatestReview": NSNull(), "timelineItems": ["nodes": [] as [Any]],
            "statusCheckRollup": ["contexts": ["nodes": [
                ["name": "unit (node 22)", "isRequired": true], ["name": "e2e / checkout", "isRequired": true], ["name": "bundle size", "isRequired": false],
            ]]],
        ]
        details = try GitHubClient.decodeDetails(JSONSerialization.data(withJSONObject: ["data": ["p0": detail]]), ids: [single])
    }

    static func ago(_ hours: Double) -> String { Date.now.addingTimeInterval(-hours * 3600).ISO8601Format() }
    static func url(_ repo: String, _ number: Int) -> String { "https://github.com/northwind/\(repo)/pull/\(number)" }

    static func pr(_ number: Int, _ title: String, repo: String = "checkout", author: String = "sam", hours: Double,
                   _ extra: [String: Any] = [:]) -> [String: Any] {
        let base: [String: Any] = [
            "id": "PR_\(number)", "number": number, "title": title, "url": url(repo, number), "isDraft": false,
            "createdAt": ago(hours), "additions": 120 + number % 90, "deletions": 20 + number % 40, "author": ["login": author],
            "repository": ["nameWithOwner": "northwind/\(repo)"], "baseRefName": "main", "headRefName": "\(author)/\(number)",
            "reviewDecision": "APPROVED", "mergeStateStatus": "CLEAN", "isMergeQueueEnabled": true,
        ]
        return base.merging(extra) { $1 }
    }

    static func checks(failed: [String] = [], running: [String] = [], passed: Int, skipped: Int = 0) -> [String: Any] {
        func run(_ name: String, _ status: String, _ conclusion: Any) -> [String: Any] {
            ["__typename": "CheckRun", "name": name, "status": status, "conclusion": conclusion, "detailsUrl": "https://github.com/northwind"]
        }
        let nodes = failed.map { run($0, "COMPLETED", "FAILURE") } + running.map { run($0, "IN_PROGRESS", NSNull()) }
            + (0..<passed).map { run("job \($0)", "COMPLETED", "SUCCESS") } + (0..<skipped).map { run("skipped \($0)", "COMPLETED", "SKIPPED") }
        return ["state": !failed.isEmpty ? "FAILURE" : running.isEmpty ? "SUCCESS" : "PENDING", "contexts": ["nodes": nodes]]
    }
}

// MARK: - Drawing

/// A desktop corner in points, y down: the menu hangs from the menu bar at the right, and each further panel
/// opens to its left with an arrow at the highlighted row, as popovers do beside a menu at the screen edge.
@MainActor
private enum Scene {
    static let scale: CGFloat = 2
    static let margin: CGFloat = 40, barHeight: CGFloat = 28, gap: CGFloat = 14, radius: CGFloat = 13

    static func compose(dark: Bool, store: PRStore, panels: [AnyView]) async throws -> Data {
        var images: [NSBitmapImageRep] = []
        for panel in panels { images.append(try await render(panel, dark: dark)) }

        // Right to left. Each panel centers on the previous panel's highlighted row where the menu bar allows.
        var frames: [CGRect] = [], arrows: [CGFloat?] = []
        let width = images.map(\.size.width).reduce(0, +) + CGFloat(images.count - 1) * gap + 2 * margin
        var right = width - margin
        var anchor: CGFloat?
        for image in images {
            let top = max(barHeight + 6, (anchor ?? 0) - image.size.height / 2)
            let frame = CGRect(x: right - image.size.width, y: top, width: image.size.width, height: image.size.height)
            frames.append(frame)
            arrows.append(anchor)
            anchor = highlightedRow(in: image).map { frame.minY + $0 }
            right = frame.minX - gap
        }
        let height = (frames.map(\.maxY).max() ?? 0) + margin

        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = CGSize(width: width, height: height)
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        let cg = context.cgContext
        cg.translateBy(x: 0, y: height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Wallpaper in the icon's blues, clipped to rounded corners. Vertical, because a diagonal gradient
        // compresses worse: 1.4 MB per PNG instead of 0.9 MB.
        cg.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerWidth: 16, cornerHeight: 16, transform: nil))
        cg.clip()
        let colors = (dark ? [0x1C2260, 0x0D1030] : [0x6F8DF7, 0x3F4BD8]).map { rgb(UInt32($0)) } as CFArray
        let gradient = try #require(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]))
        cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])

        menuBar(in: cg, store: store, menu: frames[0])

        for (i, image) in images.enumerated() {
            let frame = frames[i]
            var shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if let y = arrows[i] {
                let tip = CGMutablePath()
                tip.move(to: CGPoint(x: frame.maxX - 1, y: y - 13))
                tip.addLine(to: CGPoint(x: frame.maxX + 9, y: y - 2.5))
                tip.addQuadCurve(to: CGPoint(x: frame.maxX + 9, y: y + 2.5), control: CGPoint(x: frame.maxX + 12, y: y))
                tip.addLine(to: CGPoint(x: frame.maxX - 1, y: y + 13))
                tip.closeSubpath()
                shape = shape.union(tip)
            }
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale, color: CGColor(gray: 0, alpha: dark ? 0.5 : 0.3))
            cg.addPath(shape)
            cg.setFillColor(dark ? rgb(0x26262A, 0.96) : rgb(0xF4F4F6, 0.96))
            cg.fillPath()
            cg.restoreGState()
            cg.addPath(shape)
            cg.setStrokeColor(CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.16 : 0.1))
            cg.setLineWidth(0.5)
            cg.strokePath()
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        context.flushGraphics()
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// Lays the view out in a window that is never shown and draws it at 2x on a clear background.
    static func render(_ view: AnyView, dark: Bool) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        // Each list reports its height through state, so the size settles over a few run loop turns.
        for _ in 0..<6 {
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
        }
        let size = host.bounds.size
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        window.close()
        return rep
    }

    /// The vertical center of the row with the open-popover highlight. Rows start 8 pt from the panel's edge and
    /// their content 8 pt further in, so only a highlight paints the column in between.
    static func highlightedRow(in image: NSBitmapImageRep) -> CGFloat? {
        let x = Int(12 * scale)
        let painted = (0..<image.pixelsHigh).filter { (image.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.02 }
        guard let first = painted.first, let last = painted.last else { return nil }
        return CGFloat(first + last) / 2 / scale
    }

    /// The status item as the app draws it, highlighted as while its menu is open, beside a few system items.
    static func menuBar(in cg: CGContext, store: PRStore, menu: CGRect) {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        func symbol(_ name: String, at x: CGFloat) -> CGFloat {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium).applying(.init(paletteColors: [.white]))
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return x }
            image.draw(in: CGRect(x: x, y: (barHeight - image.size.height) / 2, width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return x + image.size.width
        }
        func text(_ string: String, at x: CGFloat) -> CGFloat {
            let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.white])
            let size = attributed.size()
            attributed.draw(at: CGPoint(x: x, y: (barHeight - size.height) / 2))
            return x + size.width
        }
        let count = "\(store.openCount)"
        let countWidth = NSAttributedString(string: count, attributes: [.font: font]).size().width
        let item = CGRect(x: menu.midX - 30, y: 3, width: 16 + 4 + countWidth + 20, height: barHeight - 6)
        cg.addPath(CGPath(roundedRect: item, cornerWidth: 6, cornerHeight: 6, transform: nil))
        cg.setFillColor(CGColor(gray: 1, alpha: 0.22))
        cg.fillPath()
        let afterSymbol = symbol(store.hasFailingOwnPR ? "xmark.circle" : "arrow.triangle.pull", at: item.minX + 10)
        _ = text(count, at: afterSymbol + 4)

        var x = item.maxX + 14
        for name in ["wifi", "battery.75percent", "switch.2"] { x = symbol(name, at: x) + 16 }
        _ = text("9:41", at: x)
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
