import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date

    init(text: String) {
        id   = UUID()
        self.text = text
        date = Date()
    }
}

final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var items: [HistoryEntry] = []
    private let maxItems = 200
    private let key = "captureHistory"

    // AppKit menu is not SwiftUI — notify it via callback
    var onChanged: (() -> Void)?

    private init() { load() }

    func add(text: String) {
        items.insert(HistoryEntry(text: text), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        save()
        onChanged?()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
        onChanged?()
    }

    func clear() {
        items = []
        save()
        onChanged?()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        items = entries
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
