import Foundation

@main enum ServiceTests {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        let tools = URL(fileURLWithPath: args[2], isDirectory: true)
        let fixture = URL(fileURLWithPath: args[3])
        let report = URL(fileURLWithPath: args[4])
        let model = BridgeModel(dataRoot: root, toolsRoot: tools)
        var results: [[String: String]] = []
        let interrupted = BridgeModel.storeError("fetch SAP certificate: store HTTP transport: EOF")
        results.append(["name": "Authentication errors: EOF is reported as an interrupted connection", "status": interrupted.contains("Соединение") && interrupted.contains("прервалось") ? "passed" : "failed"])
        let redirect = BridgeModel.storeError("sign-in request failed: unexpected response from Apple (HTTP 301): authentication redirect is missing Location")
        results.append(["name": "Authentication errors: broken redirect is reported separately from credentials", "status": redirect.contains("HTTP 301") && redirect.contains("не подтверждает ошибку пароля") ? "passed" : "failed"])
        let timeout = BridgeModel.storeError("failed to get bag: context deadline exceeded (Client.Timeout exceeded while awaiting headers)")
        results.append(["name": "Authentication errors: bag timeout is a connection failure", "status": timeout.contains("Не дождались ответа") && timeout.contains("VPN") ? "passed" : "failed"])
        let loginScript = LoginScript.make(binaryPath: root.appendingPathComponent("test's app/ipatool").path)
        let script = root.appendingPathComponent("login.command")
        try loginScript.write(to: script, atomically: true, encoding: .utf8)
        let syntax = try await Commands.run(URL(fileURLWithPath: "/bin/zsh"), ["-n", script.path])
        results.append(["name": "Login launcher: shell-safe paths and visible backend version without password flags", "status": syntax.code == 0 && loginScript.contains("--version") && !loginScript.contains("--password") ? "passed" : "failed"])
        let fake = root.appendingPathComponent("fake-backend")
        let authenticationMarker = root.appendingPathComponent("authentication-started")
        let fakeBody = "#!/bin/zsh\nif [[ $1 == bridge-prepare ]]; then exit 1; fi\nif [[ $1 == auth ]]; then touch " + Files.quote(authenticationMarker.path) + "; fi\nexit 0\n"
        try fakeBody.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        try LoginScript.make(binaryPath: fake.path).write(to: script, atomically: true, encoding: .utf8)
        let stopped = try await Commands.run(URL(fileURLWithPath: "/bin/zsh"), [script.path])
        results.append(["name": "Login launcher: failed component preparation never starts account authentication", "status": stopped.code == 1 && !FileManager.default.fileExists(atPath: authenticationMarker.path) ? "passed" : "failed"])
        let item = try await model.importIPA(fixture, expectedBundle: "test.example.app", origin: "Test", sourceID: "original-phone")
        let archived = model.archiveURL.appendingPathComponent(item.filename)
        results.append(["name": "Archive integration: inspect, copy and hash a real ZIP through the compiled helper", "status": try Files.digest(archived) == item.sha256 ? "passed" : "failed"])
        _ = try await model.importIPA(fixture, origin: "Test", sourceID: "original-phone")
        results.append(["name": "Archive integration: repeated import does not duplicate the library", "status": model.state.archive.count == 1 ? "passed" : "failed"])
        try Data("changed archive".utf8).write(to: archived)
        _ = try await model.importIPA(fixture, origin: "Test", sourceID: "original-phone")
        let changedCopy = try FileManager.default.contentsOfDirectory(at: model.archiveURL, includingPropertiesForKeys: nil).contains { $0.lastPathComponent.contains(".changed-") }
        results.append(["name": "Archive integration: preserve a changed copy and restore the verified original", "status": try Files.digest(archived) == item.sha256 && changedCopy && model.state.archive.count == 1 ? "passed" : "failed"])
        let reloaded = BridgeModel(dataRoot: root, toolsRoot: tools)
        results.append(["name": "Archive integration: restart preserves the originating phone and package metadata", "status": reloaded.state.archive.first?.sourcePhoneID == "original-phone" && reloaded.state.archive.first?.app.bundleID == "test.example.app" ? "passed" : "failed"])
        var rejected = false
        do { _ = try await model.importIPA(fixture, expectedBundle: "wrong.app", origin: "Test", sourceID: nil) } catch { rejected = true }
        results.append(["name": "Archive integration: a response containing another app is rejected", "status": rejected && model.state.archive.count == 1 ? "passed" : "failed"])
        let firstOwner = try await model.importIPA(fixture, origin: "Test", sourceID: "original-phone", appleAccount: "first@example.invalid")
        let sameOwner = try await model.importIPA(fixture, origin: "Test", sourceID: "original-phone", appleAccount: " FIRST@example.invalid ")
        let secondOwner = try await model.importIPA(fixture, origin: "Test", sourceID: "original-phone", appleAccount: "second@example.invalid")
        let anotherSource = try await model.importIPA(fixture, origin: "Test", sourceID: "another-phone", appleAccount: "first@example.invalid")
        results.append(["name": "Archive ownership: identical files retain separate Apple IDs and source phones", "status": firstOwner.id == sameOwner.id && firstOwner.id != secondOwner.id && firstOwner.id != anotherSource.id && model.state.archive.count == 4 && firstOwner.filename == secondOwner.filename ? "passed" : "failed"])
        model.account = "first@example.invalid"
        model.state.lastAccount = model.account
        model.state.source = Phone(id: "original-phone", name: "Test source", productType: "iPhone14,7", iosVersion: "26", trusted: true)
        model.state.apps = [item.app]; model.sourceID = "original-phone"; model.targetID = "test-target"
        model.purchases = [item.app]; model.purchaseTotal = 1; model.showPurchases = true
        model.state.storeOverrides[item.app.bundleID] = "123456789"
        model.selectedApps = [item.app.id]; model.selectedArchives = [firstOwner.id]
        try model.activateAccount("second@example.invalid")
        results.append(["name": "Account switch: clear stale purchases and selections while preserving every archived IPA", "status": model.account == "second@example.invalid" && model.state.archive.count == 4 && model.purchases.isEmpty && model.selectedApps.isEmpty && model.selectedArchives.isEmpty && model.state.storeOverrides.isEmpty && model.state.source?.id == "original-phone" ? "passed" : "failed"])
        try model.clearTransfer()
        let preservedHash = try Files.digest(archived)
        results.append(["name": "New transfer: reset phones and app list while preserving account and files", "status": model.sourceID.isEmpty && model.targetID.isEmpty && model.state.source == nil && model.state.apps.isEmpty && model.account == "second@example.invalid" && model.state.archive.count == 4 && preservedHash == item.sha256 ? "passed" : "failed"])
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model.state)) as! [String: Any]
        legacyJSON.removeValue(forKey: "lastAccount")
        legacyJSON["archive"] = (legacyJSON["archive"] as! [[String: Any]]).map { entry -> [String: Any] in var entry = entry; entry.removeValue(forKey: "appleAccount"); return entry }
        let legacy = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        results.append(["name": "Library migration: archives saved before owner metadata remain readable", "status": legacy.archive.count == 4 && legacy.lastAccount == nil && legacy.archive.allSatisfy { $0.appleAccount == nil } ? "passed" : "failed"])
        let index = root.appendingPathComponent("library.json")
        let corrupt = Data("broken library".utf8)
        try corrupt.write(to: index)
        let broken = BridgeModel(dataRoot: root, toolsRoot: tools)
        rejected = false
        do { try broken.save() } catch { rejected = true }
        let retainedIndex = try Data(contentsOf: index)
        results.append(["name": "Archive integration: an unreadable existing index is never overwritten", "status": rejected && retainedIndex == corrupt ? "passed" : "failed"])
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: report)
        print("Archive integration: \(results.filter { $0["status"] == "passed" }.count)/\(results.count)")
        if results.contains(where: { $0["status"] == "failed" }) { exit(1) }
    }
}
