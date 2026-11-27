import Observation

/// Which row's details popover is open. The pointer must rest 300 ms on a row to open it and 250 ms to switch rows.
/// Every move restarts the timer, so a pointer crossing rows toward the open popover never switches it.
/// Leaving a row never closes the popover, as an NSMenu submenu stays open while the pointer travels.
@MainActor @Observable
final class DetailHover {
    /// "\(section)/\(pr.id)": one PR can be in two sections.
    private(set) var openKey: String?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var pendingKey: String?
    /// The row a switch is moving to during its 50 ms gap, while `openKey` is nil.
    @ObservationIgnored private var switching: String?
    /// The row whose popover Escape or a click closed. Hover leaves it closed until the pointer leaves the row,
    /// as an NSMenu submenu closed with Escape stays closed.
    @ObservationIgnored private var suppressed: String?
    @ObservationIgnored private var suppressedAt = ContinuousClock.now

    /// Called on every pointer move inside a row.
    func moved(_ key: String) {
        if suppressed == key { return }
        suppressed = nil
        if switching == key { return }
        if openKey == key { cancel(); return }
        let delay = Duration.milliseconds(openKey == nil && switching == nil ? 300 : 250)
        cancel()
        pendingKey = key
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.show(key)
        }
    }

    /// A pointer that leaves before the delay cancels the open, so a diagonal move toward the popover keeps it.
    func exited(_ key: String) {
        if pendingKey == key { cancel() }
        if suppressed == key { suppressed = nil }
    }

    /// The chevron and a stack row's click open. A click on the open row closes it, because AppKit dismisses on mouseDown.
    /// Escape, a click outside and the footer close it.
    func open(_ key: String) {
        cancel()
        // AppKit closes a transient popover on mouseDown in the menu. The same click's mouseUp must not reopen it.
        if suppressed == key, suppressedAt.duration(to: .now) < .milliseconds(500) { return }
        suppressed = nil
        if openKey != key { show(key) }
    }

    /// The popover's binding setter. A switch already moved `openKey`, so only the current row may clear it.
    func dismissed(_ key: String) {
        guard openKey == key else { return }
        openKey = nil
        suppressed = key
        suppressedAt = .now
    }

    /// A poll removed the row, so its popover and any pending open go with it.
    func removed(_ key: String) {
        if pendingKey == key || switching == key { cancel() }
        if openKey == key { openKey = nil }
    }

    func close() {
        cancel()
        suppressed = nil
        openKey = nil
    }

    private func show(_ key: String) {
        pendingKey = nil
        guard openKey != nil else { openKey = key; return }
        // Swapping in one transaction can drop the new presentation. 50 ms lets SwiftUI commit the close first.
        openKey = nil
        switching = key
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.switching = nil
            self?.openKey = key
        }
    }

    private func cancel() {
        pending?.cancel()
        pending = nil
        pendingKey = nil
        switching = nil
    }
}
