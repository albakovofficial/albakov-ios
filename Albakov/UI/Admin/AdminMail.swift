import SwiftUI
import WebKit

// Почта: письма покупателям (просмотр и пример на свою почту), уведомления мне, «Сообщить о поступлении» (заявки и текст письма),
// подключение почтового ящика (SMTP). Те же запросы, что у панели сайта.
struct AdminMail: View {
    @ObservedObject private var admin = Admin.shared
    @State private var tab = "letters"
    @State private var mail = JSON(nil)
    @State private var mailError: String?
    var body: some View {
        let waiting = admin.data["waitlist"].array.filter { ["waiting", "failed"].contains($0["status"].str) }.count
        List {
            Section {
                Text("Всё, что сайт отправляет письмами: покупателям, вам и тем, кто ждёт размер. Письма уходят с вашего почтового ящика — он подключается один раз.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                if mail.exists && !mail["ready"].bool { Text("Почта не подключена — ни одно письмо не уходит. Покупатели не получают подтверждение заказа и трек-номер, вы не узнаёте о новых заказах.").font(Theme.font(13, .medium)).foregroundStyle(Theme.danger) }
                PillTabs(items: [("letters", "Письма покупателям"), ("alerts", "Уведомления мне"), ("notify", "Сообщить о поступлении" + (waiting > 0 ? " · \(waiting)" : ""))] + (admin.can("payment") ? [("smtp", "Подключение")] : []), value: $tab)
            }
            switch tab {
            case "alerts": MailAlerts()
            case "notify": MailNotify(mailReady: mail["ready"].bool)
            case "smtp":
                // форма — только поверх загруженных настроек: иначе «Сохранить» затёр бы имя отправителя и адрес для ответов пустыми (Q-3)
                if mail.exists { MailSmtp(mail: mail) { Task { await load() } } }
                else if let mailError { Section { ErrorRetry(text: "Настройки почты не загрузились: " + mailError) { Task { await load() } } } }
                else { Section { ProgressView().frame(maxWidth: .infinity) } }
            default: MailLetters()
            }
        }
        .font(Theme.font(15))
        .navigationTitle("Почта").navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() }; await load() }
        .refreshable { await admin.load(); await load() }
    }
    private func load() async {
        do { mail = try await API.shared.json("GET", "admin/mail")["mail"]; mailError = nil }
        catch {
            guard let m = error.userMessage else { return }   // загрузку отменили (ушли с экрана)
            if mail.exists { Toast.shared.show(m) } else { mailError = m }   // настройки уже на экране — оставляем их
        }
    }
}

/// Все письма, которые сайт отправляет сам: тема, кому, когда; посмотреть и отправить пример
private struct MailLetters: View {
    @State private var r = JSON(nil)
    @State private var loadError: String?
    @State private var to = ""
    @State private var view: JSON?
    var body: some View {
        let mi = r["mail"]
        Section {
            Text("Покупателям письма приходят с адреса для отправки и с пометкой «отвечать не нужно» — написать вам можно на почту для связи.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            if r.exists {
                LabeledContent("Отправитель", value: mi["from"].str.isEmpty ? "—" : (mi["fromName"].str.isEmpty ? "" : mi["fromName"].str + " ") + "<" + mi["from"].str + ">")
                LabeledContent("Пишут вам", value: [mi["support"].str, mi["replyTo"].str].first { !$0.isEmpty } ?? "—")
                Text(mi["ready"].bool ? "Почта настроена, письма уходят" : "Не настроена — письма не отправляются").font(Theme.font(12.5)).foregroundStyle(mi["ready"].bool ? Theme.ok : Theme.warn)
                TextField("Почта для примера", text: $to).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            } else if let loadError {   // список писем не загрузился (Q-3) — причина и «Повторить», а не вечная загрузка
                ErrorRetry(text: "Список писем не загрузился: " + loadError) { Task { await load() } }
            } else { ProgressView() }
        }
        Section("Письма") {
            ForEach(r["letters"].array.indices, id: \.self) { i in
                let x = r["letters"].array[i]
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(i + 1). " + x["title"].str).font(Theme.font(14.5, .medium))
                    Text(x["when"].str + " · " + x["to"].str).font(Theme.font(12)).foregroundStyle(Theme.muted)
                    Text("Тема: " + x["subject"].str).font(Theme.font(12.5))
                    HStack(spacing: 18) {
                        Button("Посмотреть письмо") { view = x }
                        Button("Отправить пример") { Task { await send(x["key"].str) } }.disabled(to.isEmpty)
                    }.font(Theme.font(13)).buttonStyle(.borderless)
                }.padding(.vertical, 4)
            }
        }
        .task { if !r.exists { await load() } }
        .sheet(item: Binding(get: { view.map { Letter(j: $0) } }, set: { view = $0?.j })) { w in
            NavigationStack { HTMLView(html: w.j["html"].str).ignoresSafeArea(edges: .bottom).navigationTitle(w.j["subject"].str).navigationBarTitleDisplayMode(.inline) }
        }
    }
    private func load() async {
        do { let x = try await API.shared.json("GET", "admin/mail-catalog"); r = x; to = x["mail"]["support"].str; loadError = nil }
        catch { if let m = error.userMessage { loadError = m } }
    }
    private func send(_ key: String) async {
        do { let s = try await API.shared.json("POST", "admin/mail-catalog", body: ["key": key, "to": to]); Toast.shared.show("Отправлено на " + s["sent"].str) } catch { Toast.shared.show(error.userMessage) }
    }
}

