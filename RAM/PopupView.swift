import SwiftUI
import AppKit

struct PopupView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 10) {
            dashboard
            sparkline
            details
            processHeader
            processList
            footer
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { store.popupAppeared() }
        .onDisappear { store.popupDisappeared() }
        .confirmationDialog(
            forceQuitTitle,
            isPresented: Binding(
                get: { store.forceQuitTarget != nil },
                set: { if !$0 { store.forceQuitTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Force Quit", role: .destructive) {
                store.performForceQuit()
            }
            Button("Cancel", role: .cancel) {
                store.forceQuitTarget = nil
            }
        } message: {
            Text("This immediately kills the process. Unsaved work in that process is lost.")
        }
    }

    private var forceQuitTitle: String {
        guard let proc = store.forceQuitTarget else { return "Force Quit?" }
        return "Force Quit \(proc.displayName) (\(proc.pid))?"
    }

    private var dashboard: some View {
        HStack(spacing: 8) {
            PressureGauge(level: store.memory.pressure)
                .frame(width: 132, height: 78)
            UsageRing(snapshot: store.memory)
                .frame(width: 132, height: 78)
        }
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage history")
                .font(.caption)
                .foregroundStyle(.secondary)
            Sparkline(values: store.history, color: Color(nsColor: .controlAccentColor))
                .frame(height: 56)
                .padding(.horizontal, 4)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var details: some View {
        let m = store.memory
        return VStack(spacing: 3) {
            detailRow("App", bytes: m.app, color: Palette.app)
            detailRow("Wired", bytes: m.wired, color: Palette.wired)
            detailRow("Compressed", bytes: m.compressed, color: Palette.compressed)
            detailRow("Free", bytes: m.free, color: Palette.free)
        }
    }

    private func detailRow(_ title: String, bytes: UInt64, color: NSColor) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: color))
                .frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(ByteFormat.memory(bytes))
                .monospacedDigit()
        }
        .font(.system(size: 12))
    }

    private var processHeader: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Top processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(store.listView.rawValue) {
                    store.cycleView()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("View cycles App → Process → Nested → Session → Workload")
            }
            TextField("Filter", text: $store.filter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
        }
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
    }

    private func rowView(_ row: ListRow) -> some View {
        HStack(spacing: 6) {
            if row.expandable {
                Button {
                    store.toggleExpanded(row.id)
                } label: {
                    Image(systemName: row.expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 10)
                }
                .buttonStyle(.plain)
            } else if row.depth > 0 {
                Color.clear.frame(width: 16)
            }
            Text(row.title)
                .lineLimit(1)
                .help(row.title)
            Spacer(minLength: 4)
            Text(ByteFormat.memory(row.bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if case .process(let pid) = row.kind, let proc = row.children.first(where: { $0.pid == pid }) ?? row.children.first {
                Button("Force Quit") {
                    store.confirmForceQuit(proc)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .foregroundStyle(.red)
            }
        }
        .font(.system(size: 11))
        .padding(.leading, CGFloat(row.depth) * 10)
        .padding(.vertical, 3)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note = store.activityMonitorNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Launch at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            HStack {
                Button("Activity Monitor") {
                    store.openActivityMonitor()
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit RAM") {
                    store.quit()
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 12))
        }
        .padding(.top, 4)
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

struct Sparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maxV = max(values.max() ?? 1, 0.01)
            let step = size.width / CGFloat(max(values.count - 1, 1))
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - CGFloat(v / maxV) * size.height
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .padding(6)
    }
}
