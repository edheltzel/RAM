import SwiftUI
import AppKit

struct PopupView: View {
    @Environment(Store.self) private var store
    @State private var keyMonitor: Any?

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 10) {
            dashboard
            usageHistory
            details
            processHeader
            processList
            footer
        }
        .padding(12)
        .background {
            WindowAccessor { window in
                store.popoverWindow = window
                window?.makeKey()
            }
        }
        .frame(width: 300)
        .onAppear {
            store.popupAppeared()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                store.handleFilterKey(event)
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
            store.popupDisappeared()
        }
    }

    private var dashboard: some View {
        HStack(spacing: 8) {
            PressureGauge(level: store.memory.pressure)
                .frame(width: 132, height: 78)
            UsageRing(snapshot: store.memory)
                .frame(width: 132, height: 78)
        }
    }

    private var usageHistory: some View {
        VStack(spacing: 6) {
            sectionTitle("USAGE HISTORY")
            UsageHistoryGraph(points: store.history)
                .frame(height: 72)
        }
    }

    private var details: some View {
        let m = store.memory
        let total = max(Double(m.total), 1)
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("DETAILS")
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Color(nsColor: Palette.app).frame(width: geo.size.width * CGFloat(Double(m.app) / total))
                    Color(nsColor: Palette.wired).frame(width: geo.size.width * CGFloat(Double(m.wired) / total))
                    Color(nsColor: Palette.compressed).frame(width: geo.size.width * CGFloat(Double(m.compressed) / total))
                    Color(nsColor: Palette.free).opacity(0.55)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            HStack {
                Text("Used:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormat.memory(m.used))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.system(size: 12))

            detailRow("App", bytes: m.app, color: Palette.app)
            detailRow("Wired", bytes: m.wired, color: Palette.wired)
            detailRow("Compressed", bytes: m.compressed, color: Palette.compressed)
            detailRow("Free", bytes: m.free, color: Palette.free)
            HStack {
                Text("Swap:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormat.swap(m.swap))
                    .monospacedDigit()
            }
            .font(.system(size: 12))
        }
    }

    private func detailRow(_ title: String, bytes: UInt64, color: NSColor) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: color))
                .frame(width: 8, height: 8)
            Text("\(title):")
                .foregroundStyle(.secondary)
            Spacer()
            Text(ByteFormat.memory(bytes))
                .monospacedDigit()
        }
        .font(.system(size: 12))
    }

    private var processHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                sectionTitle("TOP PROCESSES")
                Button {
                    store.cycleView()
                } label: {
                    HStack(spacing: 3) {
                        Text(store.listView.rawValue)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("View cycles App → Process → Nested → Session → Workload")
                .accessibilityLabel("Group by \(store.listView.rawValue)")

                Button {
                    store.toggleFilter()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(store.filterRevealed || !store.filter.isEmpty ? "Hide search" : "Show search")
                .accessibilityLabel(store.filterRevealed || !store.filter.isEmpty ? "Hide search" : "Show search")
            }
            if store.filterRevealed || !store.filter.isEmpty {
                filterField
            }
            HStack {
                Text("Process")
                Spacer()
                Text("Usage")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var filterField: some View {
        @Bindable var store = store
        return FilterSearchField(text: $store.filter)
            .frame(height: 24)
    }

    private var processList: some View {
        VStack(spacing: 0) {
            ForEach(store.rows) { row in
                rowView(row)
            }
            if store.rows.isEmpty {
                Text(store.filter.isEmpty ? "No processes" : "No matches")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .frame(minHeight: 220, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            store.clearSelection()
        }
    }

    private func rowView(_ row: ListRow) -> some View {
        let proc: Proc? = {
            if case .process(let pid) = row.kind {
                return store.processes.first(where: { $0.pid == pid })
                    ?? row.children.first(where: { $0.pid == pid })
                    ?? row.children.first
            }
            return row.children.first
        }()
        let selected: Bool = {
            if case .process(let pid) = row.kind {
                return store.selectedProcessPid == pid
            }
            return false
        }()
        return ProcessRow(
            row: row,
            process: proc,
            selected: selected,
            onToggleExpand: { store.toggleExpanded(row.id) },
            onSelectProcess: { pid in store.selectProcess(pid: pid) },
            onForceQuit: { target in
                store.requestForceQuit(target, window: store.popoverWindow)
            }
        )
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.22))
                .frame(height: 1)

            HStack(spacing: 6) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Open RAM when you log in")
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)

                Button("Activity Monitor") {
                    store.openActivityMonitor()
                }
                .buttonStyle(MenuActionStyle())
                .font(.system(size: 11))
                .help(store.activityMonitorNote ?? "Activity Monitor")
                .lineLimit(1)
                .fixedSize()

                Button("Quit") {
                    store.quit()
                }
                .buttonStyle(MenuActionStyle())
                .font(.system(size: 11))
                .help("Quit")
                .lineLimit(1)
                .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Rectangle().fill(.separator).frame(height: 1)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle().fill(.separator).frame(height: 1)
        }
    }
}

