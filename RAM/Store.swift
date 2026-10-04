import Foundation
import AppKit
import Darwin
import Observation

@MainActor
@Observable
final class Store {
    var memory: MemorySnapshot = .empty
    var history: [HistoryPoint] = []
    var processes: [Proc] = []
    var popupOpen = false
    var listView: ListView = .nested
    var sortDescending = true
    var filter = ""
    var filterRevealed = false
    var expanded: Set<String> = []
    var activityMonitorNote: String?

    @ObservationIgnored
    private var activityMonitorOpening = false
    var forceQuitTarget: Proc?
    var selectedProcessPid: Int32?
    var launchAtLogin = LaunchAtLogin.isEnabled

    @ObservationIgnored
    weak var popoverWindow: NSWindow?

    @ObservationIgnored
    private var keyMonitor: Any?

    private var chipTimer: Timer?
    private var popupTimer: Timer?
    private var extraWindowObservers: [NSObjectProtocol] = []
    private let historyCap = 60
    private var processSampleGeneration = 0

    @ObservationIgnored
    private weak var notedWindow: NSWindow?

    @ObservationIgnored
    private var notedWindowVisible = false

    init() {
        if let raw = UserDefaults.standard.string(forKey: "ram.listView"),
           let saved = ListView(rawValue: raw) {
            listView = saved
        }
        if UserDefaults.standard.object(forKey: "ram.sortDescending") != nil {
            sortDescending = UserDefaults.standard.bool(forKey: "ram.sortDescending")
        }
        if UserDefaults.standard.object(forKey: "ram.filterRevealed") != nil {
            filterRevealed = UserDefaults.standard.bool(forKey: "ram.filterRevealed")
        }
        if let saved = UserDefaults.standard.stringArray(forKey: "ram.expanded") {
            expanded = Set(saved)
        }
        refreshMemory()
        startChipTimer()
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func popupAppeared() {
        let alreadyOpen = popupOpen
        popupOpen = true
        if !alreadyOpen {
            filter = ""
            activityMonitorNote = nil
            forceQuitTarget = nil
            selectedProcessPid = nil
        }
        refreshMemory()
        refreshProcesses()
        startPopupTimer()
        popoverWindow?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    func popupDisappeared() {
        popupOpen = false
        popupTimer?.invalidate()
        popupTimer = nil
        if let window = popoverWindow, let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .abort)
        }
        forceQuitTarget = nil
        selectedProcessPid = nil
        filter = ""
        processes = []
        removeKeyMonitor()
        // Keep popoverWindow so becomeKey can restart sampling if SwiftUI skips onAppear.
    }


    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleFilterKey(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        self.keyMonitor = nil
    }

    /// MenuBarExtra .window often keeps PopupView mounted after dismiss (onDisappear never fires)
    /// and can skip onAppear on the next click. Drive open/closed from the extra window itself.
    func noteExtraWindow(_ window: NSWindow?) {
        guard let window else { return }
        let visible = window.isVisible
        if notedWindow === window, notedWindowVisible == visible {
            // Identity and visibility are unchanged. A sheet can be the only reason
            // a hidden window has not closed yet, so keep checking that case.
            if visible || !popupOpen || isSheetBlockingDismiss(window) {
                return
            }
        }
        notedWindow = window
        notedWindowVisible = visible
        bindExtraWindow(window)
        if visible {
            if !popupOpen {
                popupAppeared()
            }
        } else if popupOpen && !isSheetBlockingDismiss(window) {
            popupDisappeared()
        }
    }

    func toggleFilter() {
        if filterRevealed || !filter.isEmpty {
            filter = ""
            filterRevealed = false
        } else {
            filterRevealed = true
        }
        saveFilterRevealed()
    }

    func cycleView() {
        listView = listView.next
        expanded = []
        saveExpanded()
        selectedProcessPid = nil
        forceQuitTarget = nil
        UserDefaults.standard.set(listView.rawValue, forKey: "ram.listView")
    }

    func toggleSort() {
        sortDescending.toggle()
        UserDefaults.standard.set(sortDescending, forKey: "ram.sortDescending")
    }

    func toggleExpanded(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
        saveExpanded()
    }

    private func saveFilterRevealed() {
        UserDefaults.standard.set(filterRevealed, forKey: "ram.filterRevealed")
    }

