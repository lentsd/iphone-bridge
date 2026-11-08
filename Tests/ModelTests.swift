import Foundation

@main enum ModelTests {
    static func main() throws {
        var results: [[String: String]] = []
        func test(_ name: String, _ body: () throws -> Bool) {
            do {
                let passed = try body()
                results.append(["name": name, "status": passed ? "passed" : "failed"])
            } catch { results.append(["name": name, "status": "failed", "message": error.localizedDescription]) }
        }
        func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
        test("App Store URLs: numeric ID, Russian slug and tracking query") {
            StoreIdentifier.parse("123456789") == "123456789" &&
            StoreIdentifier.parse("https://apps.apple.com/ru/app/тест/id123456789?ref=test") == "123456789"
        }
        test("App Store URLs: reject lookalike domains, zero, shell input and overflow") {
            ["https://apps.apple.com.attacker.example/id123456789", "https://attacker.example/id123456789", "0", "123; touch /tmp/no", "$(id)", "https://apps.apple.com/ru/app/id0", "99999999999999999999999"].allSatisfy { StoreIdentifier.parse($0) == nil }
        }
        let app = PhoneApp(bundleID: "example.app", name: "Example", version: "1", storeID: "", minimumOS: "16", placeholder: false)
        let item = ArchiveItem(id: "hash", app: app, filename: "example.ipa", sha256: "correcthash", bytes: 100, createdAt: Date(), origin: "Test", sourcePhoneID: "old-phone")
        let path = URL(fileURLWithPath: "/tmp/archive/example.ipa")
        test("Install policy: allow a verified package on another phone") {
            try InstallPolicy.validate(sourceID: "old-phone", targetID: "new-phone", archivePath: path, item: item, hash: "correcthash")
            return true
        }
        test("Install policy: block source phone even if current picker changed") {
            rejects { try InstallPolicy.validate(sourceID: "other-phone", targetID: "old-phone", archivePath: path, item: item, hash: "correcthash") }
        }
        test("Install policy: block empty target and changed archive") {
            rejects { try InstallPolicy.validate(sourceID: "old-phone", targetID: "", archivePath: path, item: item, hash: "correcthash") } &&
            rejects { try InstallPolicy.validate(sourceID: "old-phone", targetID: "new-phone", archivePath: path, item: item, hash: "modifiedhash") }
        }
        test("Install policy: reject filename traversal") {
            var unsafe = item; unsafe.filename = "../example.ipa"
            return rejects { try InstallPolicy.validate(sourceID: "old-phone", targetID: "new-phone", archivePath: path, item: unsafe, hash: "correcthash") }
        }
        test("Library: preserve Unicode names and original source after restart") {
            var state = SavedState()
            state.apps = [app]; state.archive = [item]
            state.storeOverrides = [app.bundleID: "123456789"]
            let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
            return restored.archive[0].sourcePhoneID == "old-phone" && restored.storeOverrides == state.storeOverrides && restored.apps == state.apps
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Model checks: \(results.filter { $0["status"] == "passed" }.count)/\(results.count)")
        if results.contains(where: { $0["status"] != "passed" }) { exit(1) }
    }
}