/// Resolves the hosting popover `NSWindow` for sheet presentation.
private struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

/// Real AppKit search field: magnifying glass, placeholder, clear button, focus ring.
private struct FilterSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = "Search"
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.focusRingType = .default
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.stringValue = text
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private struct ProcessRow: View {
    var row: ListRow
    var process: Proc?
    var selected: Bool
    var onToggleExpand: () -> Void
    var onSelectProcess: (Int32) -> Void
    var onForceQuit: (Proc) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if row.expandable {
                Button(action: onToggleExpand) {
                    Image(systemName: row.expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 10)
                }
                .buttonStyle(.plain)
            } else if row.depth > 0 {
                Color.clear.frame(width: 16)
            }

            iconSlot

            HStack(spacing: 6) {
                Text(row.title)
                    .lineLimit(1)
                    .help(row.title)
                Spacer(minLength: 4)
                Text(ByteFormat.memory(row.bytes))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if case .process(let pid) = row.kind {
                    onSelectProcess(pid)
                }
            }
        }
        .font(.system(size: 11))
        .padding(.leading, CGFloat(row.depth) * 10)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Color.primary.opacity(0.10) : (hovering ? Color.primary.opacity(0.06) : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture {
                    if case .process(let pid) = row.kind {
                        onSelectProcess(pid)
                    }
                }
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var iconSlot: some View {
        if selected, case .process = row.kind, let process {
            Button {
                onForceQuit(process)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Force Quit…")
            .accessibilityLabel("Force Quit…")
        } else {
            Group {
                if let process {
                    Image(nsImage: process.rowIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if case .process(let pid) = row.kind {
                    onSelectProcess(pid)
                }
            }
        }
    }
}

/// Menu-item hover / press, per HIG menus-and-actions.
struct MenuActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuActionChrome(configuration: configuration)
    }
}

private struct MenuActionChrome: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(fill)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        if configuration.isPressed {
            return Color.accentColor.opacity(0.28)
        }
        if hovering {
            return Color.primary.opacity(0.08)
        }
        return .clear
    }
}

