import Foundation
import AppKit
import Darwin
import Observation

@MainActor
@Observable
final class Store {
    var memory: MemorySnapshot = .empty
    var history: [Double] = []
    var processes: [Proc] = []
    var popupOpen = false
    var listView: ListView = .process
    var filter = ""
    var expanded: Set<String> = []
    var activityMonitorNote: String?
    var forceQuitTarget: Proc?
    var launchAtLogin = LaunchAtLogin.isEnabled

    private var chipTimer: Timer?
    private var popupTimer: Timer?
    private let historyCap = 60

    init() {
        refreshMemory()
        startChipTimer()
        LaunchAtLogin.applyDefault()
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func popupAppeared() {
        popupOpen = true
        listView = .process
        filter = ""
        expanded = []
        activityMonitorNote = nil
        refreshMemory()
        refreshProcesses()
        startPopupTimer()
    }

    func popupDisappeared() {
        popupOpen = false
        popupTimer?.invalidate()
        popupTimer = nil
    }

    func cycleView() {
        listView = listView.next
        expanded = []
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

    func confirmForceQuit(_ proc: Proc) {
        forceQuitTarget = proc
    }

    func performForceQuit() {
        guard let proc = forceQuitTarget else { return }
        kill(proc.pid, SIGKILL)
        forceQuitTarget = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshProcesses()
            self?.refreshMemory()
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    var rows: [ListRow] {
        Grouping.rows(view: listView, processes: processes, filter: filter, expanded: expanded)
    }

    private func startChipTimer() {
        chipTimer?.invalidate()
        chipTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMemory()
            }
        }
        chipTimer?.tolerance = 1
    }

    private func startPopupTimer() {
        popupTimer?.invalidate()
        popupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popupOpen else { return }
                self.refreshMemory()
                self.refreshProcesses()
            }
        }
        popupTimer?.tolerance = 0.2
    }

    private func refreshMemory() {
        let snap = MemorySampler.snapshot()
        memory = snap
        history.append(snap.usedFraction)
        if history.count > historyCap {
            history.removeFirst(history.count - historyCap)
        }
    }

    private func refreshProcesses() {
        processes = ProcessSampler.list()
    }
}
