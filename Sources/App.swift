import AppKit
import SwiftUI

final class BridgeDelegate: NSObject, NSApplicationDelegate {
    weak var model: BridgeModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.busy == true {
            let alert = NSAlert()
            alert.messageText = "Дождись завершения операции"
            alert.informativeText = "Сейчас идёт передача файлов. Не отключай iPhone и закрой приложение после завершения."
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
}

struct BridgeApp: App {
    @NSApplicationDelegateAdaptor(BridgeDelegate.self) var delegate
    @StateObject private var model = BridgeModel()
    var body: some Scene {
        WindowGroup("iPhone Bridge") {
            ContentView(model: model)
                .preferredColorScheme(.light)
                .onAppear {
                    delegate.model = model
                    model.start()
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1160, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Обновить устройства") { model.refresh() }.keyboardShortcut("r").disabled(model.busy)
                Button("Новый перенос") { model.newTransfer() }.keyboardShortcut("n").disabled(model.busy)
                Button("Добавить IPA…") { model.chooseIPA() }.keyboardShortcut("o").disabled(model.busy)
                Button("Открыть архив") { model.revealLibrary() }.keyboardShortcut("l")
            }
        }
    }
}

@main
enum Launcher {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-preview"), args.count > index + 1 {
            renderPreview(to: args[index + 1], section: args.contains("--archive") ? 2 : args.contains("--apps") ? 1 : 0)
        } else { BridgeApp.main() }
    }

    @MainActor static func renderPreview(to path: String, section: Int) {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = BridgeModel(preview: true)
        model.section = section
        if section != 0 {
            // These fixtures are available only in this explicit rendering mode, never in the app.
            let phone = Phone(id: "preview-old-phone", name: "iPhone 14", productType: "iPhone14,7", iosVersion: "26.1", trusted: true)
            model.state.source = phone; model.sourceID = phone.id
            model.account = "example@example.invalid"
            model.state.apps = [
                PhoneApp(bundleID: "com.vk.vkclient", name: "ВКонтакте", version: "8.0", storeID: "", minimumOS: "15.0", placeholder: false),
                PhoneApp(bundleID: "ru.oneme.app", name: "MAX", version: "1.0", storeID: "", minimumOS: "15.0", placeholder: false),
                PhoneApp(bundleID: "preview.sber", name: "СберБанк", version: "16.0", storeID: "", minimumOS: "15.0", placeholder: false)
            ]
            model.selectedApps = Set(model.state.apps.map(\.id))
        }
        let view = NSHostingView(rootView: ContentView(model: model).environment(\.colorScheme, .light))
        let rect = NSRect(x: 0, y: 0, width: 1180, height: 820)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view; view.frame = rect
        window.layoutIfNeeded(); view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let image = view.bitmapImageRepForCachingDisplay(in: rect) else { exit(1) }
        view.cacheDisplay(in: rect, to: image)
        guard let data = image.representation(using: .png, properties: [:]) else { exit(1) }
        do { try data.write(to: URL(fileURLWithPath: path)) } catch { fputs(error.localizedDescription, stderr); exit(1) }
    }
}
