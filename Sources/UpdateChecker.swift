import AppKit

/// Checks GitHub's public "latest release" endpoint for a newer version.
/// This is the app's only network request. It sends no user data, and runs at most once per day
/// (or when the user picks "Check for Updates…").
final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    private let latestURL = URL(string: "https://api.github.com/repos/VishalT25/QuickOCR/releases/latest")!
    private let lastCheckKey = "lastUpdateCheck"

    /// Set when a newer release is found; the menu shows an item while this is non-nil.
    private(set) var available: (version: String, url: URL)?
    var onChange: (() -> Void)?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func checkIfDue() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        Task { await check(userInitiated: false) }
    }

    @MainActor
    func check(userInitiated: Bool) async {
        var req = URLRequest(url: latestURL, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("QuickOCR", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else {
            if userInitiated { alert("Couldn't check for updates", "Please check your connection and try again.") }
            return
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        if latest.compare(currentVersion, options: .numeric) == .orderedDescending {
            available = (latest, page)
            onChange?()
            if userInitiated { NSWorkspace.shared.open(page) }
        } else {
            available = nil
            onChange?()
            if userInitiated { alert("You're up to date", "QuickOCR \(currentVersion) is the latest version.") }
        }
    }

    @MainActor
    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