private struct Letter: Identifiable { let j: JSON; var id: String { j["key"].str } }

/// Готовое HTML-письмо внутри приложения — предпросмотр. Делегата навигации нет: ссылка из письма открывается в этом же окне
struct HTMLView: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView { let w = WKWebView(); w.loadHTMLString(html, baseURL: API.shared.base); return w }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Уведомления владельцу: куда и что присылать, пример письма
private struct MailAlerts: View {
    @ObservedObject private var admin = Admin.shared
    @State private var email = ""
    @State private var ev: [String: Bool] = [:]
    private static let kinds = [("order", "Новый заказ", "Состав, покупатель, доставка и оплата. Заказ с онлайн-оплатой приходит, когда деньги поступили"), ("support", "Вопросы покупателей", "Новые обращения и сообщения в поддержке"), ("stock", "Заканчиваются размеры", "Когда остаток размера становится 1 или 0")]
    var body: some View {
        let main = admin.data["settings"]["contacts"]["email"].str
        Section("Куда присылать") {
            TextField(main.isEmpty ? "shop@example.ru" : main, text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            Text(main.isEmpty ? "Укажите адрес, на который присылать уведомления." : "Пусто — письма уходят на основную почту магазина \(main).").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            Button("Сохранить") { Task { await save(email.isEmpty ? "Уведомления будут приходить на основную почту" : "Уведомления будут приходить на \(email)") } }.font(Theme.font(15, .medium))
        }
        Section("Что присылать") {
            ForEach(MailAlerts.kinds, id: \.0) { k in
                Toggle(isOn: Binding(get: { ev[k.0] ?? true }, set: { ev[k.0] = $0; Task { await save("Сохранено") } })) { VStack(alignment: .leading, spacing: 2) { Text(k.1).font(Theme.font(15)); Text(k.2).font(Theme.font(12)).foregroundStyle(Theme.muted) } }.tint(Theme.ink)
            }
        }
        Section("Проверить") {
            Text("Пришлём пример письма — посмотрите, как оно выглядит и не попадает ли в спам.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            ForEach(MailAlerts.kinds, id: \.0) { k in
                Button(k.1) { Task { do { let r = try await AdminAPI.post("owner-notify/test", ["kind": k.0]); Toast.shared.show("Отправили «\(k.1)» на \(r["to"].str)") } catch { Toast.shared.show(error.userMessage) } } }
            }
        }
        .onAppear {
            let n = admin.data["settings"]["ownerNotify"]; email = n["email"].str
            for k in MailAlerts.kinds { ev[k.0] = !(n["events"][k.0].exists && !n["events"][k.0].bool) }
        }
    }
    private func save(_ msg: String) async {
        if !email.isEmpty && email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) == nil { Toast.shared.show("Проверьте адрес почты"); return }
        var s = admin.data["settings"].dictAny
        s["ownerNotify"] = ["email": email, "events": ev] as [String: Any]
        do { try await AdminAPI.saveSettings(s); await admin.load(); Toast.shared.show(msg) } catch { Toast.shared.show(error.userMessage) }
    }
}

