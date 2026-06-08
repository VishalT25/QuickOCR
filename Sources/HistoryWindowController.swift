import AppKit
import SwiftUI

// MARK: - Window controller

final class HistoryWindowController: NSWindowController {
    static let shared = HistoryWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "OCR History"
        win.titlebarAppearsTransparent = false
        win.minSize = NSSize(width: 420, height: 320)
        win.contentView = NSHostingView(rootView: HistoryView())
        win.center()
        super.init(window: win)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if window?.isVisible == true {
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.center()
            window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root view

private struct HistoryView: View {
    @ObservedObject private var manager = HistoryManager.shared
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if manager.items.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .background(.background)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("OCR History")
                    .font(.system(size: 15, weight: .semibold))
                if !manager.items.isEmpty {
                    Text("\(manager.items.count) capture\(manager.items.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !manager.items.isEmpty {
                Button {
                    showClearConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .alert("Clear All History?", isPresented: $showClearConfirm) {
                    Button("Clear All", role: .destructive) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            HistoryManager.shared.clear()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently remove all \(manager.items.count) capture\(manager.items.count == 1 ? "" : "s").")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            VStack(spacing: 5) {
                Text("No Captures Yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Use the shortcut to capture text from your screen")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Entry list grouped by date

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groupedEntries()) { group in
                    Section {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { idx, entry in
                            HistoryRow(entry: entry, isToday: group.isToday)
                            if idx < group.entries.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    } header: {
                        groupHeader(group.label)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: manager.items.map(\.id))
    }

    private func groupHeader(_ label: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(.background)
    }

    // MARK: Grouping

    private func groupedEntries() -> [DateGroup] {
        let cal = Calendar.current
        let now  = Date()
        var today:     [HistoryEntry] = []
        var yesterday: [HistoryEntry] = []
        var thisWeek:  [HistoryEntry] = []
        var older:     [HistoryEntry] = []

        for entry in manager.items {
            if cal.isDateInToday(entry.date)     { today.append(entry) }
            else if cal.isDateInYesterday(entry.date) { yesterday.append(entry) }
            else if now.timeIntervalSince(entry.date) < 7 * 86400 { thisWeek.append(entry) }
            else { older.append(entry) }
        }

        return [
            today.isEmpty     ? nil : DateGroup(label: "Today",             entries: today,     isToday: true),
            yesterday.isEmpty ? nil : DateGroup(label: "Yesterday",         entries: yesterday, isToday: false),
            thisWeek.isEmpty  ? nil : DateGroup(label: "Earlier This Week", entries: thisWeek,  isToday: false),
            older.isEmpty     ? nil : DateGroup(label: "Older",             entries: older,     isToday: false),
        ].compactMap { $0 }
    }
}

// MARK: - Date group model

private struct DateGroup: Identifiable {
    let id   = UUID()
    let label: String
    let entries: [HistoryEntry]
    let isToday: Bool
}

// MARK: - Entry row

private struct HistoryRow: View {
    let entry: HistoryEntry
    let isToday: Bool

    @State private var hovered    = false
    @State private var justCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {

            // Text content
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                // Metadata row: word count + timestamp, or "Copied!" flash
                HStack(spacing: 6) {
                    if justCopied {
                        Label("Copied", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    } else {
                        let wc = wordCount(entry.text)
                        Text("\(wc) \(wc == 1 ? "word" : "words")")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                        Text(timestamp(entry.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: justCopied)
            }

            Spacer(minLength: 0)

            // Action buttons — fade in on hover
            HStack(spacing: 2) {
                IconButton(systemName: "doc.on.doc", help: "Copy to clipboard") {
                    copyEntry()
                }
                IconButton(systemName: "trash", help: "Delete") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        HistoryManager.shared.remove(id: entry.id)
                    }
                }
            }
            .opacity(hovered ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Group {
                if justCopied {
                    Color.green.opacity(0.07)
                } else if hovered {
                    Color.primary.opacity(0.04)
                } else {
                    Color.clear
                }
            }
        )
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.15), value: justCopied)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { copyEntry() }
        .transition(.asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .move(edge: .trailing))
        ))
    }

    private func copyEntry() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        withAnimation { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { justCopied = false }
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func timestamp(_ date: Date) -> String {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        if isToday { return timeFmt.string(from: date) }

        let dateFmt = DateFormatter()
        let sameYear = Calendar.current.component(.year, from: date)
                    == Calendar.current.component(.year, from: Date())
        dateFmt.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return "\(dateFmt.string(from: date)) · \(timeFmt.string(from: date))"
    }
}

// MARK: - Reusable icon button

private struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    hovered ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
    }
}