struct PressureGauge: View {
    var level: PressureLevel

    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                let inset: CGFloat = 8
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset + 4)
                let radius = min(rect.width, rect.height * 2) / 2
                let center = CGPoint(x: rect.midX, y: rect.maxY)
                let colors = [Color.green, Color.orange, Color.red]
                for i in 0..<3 {
                    var path = Path()
                    let start = Angle.degrees(180 + Double(i) * 60)
                    let end = Angle.degrees(180 + Double(i + 1) * 60)
                    path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                    context.stroke(
                        path,
                        with: .color(colors[i].opacity(i == level.segmentIndex ? 1 : 0.35)),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                }
                let needle = 180.0 + Double(level.segmentIndex) * 60.0 + 30.0
                let rad = needle * .pi / 180
                var needlePath = Path()
                needlePath.move(to: center)
                needlePath.addLine(to: CGPoint(
                    x: center.x + cos(rad) * (radius - 6),
                    y: center.y + sin(rad) * (radius - 6)
                ))
                context.stroke(needlePath, with: .color(.primary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            Text(level.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help("Memory pressure")
    }
}

struct UsageRing: View {
    var snapshot: MemorySnapshot

    var body: some View {
        ZStack {
            Canvas { context, size in
                let total = max(Double(snapshot.total), 1)
                let slices: [(Double, Color)] = [
                    (Double(snapshot.app) / total, Color(nsColor: Palette.app)),
                    (Double(snapshot.wired) / total, Color(nsColor: Palette.wired)),
                    (Double(snapshot.compressed) / total, Color(nsColor: Palette.compressed)),
                    (Double(snapshot.free) / total, Color(nsColor: Palette.free).opacity(0.45)),
                ]
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 6)
                let style = StrokeStyle(lineWidth: 9, lineCap: .butt)
                var start = Angle.degrees(-90)
                for (fraction, color) in slices {
                    let sweep = Angle.degrees(360 * max(0, fraction))
                    var path = Path()
                    path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2, startAngle: start, endAngle: start + sweep, clockwise: false)
                    context.stroke(path, with: .color(color), style: style)
                    start += sweep
                }
            }
            VStack(spacing: 0) {
                Text("\(snapshot.usedPercent)%")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                Text("RAM")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .help("Memory usage")
    }
}

struct UsageHistoryGraph: View {
    var points: [HistoryPoint]
    @State private var hoverLocation: CGPoint?
    @State private var pinnedIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let active = pinnedIndex ?? index(at: hoverLocation, width: size.width)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard points.count > 1 else {
                        var baseline = Path()
                        baseline.move(to: CGPoint(x: 0, y: size.height * 0.7))
                        baseline.addLine(to: CGPoint(x: size.width, y: size.height * 0.7))
                        context.stroke(baseline, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 1))
                        return
                    }
                    let line = linePath(size: size)
                    var fill = line
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.addLine(to: CGPoint(x: 0, y: size.height))
                    fill.closeSubpath()
                    context.fill(fill, with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.82, green: 0.68, blue: 0.48).opacity(0.55),
                            Color(red: 0.82, green: 0.68, blue: 0.48).opacity(0.05),
                        ]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    ))
                    context.stroke(
                        line,
                        with: .color(Color(red: 0.72, green: 0.55, blue: 0.32)),
                        style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)
                    )

                    if let active, points.indices.contains(active) {
                        let pt = point(at: active, size: size)
                        var v = Path()
                        v.move(to: CGPoint(x: pt.x, y: 0))
                        v.addLine(to: CGPoint(x: pt.x, y: size.height))
                        var h = Path()
                        h.move(to: CGPoint(x: 0, y: pt.y))
                        h.addLine(to: CGPoint(x: size.width, y: pt.y))
                        let dash = StrokeStyle(lineWidth: 1, dash: [3, 3])
                        context.stroke(v, with: .color(.secondary.opacity(0.7)), style: dash)
                        context.stroke(h, with: .color(.secondary.opacity(0.7)), style: dash)
                        let dot = Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
                        context.fill(dot, with: .color(.red))
                    }
                }

                if let active, points.indices.contains(active) {
                    let pt = point(at: active, size: size)
                    tooltip(points[active])
                        .offset(
                            x: min(max(pt.x - 36, 4), size.width - 92),
                            y: max(pt.y - 40, 4)
                        )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        let idx = index(at: event.location, width: size.width)
                        if pinnedIndex == idx {
                            pinnedIndex = nil
                        } else {
                            pinnedIndex = idx
                        }
                    }
            )
        }
        .padding(6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    private func tooltip(_ point: HistoryPoint) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(point.percent)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
            Text(Self.stamp.string(from: point.sampledAt))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .allowsHitTesting(false)
    }

    private func linePath(size: CGSize) -> Path {
        var path = Path()
        for i in points.indices {
            let pt = point(at: i, size: size)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        return path
    }

    private func point(at index: Int, size: CGSize) -> CGPoint {
        let n = max(points.count - 1, 1)
        let x = CGFloat(index) / CGFloat(n) * size.width
        let y = size.height * (1 - CGFloat(points[index].fraction))
        return CGPoint(x: x, y: y)
    }

    private func index(at location: CGPoint?, width: CGFloat) -> Int? {
        guard let location, points.count > 1, width > 0 else { return points.isEmpty ? nil : points.count - 1 }
        let t = min(max(location.x / width, 0), 1)
        return Int((t * CGFloat(points.count - 1)).rounded())
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "dd/MM HH:mm:ss"
        return f
    }()
}
