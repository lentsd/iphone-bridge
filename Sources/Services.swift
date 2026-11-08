import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct CommandResult {
    var code: Int32
    var text: String
    var objects: [[String: Any]] {
        text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }
    var last: [String: Any] { objects.last ?? [:] }
}

enum Commands {
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 120) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
            var output = Data()
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                // Keep a bounded tail: downloads and framework messages must not exhaust memory.
                output.append(chunk)
                if output.count > 4 * 1024 * 1024 { output.removeFirst(output.count - 2 * 1024 * 1024) }
            }
            process.waitUntilExit()
            watchdog.cancel()
            return CommandResult(code: process.terminationStatus, text: String(decoding: output, as: UTF8.self))
        }.value
    }

    static func decode<T: Decodable>(_ type: T.Type, from object: Any?) throws -> T {
        guard let object else { throw BridgeFailure.message("Не удалось прочитать ответ утилиты.") }
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
}

enum Files {
    static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func archiveID(hash: String, account: String?, sourceID: String?) -> String {
        let scope = (AccountIdentity.normalized(account) ?? "") + "\u{0}" + (sourceID ?? "")
        let suffix = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        return hash + "-" + suffix
    }
}

enum LoginScript {
    static func make(binaryPath: String) -> String {
        let binary = Files.quote(binaryPath)
        return "#!/bin/zsh\n\nprint 'iPhone Bridge 1.6 — вход в Apple ID'\n" + binary + " --version\nexport IPHONE_BRIDGE_PROGRESS=1\nprint 'Сначала проверю компоненты Apple. Пароль на этом этапе не нужен.'\n" + binary + " bridge-prepare\nif [ $? -ne 0 ]; then\n  print '\\nПодготовка не завершена. Вход в Apple ID не начинался.'\n  print 'Исправь соединение и повтори попытку. Проверенные файлы сохраняются.'\n  exit 1\nfi\nprint 'Используй аккаунт, с которого были установлены приложения.'\nprint 'Пароль вводится скрыто. Не передавай его в чат.'\n\n" + binary + " auth login\nresult=$?\nif [ $result -eq 0 ]; then\n  print '\\nГотово. Вернись в iPhone Bridge и нажми «Проверить вход».'\nelse\n  print '\\nВход не завершён. Сообщение об ошибке показано выше.'\n  print 'Если указан timeout / deadline exceeded — нет ответа от Apple; проверь VPN.'\n  print 'Если указано HTTP 301 без Location — сервер авторизации не выдал корректный ответ.'\nfi\nprint '\\nЭто окно можно закрыть.'\n"
    }
}

@MainActor
final class BridgeModel: ObservableObject {
    @Published var section = 0
    @Published var phones: [Phone] = []
    @Published var sourceID = ""
    @Published var targetID = ""
    @Published var state = SavedState()
    @Published var selectedApps = Set<String>()
    @Published var selectedArchives = Set<String>()
    @Published var search = ""
    @Published var onlyPreferred = false
    @Published var busy = false
    @Published var taskTitle = ""
    @Published var status = "Подключи исходный iPhone по кабелю и разблокируй экран."
    @Published var notice: String?
    @Published var account = ""
    @Published var activity: [ActivityEntry] = []
    @Published var appMessages: [String: String] = [:]
    @Published var purchasePage = 1
    @Published var purchaseTotal = 0
    @Published var purchases: [PhoneApp] = []
    @Published var showPurchases = false
    @Published var installConfirmation = false

    let root: URL
    let archiveURL: URL
    let binaryRoot: URL
    let preview: Bool
    private var libraryLoadFailed = false
    private var started = false

