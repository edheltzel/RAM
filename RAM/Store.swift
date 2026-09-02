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
    var forceQuitTarget: Proc?
    var selectedProcessPid: Int32?
    var launchAtLogin = LaunchAtLogin.isEnabled

    @ObservationIgnored
    weak var popoverWindow: NSWindow?

    private var chipTimer: Timer?
    private var popupTimer: Timer?
    private var extraWindowObservers: [NSObjectProtocol] = []
    private let historyCap = 60

    init() {
        if let raw = UserDefaults.standard.string(forKey: "ram.listView"),
           let saved = ListView(rawValue: raw) {
            listView = saved
        }
        if UserDefaults.standard.object(forKey: "ram.sortDescending") != nil {
            sortDescending = UserDefaults.standard.bool(forKey: "ram.sortDescending")
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
            filterRevealed = false
            expanded = []
            activityMonitorNote = nil
            forceQuitTarget = nil
            selectedProcessPid = nil
        }
        refreshMemory()
        refreshProcesses()
        startPopupTimer()
        popoverWindow?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
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
        filterRevealed = false
        processes = []
        // Keep popoverWindow so becomeKey can restart sampling if SwiftUI skips onAppear.
    }

    /// MenuBarExtra .window often keeps PopupView mounted after dismiss (onDisappear never fires)
    /// and can skip onAppear on the next click. Drive open/closed from the extra window itself.
    func noteExtraWindow(_ window: NSWindow?) {
        guard let window else { return }
        bindExtraWindow(window)
        if window.isVisible {
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
    }

    func cycleView() {
        listView = listView.next
        expanded = []
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
    }

    func setLaunchAtLogin(_ on: Bool) {
        LaunchAtLogin.setEnabled(on)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func openActivityMonitor() {
        activityMonitorNote = ActivityMonitorOpener.open()
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
        NSRunningApplication(processIdentifier: proc.pid)?.forceTerminate()
        kill(proc.pid, SIGKILL)
        forceQuitTarget = nil
        selectedProcessPid = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if Self.isRunning(proc.pid) {
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
    func handleFilterKey(_ event: NSEvent) -> NSEvent? {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            return event
        }
        // Sheet owns keys while Force Quit is up. Do not treat Return as confirm.
        if forceQuitTarget != nil {
            return event
        }
        if event.keyCode == 53 { // escape
            if !filter.isEmpty || filterRevealed {
                filter = ""
                filterRevealed = false
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
                self.refreshProcesses()
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

    private func refreshProcesses() {
        processes = ProcessSampler.list()
        if let pid = selectedProcessPid, !processes.contains(where: { $0.pid == pid }) {
            selectedProcessPid = nil
            if forceQuitTarget?.pid == pid {
                forceQuitTarget = nil
            }
        }
    }
}
