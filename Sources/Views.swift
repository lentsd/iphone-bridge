import AppKit
import SwiftUI

enum Palette {
    static let ink = Color(red: 0.12, green: 0.15, blue: 0.19)
    static let muted = Color(red: 0.43, green: 0.46, blue: 0.49)
    static let orange = Color(red: 0.89, green: 0.31, blue: 0.15)
    static let canvas = Color(red: 0.965, green: 0.963, blue: 0.950)
    static let line = Color.black.opacity(0.075)
    static let green = Color(red: 0.13, green: 0.49, blue: 0.32)
}

struct FilledButton: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 17).padding(.vertical, 11)
            .foregroundStyle(prominent ? .white : Palette.ink)
            .background(prominent ? Palette.orange : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(prominent ? .clear : Palette.line))
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
    }
}

struct ContentView: View {
    @ObservedObject var model: BridgeModel
    @State private var editingApp: PhoneApp?
    @State private var activityOpen = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        if let notice = model.notice { noticeView(notice) }
                        if model.section == 0 { connection }
                        else if model.section == 1 { applications }
                        else if model.section == 2 { archive }
                        else { help }
                        if !model.activity.isEmpty { activity }
                    }.padding(32)
                }
                footer
            }.background(Palette.canvas)
        }
        .foregroundStyle(Palette.ink)
        .font(.system(size: 13))
        .tint(Palette.orange)
        .frame(minWidth: 1040, minHeight: 740)
        .sheet(item: $editingApp) { app in AppIDEditor(app: app, current: model.state.storeOverrides[app.bundleID] ?? app.storeID) { model.updateStoreID(app, text: $0) } }
        .alert("Установить на новый iPhone?", isPresented: $model.installConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Установить") { model.installSelected() }
        } message: {
            Text("Получатель: \(model.target?.name ?? ""), \(model.target?.model ?? ""), ID …\(model.targetID.suffix(6)).\n\nПриложения: \(model.selectedItems.map { $0.app.name }.joined(separator: ", ")).\n\nУже установленные копии будут пропущены. Данные и вход в аккаунты не переносятся. Не отключай кабель до завершения.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white).frame(width: 38, height: 38).background(Palette.orange, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhone").font(.system(size: 18, weight: .bold))
                    Text("BRIDGE").font(.system(size: 10, weight: .bold)).tracking(3).foregroundStyle(Palette.muted)
                }
            }.padding(.top, 35).padding(.bottom, 41).padding(.leading, 24)
            Text("ПЕРЕНОС ПРИЛОЖЕНИЙ").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted).padding(.leading, 25).padding(.bottom, 15)
            nav(0, "Подключение", "cable.connector", "01")
            nav(1, "Приложения", "square.grid.2x2", "02")
            nav(2, "Архив .ipa", "archivebox", "03")
            Spacer()
            Button { model.section = 3 } label: {
                Label("Как это работает", systemImage: "questionmark.circle").foregroundStyle(model.section == 3 ? Palette.orange : Palette.muted)
            }.buttonStyle(.plain).padding(.horizontal, 25).padding(.bottom, 25)
            Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 7) {
                Label("Твой личный архив", systemImage: "internaldrive").font(.system(size: 11, weight: .semibold))
                Text("Файлы остаются на Mac.\nЗагрузка — с серверов Apple.").font(.system(size: 10)).lineSpacing(3).foregroundStyle(Palette.muted)
                Text("v1.6 · Apple silicon").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.7)).padding(.top, 8)
            }.padding(24)
        }.frame(width: 210).background(.white)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }
    private func nav(_ section: Int, _ title: String, _ icon: String, _ index: String) -> some View {
        Button { model.section = section } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 15)).frame(width: 21)
                Text(title).font(.system(size: 12, weight: model.section == section ? .semibold : .medium))
                Spacer()
                Text(index).font(.system(size: 10, design: .monospaced)).opacity(0.6)
            }.foregroundStyle(model.section == section ? Palette.orange : Palette.muted)
                .padding(.horizontal, 13).padding(.vertical, 13)
                .background(model.section == section ? Palette.orange.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 5)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Palette.orange).frame(width: 5, height: 5)
                    Text("СО СТАРОГО — НА НОВЫЙ").font(.system(size: 9, weight: .bold)).tracking(1.8)
                }.foregroundStyle(Palette.muted)
                Spacer()
                Label("По кабелю", systemImage: "cable.connector").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.section == 0 ? "Приложения остаются с тобой." : model.section == 1 ? "Сохрани то, что нужно." : model.section == 2 ? "Готовы к новому iPhone." : "Перенос без загадок.")
                        .font(.system(size: 29, weight: .bold)).tracking(-0.9)
                    Text(model.section == 0 ? "Подключи исходный iPhone. Сохрани доступные приложения для нового телефона." : model.section == 1 ? "VK, MAX, Сбер и другие приложения из твоей библиотеки." : model.section == 2 ? "Установочные файлы в твоём локальном архиве." : "Что утилита умеет и от чего зависит результат.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
            }
        }
    }
    private func noticeView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Palette.orange)
            Text(text).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button { model.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel("Закрыть сообщение")
        }.padding(15).background(Palette.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private var connection: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("ДВА ТЕЛЕФОНА. ОДИН МОСТ.").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Palette.muted)
                Spacer()
                Button { model.newTransfer() } label: { Label("Новый перенос", systemImage: "plus") }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).disabled(model.busy)
                    .padding(.trailing, 12)
                Button { model.refresh() } label: { Label("Обновить устройства", systemImage: "arrow.clockwise") }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).disabled(model.busy)
            }
            HStack(alignment: .top, spacing: 16) {
                phoneCard(source: true)
                phoneCard(source: false)
            }
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Palette.orange).padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Один кабель — тоже подходит").font(.system(size: 12, weight: .semibold))
                    Text("Сначала прочитай приложения со старого iPhone. Список сохранится на Mac; затем подключи новый телефон.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
                }
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 15) {
                Text("Как проходит перенос").font(.system(size: 16, weight: .semibold))
                HStack(alignment: .top, spacing: 22) {
                    explanation("01", "Подключить", "Разблокируй iPhone и разреши доверие этому Mac.", "cable.connector")
                    explanation("02", "Сохранить", "Войди в Apple ID и запроси доступные установочные файлы.", "square.and.arrow.down")
                    explanation("03", "Установить", "Выбери новый iPhone и приложения из архива.", "arrow.down.app")
                }
            }.padding(.top, 3)
            Text("Наличие приложения на старом iPhone не гарантирует загрузку: Apple должна ещё выдавать файл твоему аккаунту. Можно импортировать ранее сохранённый .ipa.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
        }
    }
    private func phoneCard(source isSource: Bool) -> some View {
        let phone = isSource ? model.source : model.target
        let connected = isSource ? model.sourceConnected : phone != nil
        return VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text(isSource ? "ОТКУДА" : "КУДА").font(.system(size: 9, weight: .bold)).tracking(1.7).foregroundStyle(Palette.muted)
                Spacer()
                Circle().fill(connected ? Palette.green : Palette.muted.opacity(0.4)).frame(width: 5, height: 5)
                Text(connected ? "USB подключён" : isSource && model.state.source != nil ? "Список сохранён" : "Ожидает подключения")
                    .font(.system(size: 10)).foregroundStyle(connected ? Palette.green : Palette.muted)
            }
            HStack(spacing: 17) {
                PhoneDrawing(new: !isSource).frame(width: 55, height: 96)
                VStack(alignment: .leading, spacing: 7) {
                    Text(phone?.model ?? (isSource ? "Исходный iPhone" : "Новый iPhone")).font(.system(size: 20, weight: .semibold)).tracking(-0.5)
                    Text(phone.map { $0.iosVersion.isEmpty ? $0.name : "\($0.name) · iOS \($0.iosVersion)" } ?? (isSource ? "Твой исходный телефон" : "Твой новый телефон"))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                    if let phone { Text("ID …\(phone.id.suffix(8))").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) }
                }
                Spacer(minLength: 0)
            }
            if isSource {
                Picker("Исходный iPhone", selection: $model.sourceID) {
                    Text("Выбери исходный iPhone").tag("")
                    ForEach(model.phones) { Text("\($0.name) · \($0.model) · …\($0.id.suffix(4))").tag($0.id) }
                    if let saved = model.state.source, !model.phones.contains(where: { $0.id == saved.id }) { Text("\(saved.name) · сохранённый список").tag(saved.id) }
                }.labelsHidden().disabled(model.busy)
                Button { model.readApps() } label: { Label("Прочитать приложения", systemImage: "square.grid.2x2") }
                    .buttonStyle(FilledButton()).disabled(model.busy || !model.sourceConnected).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Новый iPhone", selection: $model.targetID) {
                    Text("Выбери новый iPhone").tag("")
                    ForEach(model.availableTargets) { Text("\($0.name) · \($0.model) · …\($0.id.suffix(4))").tag($0.id) }
                }.labelsHidden().disabled(model.busy)
                if let phone, !phone.trusted {
                    Button("Запросить доверие") { model.pairTarget() }.buttonStyle(FilledButton(prominent: false)).disabled(model.busy)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: phone != nil ? "checkmark.circle" : "arrow.down.app")
                        Text(phone != nil ? "Готов к установке из архива" : "Подключи после сохранения файлов")
                    }.font(.system(size: 11)).foregroundStyle(phone != nil ? Palette.green : Palette.muted).padding(.vertical, 12)
                }
            }
        }.padding(21).frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            .background(isSource ? .white : Color(red: 0.985, green: 0.966, blue: 0.935), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(isSource ? Palette.line : Palette.orange.opacity(0.14)))
    }
    private func explanation(_ number: String, _ title: String, _ body: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Palette.orange)
                Spacer()
                Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.5))
            }
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(body).font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private var accountCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.account.isEmpty ? "Apple ID с твоими приложениями" : model.account).font(.system(size: 13, weight: .semibold))
                Text(model.account.isEmpty ? "Войди в аккаунт, с которого приложения установлены на исходном iPhone." : "Проверь, что это Apple ID исходного iPhone.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button(model.account.isEmpty ? "Войти" : "Сменить Apple ID") { model.startLogin() }.buttonStyle(FilledButton(prominent: false)).disabled(model.busy)
            Button("Проверить вход") { model.checkAccount() }.buttonStyle(FilledButton(prominent: false)).disabled(model.busy)
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
    private var applications: some View {
        VStack(alignment: .leading, spacing: 18) {
            accountCard
            HStack {
                Button { model.showPurchases = false; model.search = ""; model.selectedApps = Set(model.state.apps.filter(\.preferred).map(\.id)) } label: {
                    Label("С iPhone · \(model.state.apps.count)", systemImage: "iphone")
                }.buttonStyle(FilledButton(prominent: !model.showPurchases)).disabled(model.busy)
                Button { model.loadPurchases() } label: { Label("История Apple ID", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(FilledButton(prominent: model.showPurchases)).disabled(model.busy || model.account.isEmpty)
                Spacer()
                if let source = model.state.source, !model.showPurchases { Text(source.name).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Найти по названию или идентификатору", text: $model.search).textFieldStyle(.plain)
                }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line))
                Toggle("VK, MAX и Сбер", isOn: $model.onlyPreferred).toggleStyle(.checkbox).font(.system(size: 11))
            }
            if model.visibleApps.isEmpty {
                empty("square.grid.2x2", model.state.apps.isEmpty && !model.showPurchases ? "Сначала прочитай список приложений" : "По этому фильтру ничего не найдено", model.state.apps.isEmpty && !model.showPurchases ? "Открой «Подключение» и подключи исходный iPhone. Также можно загрузить историю Apple ID." : "Измени поиск или отключи фильтр VK, MAX и Сбер.")
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("ПРИЛОЖЕНИЕ"); Spacer(); Text("ИСТОЧНИК И СОСТОЯНИЕ")
                    }.font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Palette.muted).padding(.horizontal, 18).padding(.vertical, 12)
                    ForEach(model.visibleApps) { app in
                        Rectangle().fill(Palette.line).frame(height: 1)
                        appRow(app)
                    }
                }.background(.white, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line))
            }
            if model.showPurchases {
                HStack {
                    Text("Страница \(model.purchasePage) · всего \(model.purchaseTotal) записей").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Назад") { model.loadPurchases(page: model.purchasePage - 1) }.disabled(model.busy || model.purchasePage <= 1)
                    Button("Дальше") { model.loadPurchases(page: model.purchasePage + 1) }.disabled(model.busy || model.purchasePage * 100 >= model.purchaseTotal)
                }
            }
            HStack(alignment: .center, spacing: 20) {
                Text("Apple может выдать другую доступную версию. Если файл больше не выдаётся, понадобится ранее сохранённый IPA.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                Button { model.downloadSelected() } label: { Label("Сохранить выбранные · \(model.selectedApps.count)", systemImage: "arrow.down.to.line") }
                    .buttonStyle(FilledButton()).disabled(model.busy || model.selectedApps.isEmpty || model.account.isEmpty)
            }
            Text("Вход открывается в Terminal. Ввод пароля скрыт; пароль и код 2FA не записываются в журнал приложения.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }
    private func appRow(_ app: PhoneApp) -> some View {
        HStack(spacing: 12) {
            Toggle("Выбрать \(app.name)", isOn: selection(app.id, in: $model.selectedApps)).labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
            AppMonogram(app: app).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(app.name).font(.system(size: 13, weight: .semibold))
                    if !app.version.isEmpty { Text(app.version).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                }
                Text(app.bundleID).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                let storeID = model.state.storeOverrides[app.bundleID] ?? app.storeID
                Text(model.appMessages[app.id] ?? (app.placeholder ? "Приложение выгружено" : model.state.archive.contains(where: { $0.app.bundleID == app.bundleID }) ? "Есть в архиве" : "Готово к запросу"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
                Button { editingApp = app } label: {
                    Label(storeID.isEmpty ? "Указать App Store ID" : "ID \(storeID)", systemImage: "pencil")
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.orange).disabled(model.busy)
            }
        }.padding(.horizontal, 18).padding(.vertical, 13)
    }
    private var archive: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Локальный архив · \(model.storedCount)").font(.system(size: 16, weight: .semibold))
                    Text("Файлы проверяются по SHA-256 перед установкой.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { model.revealLibrary() } label: { Label("Открыть папку", systemImage: "folder") }.buttonStyle(FilledButton(prominent: false))
                Button { model.chooseIPA() } label: { Label("Добавить .ipa", systemImage: "plus") }.buttonStyle(FilledButton(prominent: false)).disabled(model.busy)
            }
            if model.state.archive.isEmpty {
                empty("archivebox", "Здесь будут твои приложения", "Сохрани файлы на вкладке «Приложения» или добавь IPA, который уже есть на Mac.")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.state.archive) { item in
                        HStack(spacing: 12) {
                            Toggle("Выбрать \(item.app.name)", isOn: selection(item.id, in: $model.selectedArchives)).labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                            AppMonogram(app: item.app).frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.app.name).font(.system(size: 13, weight: .semibold))
                                Text("\(item.app.version) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)) · \(item.origin)")
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Text(item.app.bundleID).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                                Text(item.appleAccount.map { "Apple ID: \($0)" } ?? "Apple ID не записан для этой копии").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Text(item.createdAt, style: .date).font(.system(size: 10)).foregroundStyle(Palette.muted)
                            Button { model.exportIPA(item) } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain).padding(8).help("Сохранить копию IPA…").disabled(model.busy)
                        }.padding(16)
                        if item.id != model.state.archive.last?.id { Rectangle().fill(Palette.line).frame(height: 1) }
                    }
                }.background(.white, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line))
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Установка на новый iPhone", systemImage: "arrow.down.app").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { model.refresh() } label: { Label("Обновить", systemImage: "arrow.clockwise") }.buttonStyle(.plain).font(.system(size: 11)).disabled(model.busy)
                }
                HStack(spacing: 14) {
                    Picker("Получатель", selection: $model.targetID) {
                        Text("Выбери новый iPhone").tag("")
                        ForEach(model.availableTargets) { Text("\($0.name) · \($0.model) · …\($0.id.suffix(6))").tag($0.id) }
                    }.disabled(model.busy)
                    if model.target != nil && model.target?.trusted == false {
                        Button("Доверять Mac") { model.pairTarget() }.buttonStyle(FilledButton(prominent: false)).disabled(model.busy)
                    }
                    Button { model.installConfirmation = true } label: { Label("Установить · \(model.selectedArchives.count)", systemImage: "arrow.down.app") }
                        .buttonStyle(FilledButton()).disabled(!model.canInstall)
                }
                Text("Выбери тот же Apple ID на iPhone. После установки открой приложения и войди заново. Утилита пропускает уже установленные копии.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
            }.padding(20).background(Color(red: 0.985, green: 0.966, blue: 0.935), in: RoundedRectangle(cornerRadius: 14))
        }
    }
    private var help: some View {
        VStack(alignment: .leading, spacing: 22) {
            helpCard("Что переносится", "Установочный файл приложения из Apple или из твоего архива. Данные, переписки, банковские сессии и настройки входа этим способом не переносятся.", "app.badge.checkmark")
            helpCard("Почему нужен Apple ID", "Установленные приложения нельзя штатно извлечь с обычного iPhone в готовый IPA. Утилита читает их список и запрашивает файлы у Apple от твоего аккаунта. Удаление из поиска App Store и запрет повторной загрузки — разные ограничения.", "person.crop.circle")
            helpCard("Если Apple не выдаёт файл", "Проверь числовой App Store ID, историю покупок и аккаунт, с которого устанавливал приложение. Если загрузка недоступна, нужен ранее сохранённый совместимый IPA. Утилита не может гарантировать восстановление VK, MAX или Сбера.", "info.circle")
            helpCard("Что проверить после установки", "Открой каждое приложение на iPhone 17 Pro. iOS проверяет подпись и право запуска; старая версия также может больше не поддерживаться сервером приложения.", "iphone.gen3")
            HStack {
                Button("Открыть инструкцию") { model.revealInstructions() }.buttonStyle(FilledButton(prominent: false))
                Link("Открытый исходный код ipatool ↗", destination: URL(string: "https://github.com/majd/ipatool")!).font(.system(size: 11))
            }
        }
    }
    private func helpCard(_ title: String, _ body: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Palette.orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(21).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
    private func empty(_ icon: String, _ title: String, _ body: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Palette.muted)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(body).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: 400).lineSpacing(3)
        }.frame(maxWidth: .infinity).padding(.vertical, 45).padding(.horizontal, 22)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
    private var activity: some View {
        DisclosureGroup(isExpanded: $activityOpen) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(model.activity.prefix(12)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.date, style: .time).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                        Text(entry.text).font(.system(size: 11)).foregroundStyle(entry.failed ? Palette.orange : Palette.muted).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(.top, 12)
        } label: { Text("Журнал действий · \(model.activity.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted) }
    }
    private var footer: some View {
        HStack(spacing: 9) {
            if model.busy { ProgressView().controlSize(.small) }
            else { Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(model.phones.isEmpty ? Palette.muted : Palette.green) }
            Text(model.busy ? model.taskTitle : model.status).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
            Spacer(minLength: 10)
            Text("\(model.storedCount) IPA").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
        }.padding(.horizontal, 25).padding(.vertical, 12).frame(minHeight: 44).background(.white)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    private func selection(_ id: String, in values: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { checked in
            if checked { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }
}

struct PhoneDrawing: View {
    var new: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 11).fill(Palette.ink)
            .overlay(RoundedRectangle(cornerRadius: 9).fill(new ? Color(red: 0.95, green: 0.80, blue: 0.63) : Color(red: 0.78, green: 0.84, blue: 0.88)).padding(3))
            .overlay(alignment: .top) { Capsule().fill(Palette.ink).frame(width: new ? 20 : 25, height: new ? 6 : 7).padding(.top, new ? 7 : 3) }
            .overlay(alignment: .bottom) { Capsule().fill(Palette.ink.opacity(0.4)).frame(width: 18, height: 2).padding(.bottom, 7) }
            .rotationEffect(.degrees(new ? 7 : -7))
            .shadow(color: .black.opacity(0.12), radius: 7, x: 2, y: 7)
    }
}

struct AppMonogram: View {
    var app: PhoneApp
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(app.category == "Сбер" ? Color(red: 0.16, green: 0.65, blue: 0.34) : app.category == "MAX" ? Color(red: 0.45, green: 0.31, blue: 0.88) : app.category == "VK" ? Color(red: 0.08, green: 0.47, blue: 0.97) : Palette.muted.opacity(0.13))
            Text(app.monogram).font(.system(size: app.monogram.count > 2 ? 11 : 16, weight: .bold)).foregroundStyle(app.preferred ? .white : Palette.muted)
        }.accessibilityHidden(true)
    }
}

struct AppIDEditor: View {
    var app: PhoneApp
    var current: String
    var save: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("App Store ID · \(app.name)").font(.system(size: 18, weight: .semibold))
            Text("Для удалённого приложения числовой ID может сработать, даже когда поиск по названию уже не работает. Его также можно получить из истории Apple ID.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("123456789 или ссылка apps.apple.com", text: $text).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save(text); dismiss() }.keyboardShortcut(.defaultAction).disabled(StoreIdentifier.parse(text) == nil)
            }
        }.padding(25).frame(width: 440).onAppear { text = current }
    }
}