    init(preview: Bool = false, dataRoot: URL? = nil, toolsRoot: URL? = nil) {
        self.preview = preview
        let override = ProcessInfo.processInfo.environment["IPHONE_BRIDGE_DATA_DIR"]
        root = dataRoot ?? override.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("iPhone Bridge", isDirectory: true)
        archiveURL = root.appendingPathComponent("Архив", isDirectory: true)
        binaryRoot = toolsRoot ?? (Bundle.main.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).appendingPathComponent("bin", isDirectory: true)
        if preview { return }
        do {
            try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let saved = root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: saved.path) {
                state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: saved))
                sourceID = state.source?.id ?? ""
                selectedApps = Set(state.apps.filter(\.preferred).map(\.id))
            }
        } catch { libraryLoadFailed = true; notice = "Не удалось открыть локальную библиотеку: \(error.localizedDescription). Существующий список не будет перезаписан." }
    }

    var source: Phone? { phones.first { $0.id == sourceID } ?? (state.source?.id == sourceID ? state.source : nil) }
    var sourceConnected: Bool { phones.contains { $0.id == sourceID } }
    var target: Phone? { phones.first { $0.id == targetID } }
    var availableTargets: [Phone] { phones.filter { $0.id != sourceID && $0.id != state.source?.id } }
    var visibleApps: [PhoneApp] {
        let apps = showPurchases ? purchases : state.apps
        return apps.filter { (!onlyPreferred || $0.preferred) && (search.isEmpty || ($0.name + " " + $0.bundleID).localizedCaseInsensitiveContains(search)) }
    }
    var selectedItems: [ArchiveItem] { state.archive.filter { selectedArchives.contains($0.id) } }
    var canInstall: Bool { !busy && target?.trusted == true && !selectedItems.isEmpty && targetID != sourceID && targetID != state.source?.id }
    var storedCount: Int { state.archive.count }

    func resetVolatileAccountState() {
        purchases = []; purchasePage = 1; purchaseTotal = 0; showPurchases = false
        selectedApps = []; selectedArchives = []; appMessages = [:]; search = ""
    }

    func activateAccount(_ email: String) throws {
        guard AccountIdentity.normalized(email) != nil else { throw BridgeFailure.message("Apple ID не определён.") }
        let previous = AccountIdentity.normalized(account) ?? AccountIdentity.normalized(state.lastAccount)
        if previous != nil && previous != AccountIdentity.normalized(email) {
            resetVolatileAccountState()
            state.storeOverrides = [:]
        }
        account = email
        state.lastAccount = email
        try save()
    }

    func currentAccount() async throws -> String {
        let result = try await store(["auth", "info"], timeout: 30)
        guard let entry = result.objects.last(where: { $0["success"] as? Bool == true }),
              let email = entry["email"] as? String, AccountIdentity.normalized(email) != nil else {
            throw BridgeFailure.message("Apple ID ещё не подключён. Заверши вход в Terminal.")
        }
        return email
    }

    func start() {
        guard !started, !preview else { return }
        started = true
        if CommandLine.arguments.contains("--new-transfer") {
            do { try clearTransfer() } catch { notice = error.localizedDescription }
        }
        operation("Проверяю текущий Apple ID на Mac…") {
            do { try self.activateAccount(try await self.currentAccount()) }
            catch { self.account = "" }
        }
    }

    func clearTransfer() throws {
        guard !busy else { throw BridgeFailure.message("Дождись завершения текущей операции.") }
        state.source = nil; state.apps = []; state.storeOverrides = [:]
        sourceID = ""; targetID = ""; resetVolatileAccountState()
        onlyPreferred = false; notice = nil; section = 0
        try save()
        log("Новый перенос. Подключи исходный iPhone и выбери его в списке. Архив сохранён.")
    }

    func newTransfer() {
        guard !busy else { return }
        do { try clearTransfer(); refresh() } catch { notice = error.localizedDescription }
    }

    func log(_ message: String, failed: Bool = false) {
        activity.insert(ActivityEntry(text: message, failed: failed), at: 0)
        if activity.count > 80 { activity.removeLast(activity.count - 80) }
        status = message
    }
    func save() throws {
        guard !libraryLoadFailed else { throw BridgeFailure.message("Существующая библиотека не читается и не будет перезаписана. Сохрани её копию через Finder перед восстановлением.") }
        let data = try JSONEncoder().encode(state)
        let url = root.appendingPathComponent("library.json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func operation(_ title: String, work: @escaping @MainActor () async throws -> Void) {
        guard !busy, !preview else { return }
        busy = true; taskTitle = title
        Task {
            defer { busy = false; taskTitle = "" }
            do { try await work() }
            catch { let text = error.localizedDescription; log(text, failed: true); notice = text }
        }
    }
    func bridge(_ args: [String], timeout: TimeInterval = 120) async throws -> [String: Any] {
        let result = try await Commands.run(binaryRoot.appendingPathComponent("device-bridge"), args, timeout: timeout)
        guard result.code == 0, result.last["ok"] as? Bool == true else {
            throw BridgeFailure.message(result.last["error"] as? String ?? "Связь с iPhone прервалась. Подключи его заново и разблокируй.")
        }
        return result.last
    }
    func store(_ args: [String], timeout: TimeInterval = 120) async throws -> CommandResult {
        let result = try await Commands.run(binaryRoot.appendingPathComponent("ipatool"), ["--format", "json", "--non-interactive"] + args, timeout: timeout)
        guard result.code == 0, !result.objects.contains(where: { $0["error"] != nil || ($0["success"] as? Bool) == false }) else {
            throw BridgeFailure.message(Self.storeError(result.text))
        }
        return result
    }
    static func storeError(_ raw: String) -> String {
        let text = raw.lowercased()
        if text.contains(": eof") || text.contains("unexpected eof") || text.contains("connection interrupted") {
            return "Соединение с сервером Apple прервалось. Проверь VPN и повтори запрос. Такой обрыв не подтверждает отсутствие приложения или неверный пароль."
        }
        if text.contains("authentication redirect is missing location") || text.contains("authentication response") && text.contains("http 301") {
            return "Apple вернула некорректное перенаправление при входе (HTTP 301 без адреса). Это не подтверждает ошибку пароля. Нужен совместимый модуль авторизации или другая рабочая сеть."
        }
        if text.contains("context deadline exceeded") || text.contains("awaiting headers") || text.contains("timeout") || text.contains("timed out") || text.contains("network") || text.contains("no such host") {
            return "Не дождались ответа сервера Apple. Проверь соединение и VPN, затем повтори вход. Результат проверки пароля не получен."
        }
        if text.contains("keyring") || text.contains("keychain") || text.contains("not logged") || text.contains("account not") || text.contains("password token") || text.contains("credentials") || text.contains("password is required") {
            return "Нужен вход в Apple ID. Нажми «Войти», заверши вход в Terminal, затем «Проверить вход»."
        }
        if text.contains("not found") || text.contains("not available") || text.contains("unavailable") || text.contains("not exist") {
            return "Apple не выдала это приложение. Проверь числовой App Store ID; снятые с публикации приложения иногда доступны только по нему. Если файл больше не выдаётся аккаунту, нужен ранее сохранённый IPA."
        }
        if text.contains("license") || text.contains("purchase") && text.contains("required") {
            return "У этого Apple ID нет доступной лицензии приложения. Войди в аккаунт, с которого оно было установлено раньше."
        }
        if text.contains("403") || text.contains("401") { return "Apple отклонила запрос. Повтори вход в Apple ID. Доступность удалённых приложений зависит от серверов Apple." }
        return "Не удалось получить файл у Apple. Проверь вход и App Store ID. Если Apple больше не выдаёт приложение, импортируй ранее сохранённый IPA."
    }

    func refresh() {
        operation("Ищу iPhone по USB…") {
            let response = try await self.bridge(["devices"], timeout: 20)
            self.phones = try Commands.decode([Phone].self, from: response["devices"])
            if !self.phones.contains(where: { $0.id == self.targetID }) { self.targetID = "" }
            self.log(self.phones.isEmpty ? "iPhone пока не найден. Подключи кабель с передачей данных и разблокируй экран." : "Найдено устройств: \(self.phones.count). Выбери исходный и новый iPhone.")
        }
    }
    func readApps() {
        let id = sourceID
        guard let selectedSource = phones.first(where: { $0.id == id }) else { return }
        if state.source?.id != nil && state.source?.id != id && !state.apps.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Прочитать другой исходный iPhone?"
            alert.informativeText = "Сохранённый список приложений заменится списком с \(selectedSource.name). Архив IPA сохранится."
            alert.addButton(withTitle: "Прочитать"); alert.addButton(withTitle: "Отмена")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        operation("Читаю приложения. Подтверди доверие на iPhone…") {
            let response = try await self.bridge(["apps", id])
            self.state.apps = try Commands.decode([PhoneApp].self, from: response["apps"])
            var phone = selectedSource; phone.trusted = true
            self.state.source = phone
            if let index = self.phones.firstIndex(where: { $0.id == id }) { self.phones[index].trusted = true }
            if self.targetID == id { self.targetID = "" }
            self.selectedApps = Set(self.state.apps.filter { $0.preferred && !$0.placeholder }.map(\.id))
            self.selectedArchives = []; self.appMessages = [:]; self.search = ""
            self.onlyPreferred = self.state.apps.contains(where: \.preferred)
            self.showPurchases = false; self.section = 1
            try self.save()
            self.log("Список с \(phone.name) сохранён: \(self.state.apps.count) приложений. Исходный iPhone можно отключить.")
        }
    }
    func pairTarget() {
        let id = targetID
        guard !id.isEmpty else { return }
        operation("Подтверди доверие на новом iPhone…") {
            _ = try await self.bridge(["pair", id])
            if let index = self.phones.firstIndex(where: { $0.id == id }) { self.phones[index].trusted = true }
            self.log("Новый iPhone доверяет этому Mac.")
        }
    }
    func startLogin() {
        guard !busy, !preview else { return }
        do {
            account = ""
            resetVolatileAccountState()
            let path = root.appendingPathComponent("Войти в Apple ID.command")
            let binary = binaryRoot.appendingPathComponent("ipatool").path
            let text = LoginScript.make(binaryPath: binary)
            try text.write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            NSWorkspace.shared.open([path], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { Task { @MainActor in self.notice = "Не удалось открыть Terminal. Открой файл «Войти в Apple ID.command» в папке библиотеки." } }
            }
            log("Открыто окно входа. После входа нажми «Проверить вход».")
        } catch { notice = error.localizedDescription }
    }
    func checkAccount() {
        operation("Проверяю вход в Apple ID…") {
            try self.activateAccount(try await self.currentAccount())
            self.log("Apple ID подтверждён. Проверь адрес в карточке аккаунта перед скачиванием.")
        }
    }
    func loadPurchases(page: Int = 1) {
        operation("Читаю историю Apple ID, страница \(page)…") {
            let result = try await self.store(["list-purchases", "--page", String(page), "--max-results", "100"], timeout: 300)
            guard let entry = result.objects.last(where: { $0["apps"] != nil }), let apps = entry["apps"] as? [[String: Any]] else {
                throw BridgeFailure.message("Apple не вернула список покупок.")
            }
            self.purchaseTotal = entry["totalCount"] as? Int ?? apps.count
            self.purchasePage = page
            self.purchases = apps.compactMap { record in
                guard let bundle = record["bundleID"] as? String, !bundle.isEmpty else { return nil }
                let storeID = (record["id"] as? NSNumber)?.stringValue ?? (record["id"] as? String ?? "")
                return PhoneApp(bundleID: bundle, name: record["name"] as? String ?? bundle, version: record["version"] as? String ?? "", storeID: storeID, minimumOS: "", placeholder: false)
            }
            for app in self.purchases where !app.storeID.isEmpty { self.state.storeOverrides[app.bundleID] = app.storeID }
            try self.save()
            self.showPurchases = true; self.onlyPreferred = false; self.search = ""; self.section = 1
            self.selectedApps = Set(self.purchases.filter(\.preferred).map(\.id))
            self.log("Загружена страница \(page) истории Apple ID. Всего записей: \(self.purchaseTotal).")
        }
    }
    func updateStoreID(_ app: PhoneApp, text: String) {
        guard let id = StoreIdentifier.parse(text) else { notice = "Введи числовой App Store ID или ссылку https://apps.apple.com/…/id123456789."; return }
        state.storeOverrides[app.bundleID] = id
        do { try save(); log("App Store ID сохранён для \(app.name).") } catch { notice = error.localizedDescription }
    }
    func downloadSelected() {
        let pool = showPurchases ? purchases : state.apps
        let apps = pool.filter { selectedApps.contains($0.id) }
        guard !apps.isEmpty else { return }
        let expectedAccount = account
        operation("Запрашиваю приложения у Apple…") {
            guard let expected = AccountIdentity.normalized(expectedAccount) else { throw BridgeFailure.message("Сначала нажми «Проверить вход» и проверь Apple ID.") }
            let actual = try await self.currentAccount()
            guard AccountIdentity.normalized(actual) == expected else {
                try self.activateAccount(actual)
                throw BridgeFailure.message("Apple ID на Mac изменился. Проверь адрес в карточке аккаунта и заново выбери приложения.")
            }
            var complete = 0
            for (index, app) in apps.enumerated() {
                self.taskTitle = "\(index + 1)/\(apps.count) · Сохраняю \(app.name)…"
                self.appMessages[app.id] = "Скачивается…"
                let temporary = self.root.appendingPathComponent("download-\(UUID().uuidString).ipa")
                do {
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let id = self.state.storeOverrides[app.bundleID] ?? app.storeID
                    var args = ["download", "--platform", "iphone", "--output", temporary.path]
                    if let storeID = StoreIdentifier.parse(id) { args += ["--app-id", storeID] }
                    else { args += ["--bundle-identifier", app.bundleID] }
                    // Never acquire a license or purchase an app automatically.
                    _ = try await self.store(args, timeout: 1200)
                    let item = try await self.importIPA(temporary, expectedBundle: app.bundleID, origin: "Apple", sourceID: self.state.source?.id, appleAccount: actual)
                    self.selectedArchives.insert(item.id)
                    self.appMessages[app.id] = "В архиве · \(item.app.version)"; complete += 1
                    self.log("\(app.name) сохранено в архив. Версия из Apple: \(item.app.version).")
                } catch {
                    self.appMessages[app.id] = "Не получено"
                    self.log("\(app.name): \(error.localizedDescription)", failed: true)
                    self.notice = "\(app.name): \(error.localizedDescription)"
                }
            }
            if complete > 0 { self.section = 2 }
            self.log("Сохранено приложений: \(complete) из \(apps.count). Результаты остальных — в журнале.")
        }
    }
    func importIPA(_ url: URL, expectedBundle: String? = nil, origin: String, sourceID: String?, appleAccount: String? = nil) async throws -> ArchiveItem {
        let response = try await bridge(["ipa-info", url.path])
        let app = try Commands.decode(PhoneApp.self, from: response["app"])
        guard expectedBundle == nil || app.bundleID == expectedBundle else { throw BridgeFailure.message("Apple вернула другое приложение. Файл не добавлен в архив.") }
        let hash = try await Task.detached { try Files.digest(url) }.value
        let filename = "\(app.bundleID)-\(hash.prefix(16)).ipa"
        let destination = archiveURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            let archivedHash = try await Task.detached { try Files.digest(destination) }.value
            if archivedHash == hash {
                if let existing = state.archive.first(where: { $0.sha256 == hash && $0.sourcePhoneID == sourceID && AccountIdentity.normalized($0.appleAccount) == AccountIdentity.normalized(appleAccount) }) { return existing }
            } else {
                let quarantine = destination.appendingPathExtension("changed-\(UUID().uuidString)")
                try FileManager.default.moveItem(at: destination, to: quarantine)
            }
        }
        let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        try await Task.detached {
            if !FileManager.default.fileExists(atPath: destination.path) {
                let staged = destination.appendingPathExtension("partial")
                defer { try? FileManager.default.removeItem(at: staged) }
                try FileManager.default.copyItem(at: url, to: staged)
                guard try Files.digest(staged) == hash else { throw BridgeFailure.message("Файл изменился во время копирования. Повтори импорт.") }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
                try FileManager.default.moveItem(at: staged, to: destination)
            }
        }.value
        let item = ArchiveItem(id: Files.archiveID(hash: hash, account: appleAccount, sourceID: sourceID), app: app, filename: filename, sha256: hash, bytes: bytes, createdAt: Date(), origin: origin, sourcePhoneID: sourceID, appleAccount: appleAccount)
        state.archive.removeAll { $0.id == item.id }
        state.archive.insert(item, at: 0)
        try save()
        return item
    }
    func chooseIPA() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Добавить сохранённые установочные файлы"
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? .archive]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        operation("Проверяю и добавляю IPA…") {
            for url in urls {
                do {
                    let item = try await self.importIPA(url, origin: "Импорт", sourceID: nil)
                    self.selectedArchives.insert(item.id)
                    self.log("\(item.app.name) добавлено в архив.")
                } catch { self.log("\(url.lastPathComponent): \(error.localizedDescription)", failed: true); self.notice = error.localizedDescription }
            }
            self.section = 2
        }
    }
    func installSelected() {
        guard canInstall, let phone = target else { return }
        let items = selectedItems
        let source = state.source?.id ?? sourceID
        let target = phone.id
        operation("Устанавливаю на \(phone.name). Не отключай кабель…") {
            var complete = 0
            for (index, item) in items.enumerated() {
                self.taskTitle = "\(index + 1)/\(items.count) · \(item.app.name) → \(phone.name). Не отключай кабель."
                do {
                    let url = self.archiveURL.appendingPathComponent(item.filename)
                    let hash = try await Task.detached { try Files.digest(url) }.value
                    try InstallPolicy.validate(sourceID: source, targetID: target, archivePath: url, item: item, hash: hash)
                    let response = try await self.bridge(["install", target, url.path, item.app.bundleID, source], timeout: 900)
                    if response["alreadyInstalled"] as? Bool == true {
                        self.log("\(item.app.name) уже есть на \(phone.name). Установленная копия сохранена.")
                    } else { complete += 1; self.log("\(item.app.name) установлено на \(phone.name). Открой приложение и проверь вход.") }
                } catch { self.log("\(item.app.name): \(error.localizedDescription)", failed: true); self.notice = error.localizedDescription }
            }
            self.log("Установка завершена. Новых приложений: \(complete) из \(items.count). Подробности — в журнале.")
        }
    }
    func revealLibrary() { NSWorkspace.shared.open(archiveURL) }
    func revealInstructions() {
        if let url = Bundle.main.url(forResource: "Инструкция", withExtension: "md") { NSWorkspace.shared.open(url) }
    }
    func exportIPA(_ item: ArchiveItem) {
        guard !busy else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(item.app.name)-\(item.app.version).ipa".replacingOccurrences(of: "/", with: "-")
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? .archive]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        operation("Экспортирую IPA…") {
            let source = self.archiveURL.appendingPathComponent(item.filename)
            let data = try await Task.detached { try Data(contentsOf: source, options: .mappedIfSafe) }.value
            try data.write(to: url, options: .atomic)
            self.log("\(item.app.name): IPA экспортирован.")
        }
    }
}