/// «Сообщить о поступлении»: кнопка на сайте, чего ждут, заявки, отправка писем, текст письма
private struct MailNotify: View {
    let mailReady: Bool
    @ObservedObject private var admin = Admin.shared
    @State private var f = "waiting"
    @State private var sub = "requests"
    @StateObject private var tpl = Doc([:])
    @State private var to = ""
    @State private var delId: String?
    private static let st = ["waiting": "Ждёт поступления", "failed": "Ошибка отправки — повторим", "sent": "Письмо отправлено", "canceled": "Покупатель отменил"]
    private static let def: [String: Any] = ["subject": "{товар} снова в наличии", "heading": "Он вернулся", "text": "Вы просили сообщить, когда появится {товар} в цвете «{цвет}», размер {размер}. Он снова в наличии.", "button": "Перейти к товару", "footer": "Вы получили это письмо, потому что оставили заявку на сайте {магазин}. Это разовое уведомление, рассылки не будет."]
    var body: some View {
        let n = admin.data["settings"]["notify"], on = !(n["enabled"].exists && !n["enabled"].bool)
        let wl = admin.data["waitlist"].array
        let match: [String]? = ["waiting": ["waiting", "failed"], "done": ["sent"], "canceled": ["canceled"]][f]
        let list = Array(wl.filter { match == nil || match!.contains($0["status"].str) }.reversed())
        let ready = wl.filter { ["waiting", "failed"].contains($0["status"].str) && info($0).stock > 0 }
        Section {
            Text("Если нужного размера или цвета нет, покупатель нажимает «Сообщить о поступлении» и оставляет почту. Когда вы пополните остаток, письмо уйдёт само.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            Toggle(isOn: Binding(get: { on }, set: { v in Task { await setEnabled(v) } })) { VStack(alignment: .leading) { Text("Кнопка «Сообщить о поступлении»").font(Theme.font(15)); Text(on ? "Покупатели видят её, если размера или цвета нет" : "Выключена — покупатели её не видят").font(Theme.font(12)).foregroundStyle(Theme.muted) } }.tint(Theme.ink)
            if !ready.isEmpty && !mailReady { Text("\(ready.count) \(Fmt.plural(ready.count, "заявка", "заявки", "заявок")): товар уже в наличии, но письма не ушли — почта для отправки не настроена.").font(Theme.font(13)).foregroundStyle(Theme.warn) }
            Picker("", selection: $sub) { Text("Заявки").tag("requests"); Text("Текст письма").tag("letter") }.pickerStyle(.segmented)
        }
        if sub == "letter" {
            Section("Текст письма") {
                Text("Подстановки: {товар}, {цвет}, {размер}, {цена}, {магазин} — в каждом письме на их месте окажутся данные из заявки.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                DefForm(defs: [FDef(k: "subject", label: "Тема письма"), FDef(k: "heading", label: "Заголовок"), FDef(k: "text", label: "Текст", kind: .area(6), hint: "Пустая строка — новый абзац"), FDef(k: "button", label: "Текст кнопки"), FDef(k: "footer", label: "Подпись внизу письма", kind: .area(3))], doc: tpl)
                Button("Сохранить текст") { Task { await saveTpl() } }.font(Theme.font(15, .medium))
                Button("Вернуть стандартный") { tpl.v = MailNotify.def; Toast.shared.show("Стандартный текст подставлен. Нажмите «Сохранить текст»") }
            }
            Section("Проверить письмо") {
                TextField("Ваша почта", text: $to).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                Button("Отправить пример") { Task { do { _ = try await AdminAPI.post("mail/test", ["to": to]); Toast.shared.show("Пример отправлен на \(to). Учтите: сохранённый текст, а не черновик.") } catch { Toast.shared.show(error.userMessage) } } }.disabled(to.isEmpty || !mailReady)
                Button("Отправить письма регистрации: код и приветствие") { Task { do { _ = try await AdminAPI.post("mail/test-account", ["to": to]); Toast.shared.show("Отправили на \(to) два письма") } catch { Toast.shared.show(error.userMessage) } } }.disabled(to.isEmpty || !mailReady)
            }
            .onAppear { if tpl.v.isEmpty { var t = MailNotify.def; for (k, v) in n.dict where k != "enabled" { t[k] = v.str }; tpl.v = t } }
        } else {
            let groups = Dictionary(grouping: wl.filter { ["waiting", "failed"].contains($0["status"].str) }) { $0["productId"].str + "|" + $0["colorId"].str + "|" + $0["size"].str }.values.sorted { $0.count > $1.count }
            if !groups.isEmpty {
                Section("Чего ждут покупатели") {
                    ForEach(groups.indices, id: \.self) { i in
                        let g = groups[i], x = info(g[0])
                        HStack { Text("\(x.name) · \(x.color) · \(x.size)").font(Theme.font(13.5)); Spacer(); Text("ждут \(g.count) · на складе \(x.stock)").font(Theme.font(12)).foregroundStyle(Theme.muted) }
                    }
                }
            }
            Section {
                Picker("", selection: $f) { Text("Ждут").tag("waiting"); Text("Отправлены").tag("done"); Text("Отменены").tag("canceled"); Text("Все").tag("all") }.pickerStyle(.segmented)
                if !ready.isEmpty { Button("Отправить письма сейчас (\(ready.count))") { Task { do { let r = try await AdminAPI.post("waitlist/send"); await admin.load(); Toast.shared.show(notifyMsg("Готово", r["notify"])) } catch { Toast.shared.show(error.userMessage) } } }.font(Theme.font(15, .medium)) }
                if list.isEmpty { Text(f == "waiting" ? "Заявок нет. Когда покупатель попросит сообщить о поступлении, заявка появится здесь." : "Пусто").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                ForEach(list.indices, id: \.self) { i in
                    let w = list[i], x = info(w)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(w["email"].str).font(Theme.font(14)).textSelection(.enabled); Spacer(); Text(MailNotify.st[w["status"].str] ?? w["status"].str).font(Theme.font(11.5)).foregroundStyle(w["status"].str == "sent" ? Theme.ok : w["status"].str == "failed" ? Theme.danger : Theme.muted) }
                        Text("\(x.name) · \(x.color) · \(x.size) · " + Fmt.date(ISO.date(w["createdAt"].str))).font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                    .swipeActions { Button("Удалить", role: .destructive) { delId = w["id"].str } }
                }
            }
            .confirmationDialog("Удалить заявку?", isPresented: Binding(get: { delId != nil }, set: { if !$0 { delId = nil } }), titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let id = delId { Task { do { _ = try await API.shared.raw("DELETE", "admin/waitlist/\(id)"); await admin.load(); Toast.shared.show("Заявка удалена") } catch { Toast.shared.show(error.userMessage) } } } }
            }
        }
    }
    private func info(_ w: JSON) -> (name: String, color: String, size: String, stock: Int) {
        let p = admin.data["products"].array.first { $0["id"].str == w["productId"].str }
        let c = p?["colors"].array.first { $0["id"].str == w["colorId"].str }
        let st = c?["sizes"].array.filter { w["size"].str.isEmpty || $0["size"].str == w["size"].str }.reduce(0) { $0 + ($1["stock"].int ?? 0) } ?? 0
        return (p?["name"].str ?? "Товар удалён", c?["name"].str ?? "—", w["size"].str.isEmpty ? "любой" : w["size"].str, st)
    }
    private func setEnabled(_ v: Bool) async {
        var s = admin.data["settings"].dictAny; var n = (s["notify"] as? [String: Any]) ?? MailNotify.def; n["enabled"] = v; s["notify"] = n
        do { try await AdminAPI.saveSettings(s); await AdminAPI.reload(); Toast.shared.show(v ? "Кнопка «Сообщить о поступлении» включена" : "Кнопка выключена: покупатели её не увидят") } catch { Toast.shared.show(error.userMessage) }
    }
    private func saveTpl() async {
        let t = tpl.v.mapValues { "\($0)" }
        if [t["subject"], t["heading"], t["button"]].contains(where: { ($0 ?? "").trimmingCharacters(in: .whitespaces).isEmpty }) { Toast.shared.show("Тема, заголовок и текст кнопки не могут быть пустыми"); return }
        let all = ["subject", "heading", "text", "button", "footer"].map { t[$0] ?? "" }.joined()
        let ok = ["{товар}", "{цвет}", "{размер}", "{цена}", "{магазин}"]
        let found = (try? NSRegularExpression(pattern: #"\{[^}]*\}"#))?.matches(in: all, range: NSRange(all.startIndex..., in: all)).compactMap { Range($0.range, in: all).map { String(all[$0]) } } ?? []
        if let bad = found.first(where: { !ok.contains($0) }) { Toast.shared.show("Неизвестная подстановка \(bad). Используйте подстановки из списка"); return }
        var s = admin.data["settings"].dictAny; var n: [String: Any] = t; n["enabled"] = !(admin.data["settings"]["notify"]["enabled"].exists && !admin.data["settings"]["notify"]["enabled"].bool); s["notify"] = n
        do { try await AdminAPI.saveSettings(s); await admin.load(); Toast.shared.show("Текст письма сохранён") } catch { Toast.shared.show(error.userMessage) }
    }
}

/// Подключение почтового ящика: сервер, порт, шифрование, логин, пароль приложения, отправитель
private struct MailSmtp: View {
    let mail: JSON
    let saved: () -> Void
    @StateObject private var doc = Doc([:])
    @State private var loaded = false
    var body: some View {
        Section {
            Text("Письма уходят с вашего почтового ящика. Лучше всего — ящик на домене магазина в Яндекс 360 или Mail.ru для бизнеса либо сервис рассылок SMTP.BZ.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            HStack { Text("Заполнить для:").font(Theme.font(13)).foregroundStyle(Theme.muted); Button("SMTP.BZ") { preset("connect.smtp.bz", 2525, "starttls") }; Button("Яндекс") { preset("smtp.yandex.ru", 465, "ssl") }; Button("Mail.ru") { preset("smtp.mail.ru", 465, "ssl") } }.font(Theme.font(13)).buttonStyle(.bordered)
            DefForm(defs: [FDef(k: "host", label: "Сервер исходящей почты (SMTP)"), FDef(k: "port", label: "Порт", kind: .number),
                           FDef(k: "security", label: "Шифрование", kind: .select([("ssl", "SSL (обычно порт 465)"), ("starttls", "STARTTLS (обычно порт 587)"), ("none", "Без шифрования")])),
                           FDef(k: "user", label: "Логин"), FDef(k: "pass", label: "Пароль приложения", hint: mail["hasPass"].bool ? "Пароль сохранён. Оставьте поле пустым, чтобы не менять." : "Создаётся в настройках безопасности почты. Обычный пароль от ящика не подойдёт."),
                           FDef(k: "fromEmail", label: "Адрес отправителя", hint: "Обычно совпадает с логином"), FDef(k: "fromName", label: "Имя отправителя"),
                           FDef(k: "replyTo", label: "Адрес для ответов", hint: "Куда попадёт ответ, если покупатель нажмёт «Ответить». Пусто — почта из «Контактов»")], doc: doc)
            Button("Сохранить") { Task { await save() } }.font(Theme.font(15, .medium))
        }
        .onAppear { if !loaded { var v = mail.dictAny; v["pass"] = ""; doc.v = v; loaded = true } }
    }
    private func preset(_ h: String, _ p: Int, _ s: String) { doc.v["host"] = h; doc.v["port"] = p; doc.v["security"] = s }
    private func save() async {
        var m = doc.v
        if doc.str("host").isEmpty || doc.str("user").isEmpty { Toast.shared.show("Укажите сервер и логин"); return }
        if doc.str("fromEmail").isEmpty { m["fromEmail"] = doc.str("user") }
        do { _ = try await AdminAPI.post("mail", ["mail": m]); Toast.shared.show("Настройки почты сохранены. Проверьте их: отправьте себе любое письмо во вкладке «Письма»"); saved() } catch { Toast.shared.show(error.userMessage) }
    }
}