    private func saveExpanded() {
        UserDefaults.standard.set(Array(expanded), forKey: "ram.expanded")
    }

    func setLaunchAtLogin(_ on: Bool) {
        LaunchAtLogin.setEnabled(on)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func openActivityMonitor() {
        guard !activityMonitorOpening else { return }
        activityMonitorOpening = true
        Task { [weak self] in
            let note = await Task.detached(priority: .userInitiated) {
                ActivityMonitorOpener.open()
            }.value
            guard let self else { return }
            self.activityMonitorOpening = false
            guard self.popupOpen else { return }
            self.activityMonitorNote = note
        }
    }

    func selectProcess(pid: Int32) {
        if selectedProcessPid == pid {
            selectedProcessPid = nil
            forceQuitTarget = nil
        } else {
            selectedProcessPid = pid
            forceQuitTarget = nil
        }
    }

    func clearSelection() {
        selectedProcessPid = nil
        forceQuitTarget = nil
    }

    func requestForceQuit(_ proc: Proc, window: NSWindow? = nil) {
        if let window {
            popoverWindow = window
        }
        let host = window ?? popoverWindow
        forceQuitTarget = proc
        guard let host, host.attachedSheet == nil else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Force Quit \(proc.displayName)?"
        let forceQuitButton = alert.addButton(withTitle: "Force Quit")
        forceQuitButton.hasDestructiveAction = true
        forceQuitButton.keyEquivalent = ""
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        alert.window.defaultButtonCell = nil

        alert.beginSheetModal(for: host) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.performForceQuit()
            } else {
                self.cancelForceQuit()
            }
        }
    }

    func cancelForceQuit() {
        forceQuitTarget = nil
    }

    func performForceQuit() {
        guard let proc = forceQuitTarget else { return }
        forceQuitTarget = nil
        selectedProcessPid = nil
        // Refuse to signal if the PID was reused (start time no longer matches).
        guard Self.matchesIdentity(proc) else {
            refreshProcesses()
            refreshMemory()
            return
        }
        _ = Self.terminateMatching(proc)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if Self.matchesIdentity(proc) {
                self.presentForceQuitFailed(proc)
            }
            self.refreshProcesses()
            self.refreshMemory()
        }
    }

    /// `kill(pid, 0)` succeeds if we can signal it. EPERM means it is alive but not ours.
    private static func isRunning(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Same PID + same kernel start time as when the row was sampled.
    private static func matchesIdentity(_ proc: Proc) -> Bool {
        guard isRunning(proc.pid) else { return false }
        guard let start = ProcessSampler.startTime(pid: proc.pid) else { return false }
        return start.sec == proc.startSec && start.usec == proc.startUsec
    }

    /// One checked terminate path: AppKit forceTerminate when available, else SIGKILL.
    /// Re-validates identity before each signal so a replacement process is never hit.
    /// forceTerminate() success only means the request was sent — re-check, then SIGKILL if still live.
    @discardableResult
    private static func terminateMatching(_ proc: Proc) -> Bool {
        guard matchesIdentity(proc) else { return false }
        if let app = NSRunningApplication(processIdentifier: proc.pid) {
            // forceTerminate returning true means the request was sent, NOT that the process died.
            _ = app.forceTerminate()
            // Exited (or was replaced) during forceTerminate — treat as done.
            if !matchesIdentity(proc) { return true }
            // Same identity still live — fall through to SIGKILL.
        }
        guard matchesIdentity(proc) else { return false }
        return kill(proc.pid, SIGKILL) == 0
    }

    private func presentForceQuitFailed(_ proc: Proc) {
        guard let host = popoverWindow, host.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Force Quit \(proc.displayName)"
        alert.informativeText = "The process is still running."
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: host, completionHandler: nil)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    /// Type-to-filter like a menu: printable keys append, delete backs up, escape clears.
    /// Returns nil when the event is consumed so the menu extra keeps focus.
    /// When the native search field / field editor has focus, keys pass through untouched
    /// so selection replace and backspace work correctly.
    func handleFilterKey(_ event: NSEvent) -> NSEvent? {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            return event
        }
        // Sheet owns keys while Force Quit is up. Do not treat Return as confirm.
        if forceQuitTarget != nil || popoverWindow?.attachedSheet != nil {
            return event
        }
        // Native text editing owns the event — do not mutate `filter` by hand.
        if Self.isTextEditing(in: popoverWindow) {
            return event
        }
        if event.keyCode == 53 { // escape
            if !filter.isEmpty || filterRevealed {
                filter = ""
                filterRevealed = false
                saveFilterRevealed()
                return nil
            }
            if selectedProcessPid != nil {
                selectedProcessPid = nil
                return nil
            }
            return event
        }
        if event.keyCode == 51 { // delete
            if !filter.isEmpty {
                filter.removeLast()
                return nil
            }
            return event
        }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let ch = chars.first, ch.isASCII else {
            return event
        }
        if ch.isLetter || ch.isNumber || ch == " " || ch == "-" || ch == "." || ch == "_" {
            filter.append(ch)
            filterRevealed = true
            saveFilterRevealed()
            selectedProcessPid = nil
            return nil
        }
        return event
    }

    var rows: [ListRow] {
        Grouping.rows(view: listView, processes: processes, filter: filter, expanded: expanded, sortDescending: sortDescending)
    }

    private func startChipTimer() {
        chipTimer?.invalidate()
        chipTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.popupOpen {
                    self.stopPopupIfWindowHidden()
                    if self.popupOpen { return }
                }
                self.refreshMemory()
            }
        }
        chipTimer?.tolerance = 1
    }

    private func startPopupTimer() {
        popupTimer?.invalidate()
        popupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popupOpen else { return }
                if self.stopPopupIfWindowHidden() { return }
                self.refreshMemory()
                self.sampleProcessesOffMain()
            }
        }
        popupTimer?.tolerance = 0.2
    }

    private func refreshMemory() {
        let snap = MemorySampler.snapshot()
        memory = snap
        guard popupOpen else { return }
        history.append(HistoryPoint(fraction: snap.usedFraction, sampledAt: snap.sampledAt))
        if history.count > historyCap {
            history.removeFirst(history.count - historyCap)
        }
    }

    @discardableResult
    private func stopPopupIfWindowHidden() -> Bool {
        guard let window = popoverWindow else { return false }
        guard !window.isVisible, !isSheetBlockingDismiss(window) else { return false }
        popupDisappeared()
        return true
    }

    private func isSheetBlockingDismiss(_ window: NSWindow) -> Bool {
        forceQuitTarget != nil || window.attachedSheet != nil || window.isSheet
    }

    private func bindExtraWindow(_ window: NSWindow) {
        if popoverWindow === window, !extraWindowObservers.isEmpty { return }
        for observer in extraWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        extraWindowObservers = []
        popoverWindow = window
        extraWindowObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.popupOpen else { return }
                    self.popupAppeared()
                }
            }
        )
        extraWindowObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.popupOpen else { return }
                    if let window = self.popoverWindow {
                        if window.isVisible || self.isSheetBlockingDismiss(window) { return }
                    }
                    self.popupDisappeared()
                }
            }
        )
    }

    /// True when an AppKit field editor / text field owns first responder in the popup.
    private static func isTextEditing(in window: NSWindow?) -> Bool {
        let keyWindow: NSWindow?
        if let window, window.isKeyWindow {
            keyWindow = window
        } else {
            keyWindow = NSApp.keyWindow
        }
        guard let first = keyWindow?.firstResponder else { return false }
        if first is NSTextView || first is NSText { return true }
        if let field = first as? NSTextField, field.currentEditor() != nil { return true }
        if let control = first as? NSControl, control.currentEditor() != nil { return true }
        return false
    }

    private func refreshProcesses() {
        processSampleGeneration += 1
        applyProcesses(ProcessSampler.list())
    }

    /// The open popup samples processes every second. Do that off the main actor.
    private func sampleProcessesOffMain() {
        processSampleGeneration += 1
        let generation = processSampleGeneration
        Task { [weak self] in
            let sampled = await Task.detached(priority: .userInitiated) {
                ProcessSampler.list()
            }.value
            guard let self, self.popupOpen, generation == self.processSampleGeneration else { return }
            self.applyProcesses(sampled)
        }
    }

    private func applyProcesses(_ sampled: [Proc]) {
        processes = sampled
        if let pid = selectedProcessPid, !processes.contains(where: { $0.pid == pid }) {
            selectedProcessPid = nil
            if forceQuitTarget?.pid == pid {
                forceQuitTarget = nil
            }
        }
    }
}
