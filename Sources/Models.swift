import Foundation

struct Phone: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var productType: String
    var iosVersion: String
    var trusted: Bool
    var error: String?

    var model: String {
        ["iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
         "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
         "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
         "iPhone18,3": "iPhone 17"][productType] ?? (productType.isEmpty ? "iPhone" : productType)
    }
}

struct PhoneApp: Codable, Identifiable, Equatable {
    var bundleID: String
    var name: String
    var version: String
    var storeID: String
    var minimumOS: String
    var placeholder: Bool
    var id: String { bundleID }

    var category: String {
        let text = (name + " " + bundleID).lowercased()
        if text.contains("sber") || text.contains("сбер") || text.contains("sbol") { return "Сбер" }
        if text.contains("oneme") || text.contains("max-messenger") || name.lowercased() == "max" || name.lowercased() == "макс" { return "MAX" }
        if text.contains("vkcom") || text.contains("vkontakte") || text.contains("вконтакте") || name.lowercased() == "vk" { return "VK" }
        return "Другое"
    }
    var preferred: Bool { category != "Другое" }
    var monogram: String { preferred ? (category == "Сбер" ? "С" : category) : String(name.prefix(1)).uppercased() }
}

struct ArchiveItem: Codable, Identifiable, Equatable {
    var id: String
    var app: PhoneApp
    var filename: String
    var sha256: String
    var bytes: Int64
    var createdAt: Date
    var origin: String
    var sourcePhoneID: String?
    var appleAccount: String? = nil
}

struct SavedState: Codable {
    var source: Phone?
    var apps: [PhoneApp] = []
    var storeOverrides: [String: String] = [:]
    var archive: [ArchiveItem] = []
    var lastAccount: String? = nil
}

enum AccountIdentity {
    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.isEmpty ? nil : text
    }
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    var date = Date()
    var text: String
    var failed = false
}

enum BridgeFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

enum StoreIdentifier {
    static func parse(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^[0-9]{1,18}$"#, options: .regularExpression) != nil, UInt64(text) ?? 0 > 0 { return text }
        guard let url = URL(string: text), url.scheme == "https", url.host?.lowercased() == "apps.apple.com",
              let match = url.path.range(of: #"/id([0-9]{1,18})(?:/|$)"#, options: .regularExpression) else { return nil }
        let part = String(url.path[match]).replacingOccurrences(of: "/id", with: "").replacingOccurrences(of: "/", with: "")
        return UInt64(part) ?? 0 > 0 ? part : nil
    }
}

enum InstallPolicy {
    static func validate(sourceID: String?, targetID: String, archivePath: URL, item: ArchiveItem, hash: String) throws {
        guard !targetID.isEmpty else { throw BridgeFailure.message("Выбери новый iPhone.") }
        guard sourceID != targetID, item.sourcePhoneID != targetID else { throw BridgeFailure.message("Исходный и новый iPhone совпадают. Выбери другой телефон.") }
        guard archivePath.lastPathComponent == item.filename, !item.filename.contains("/"), !item.filename.contains("..") else { throw BridgeFailure.message("Некорректный путь к IPA.") }
        guard hash == item.sha256 else { throw BridgeFailure.message("IPA изменился после сохранения. Импортируй исходный файл заново.") }
    }
}
