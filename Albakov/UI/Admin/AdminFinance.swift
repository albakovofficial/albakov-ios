import SwiftUI
import JavaScriptCore

// Финансы: отчёт о прибыли, операции, себестоимость, настройки. Расчёт — тот же модуль, что и на сайте
// (public/js/finance.js): приложение загружает его с сайта и выполняет через JavaScriptCore, поэтому цифры совпадают один в один.
@MainActor
final class FinanceEngine: ObservableObject {
    static let shared = FinanceEngine()
    private var ctx: JSContext?
    @Published var error: String?

    func ready() async -> Bool {
        if ctx != nil { return true }
        guard let url = API.shared.url("js/finance.js") else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let c = JSContext()!
            c.exceptionHandler = { [weak self] _, e in Task { @MainActor in self?.error = e?.toString() } }
            c.evaluateScript("var window = this; var module = undefined;")
            c.evaluateScript(String(decoding: data, as: UTF8.self))
            // Отчёт в JSON: строки по категориям раскрываем заранее (в модуле это функция)
            c.evaluateScript("""
            function finReport(inputJson, kind, shift, from, to) {
              var input = JSON.parse(inputJson), per = Finance.period(kind, shift, from, to), r = Finance.report(input, per);
              ['cur', 'prev'].forEach(function (k) { var s = r[k]; s.byLine = {}; ['variable', 'fixed', 'purchase', 'taxpaid'].forEach(function (l) { s.byLine[l] = s.lines(l); }); delete s.lines; });
              r.months.forEach(function (m) { delete m.p.lines; });
              r.ops = r.ops.filter(function (x) { return x.date >= per.from && x.date <= per.to; });
              return JSON.stringify(r);
            }
            function finKinds() { return JSON.stringify({ kinds: Finance.KINDS, defaults: Finance.defaults() }); }
            """)
            guard c.objectForKeyedSubscript("Finance")?.isUndefined == false else { error = "Не загрузился модуль расчёта"; return false }
            ctx = c; return true
        } catch { self.error = error.userMessage; return false }
    }
    func report(_ input: [String: Any], kind: String, shift: Int, from: String, to: String) -> JSON {
        guard let ctx else { return JSON(nil) }
        // данные панели пришли с сервера в JSON и обратно записываются всегда; иначе — причина вместо пустого отчёта.
        // Ошибка относится к последнему расчёту: удачный расчёт её убирает (ошибку модуля ставит exceptionHandler уже после)
        let d: Data
        do { d = try JSONSerialization.checkedData(input); error = nil }
        catch { self.error = "Отчёт не посчитан: данные панели не подготовились. Обновите их — потяните экран вниз."; return JSON(nil) }
        let s = ctx.objectForKeyedSubscript("finReport").call(withArguments: [String(decoding: d, as: UTF8.self), kind, shift, from, to])?.toString() ?? ""
        return JSON(data: Data(s.utf8))
    }
    func kinds() -> JSON { JSON(data: Data((ctx?.objectForKeyedSubscript("finKinds").call(withArguments: [])?.toString() ?? "").utf8)) }
}

struct AdminFinance: View {
    @ObservedObject private var admin = Admin.shared
    @ObservedObject private var eng = FinanceEngine.shared
    @State private var tab = "report"
    @State private var kind = "month"
    @State private var shift = 0
    @State private var from = Date().addingTimeInterval(-30 * 86400)
    @State private var to = Date()
    @State private var r = JSON(nil)
    @State private var ready = false
    @State private var edit: JSON?
    @State private var adding = false

    private static let pers = [("week", "Неделя"), ("month", "Месяц"), ("quarter", "Квартал"), ("year", "Год"), ("custom", "Свой")]
    private var input: [String: Any] {
        ["orders": admin.data["orders"].arrAny, "products": admin.data["products"].arrAny, "expenses": admin.data["expenses"].arrAny, "finance": admin.data["finance"].raw ?? [String: Any](), "receipts": admin.data["receipts"].arrAny]
    }
    private func ymd(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: d) }
    private func recalc() { if ready { r = eng.report(input, kind: kind, shift: shift, from: ymd(from), to: ymd(to)) } }

    var body: some View {
        List {
            Section {
                PillTabs(items: [("report", "Отчёт"), ("ops", "Операции"), ("costs", "Себестоимость"), ("settings", "Настройки")], value: $tab)
                if tab == "report" || tab == "ops" {
                    PillTabs(items: AdminFinance.pers, value: $kind)
                    if kind == "custom" {
                        DatePicker("С", selection: $from, displayedComponents: .date); DatePicker("По", selection: $to, displayedComponents: .date)
                    } else {
                        HStack {
                            Button { shift += 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                            Spacer(); Text(r["period"]["label"].str).font(Theme.font(15, .medium)); Spacer()
                            Button { shift = max(0, shift - 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).disabled(shift == 0)
                        }
                    }
                    Button { adding = true } label: { Label("Операция: расход или доход", systemImage: "plus").font(Theme.font(15, .medium)) }
                }
            }
            if let e = eng.error { Text(e).font(Theme.font(13)).foregroundStyle(Theme.danger) }
            if !ready { ProgressView() }
            else if tab == "report" { report }
            else if tab == "ops" { ops }
            else if tab == "costs" { FinanceCosts() }
            else { FinanceSettings() }
        }
        .navigationTitle("Финансы").navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() }; ready = await eng.ready(); recalc() }
        .onChange(of: kind) { _ in shift = 0; recalc() }.onChange(of: shift) { _ in recalc() }.onChange(of: from) { _ in recalc() }.onChange(of: to) { _ in recalc() }
        .onChange(of: admin.data["expenses"].arrAny.count) { _ in recalc() }
        .refreshable { await admin.load(); recalc() }
        .sheet(isPresented: $adding) { ExpenseSheet(expense: nil) { Task { await admin.load(); recalc() } } }
        .sheet(item: Binding(get: { edit.map { IdentJSON(j: $0) } }, set: { edit = $0?.j })) { w in ExpenseSheet(expense: w.j) { Task { await admin.load(); recalc() } } }
    }

    // MARK: Отчёт
    @ViewBuilder private var report: some View {
        let c = r["cur"], p = r["prev"], rev = c["revenue"].double ?? 0, net = c["net"].double ?? 0
        Section {
            if (c["missingUnits"].int ?? 0) > 0 { Text("У \(c["missingUnits"].int ?? 0) проданных вещей не указана себестоимость — прибыль завышена. Заполните во вкладке «Себестоимость».").font(Theme.font(13)).foregroundStyle(Theme.warn) }
            HStack(spacing: 8) {
                kpi("Выручка", rev, p["revenue"].double ?? 0)
                kpi("Чистая прибыль", net, p["net"].double ?? 0)
            }
            HStack(spacing: 8) {
                AdminStat(title: "С каждых 100 ₽", value: rev > 0 ? "\(Int((net / rev * 100).rounded())) ₽" : "—")
                AdminStat(title: "Заказов", value: "\(c["orders"].int ?? 0)")
                AdminStat(title: "Средний чек", value: (c["avg"].double ?? 0) > 0 ? Fmt.rub(Int(c["avg"].double ?? 0)) : "—")
            }
            Text("Сравнение с " + r["period"]["prevLabel"].str).font(Theme.font(12)).foregroundStyle(Theme.muted)
        }
        Section("Что видно из отчёта") {
            ForEach(r["tips"].array.indices, id: \.self) { i in
                let t = r["tips"].array[i]
                VStack(alignment: .leading, spacing: 3) {
                    Text(t["title"].str).font(Theme.font(12, .medium)).foregroundStyle(t["kind"].str == "g" ? Theme.ok : t["kind"].str == "w" ? Theme.warn : Theme.muted)
                    Text(t["text"].str).font(Theme.font(14.5)); Text(t["hint"].str).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                }
            }
        }
        Section("Прибыль и убытки") {
            line("Продажи", c["sales"].double); line("Возвраты", -(c["refunds"].double ?? 0))
            line("Выручка", c["revenue"].double, bold: true)
            line("Себестоимость проданного", -(c["cogs"].double ?? 0)); line("Валовая прибыль", c["gross"].double, bold: true)
            ForEach(c["byLine"]["variable"].array.indices, id: \.self) { i in let x = c["byLine"]["variable"].array[i]; line("  " + x["name"].str, -(x["amount"].double ?? 0), small: true) }
            line("Продажа и доставка", -(c["variable"].double ?? 0)); line("Маржинальная прибыль", c["contribution"].double, bold: true)
            ForEach(c["byLine"]["fixed"].array.indices, id: \.self) { i in let x = c["byLine"]["fixed"].array[i]; line("  " + x["name"].str, -(x["amount"].double ?? 0), small: true) }
            line("Работа магазина", -(c["fixed"].double ?? 0)); line("Прибыль до налога", c["ebt"].double, bold: true)
            line("Налог (" + String(format: "%g", r["finance"]["taxRate"].double ?? 0).replacingOccurrences(of: ".", with: ",") + "%)", -(c["tax"].double ?? 0))
            line("Чистая прибыль", c["net"].double, bold: true)
        }
        Section("Живые деньги") {
            line("Пришло", c["cashIn"].double); line("Ушло", -(c["cashOut"].double ?? 0)); line("Остаток за период", c["cash"].double, bold: true)
            if (c["taxLeft"].double ?? 0) > 0 { line("Отложить на налог", c["taxLeft"].double) }
        }
        Section("По месяцам") {
            let ms = r["months"].array, mx = max(1, ms.map { abs($0["p"]["revenue"].double ?? 0) }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(ms.indices, id: \.self) { i in
                    let m = ms[i], v = m["p"]["revenue"].double ?? 0, n = m["p"]["net"].double ?? 0
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.surface2).frame(height: CGFloat(max(0, v) / mx) * 120)
                            RoundedRectangle(cornerRadius: 4).fill(n >= 0 ? Theme.ink : Theme.danger).frame(height: CGFloat(abs(n) / mx) * 120)
                        }.frame(height: 120, alignment: .bottom)
                        Text(m["label"].str).font(Theme.font(10.5)).foregroundStyle(Theme.muted)
                    }.frame(maxWidth: .infinity)
                }
            }.padding(.vertical, 6)
            Text("Серым — выручка, чёрным — чистая прибыль").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
        }
        Section("Прибыль по моделям") {
            if r["products"].array.isEmpty { Text("Продаж за период нет").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
            ForEach(r["products"].array.indices, id: \.self) { i in
                let x = r["products"].array[i]
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(x["name"].str).font(Theme.font(14.5)); Spacer(); Text(x["missing"].bool ? "нет себестоимости" : Fmt.rub(Int(x["profit"].double ?? 0))).font(Theme.font(14, .medium)).foregroundStyle(x["missing"].bool ? Theme.warn : Theme.text) }
                    Text("\(x["units"].int ?? 0) шт. · выручка \(Fmt.rub(Int(x["revenue"].double ?? 0)))" + (x["missing"].bool ? "" : " · \(Fmt.rub(Int(x["perUnit"].double ?? 0))) с вещи · \(Int(((x["margin"].double ?? 0) * 100).rounded()))%")).font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
            }
        }
        Section("Склад") {
            let s = r["stock"]
            HStack(spacing: 8) { AdminStat(title: "Вещей на складе", value: "\(s["units"].int ?? 0)"); AdminStat(title: "По себестоимости", value: Fmt.rub(Int(s["atCost"].double ?? 0))); AdminStat(title: "По цене продажи", value: Fmt.rub(Int(s["atPrice"].double ?? 0))) }
            if s["fastest"].exists { Text("Быстрее всего продаётся: \(s["fastest"]["name"].str) — \(s["fastest"]["sold"].int ?? 0) шт. за 30 дней").font(Theme.font(13)) }
            if s["stale"].exists { Text("Лежит без продаж: \(s["stale"]["name"].str) — \(s["stale"]["left"].int ?? 0) шт.").font(Theme.font(13)) }
            ForEach(s["low"].array.indices, id: \.self) { i in let x = s["low"].array[i]; Text("Заканчивается: \(x["name"].str), \(x["color"].str), \(x["size"].str) — осталось \(x["stock"].int ?? 0)").font(Theme.font(13)).foregroundStyle(Theme.warn) }
        }
    }
    private func kpi(_ t: String, _ v: Double, _ prev: Double) -> some View {
        let d = prev != 0 ? Int(((v - prev) / abs(prev) * 100).rounded()) : nil
        return AdminStat(title: t, value: Fmt.rub(Int(v.rounded())), sub: d.map { ($0 >= 0 ? "▲ " : "▼ ") + "\(abs($0))%" } ?? "")
    }
    private func line(_ t: String, _ v: Double?, bold: Bool = false, small: Bool = false) -> some View {
        let n = Int((v ?? 0).rounded())
        return HStack { Text(t).font(Theme.font(small ? 12.5 : 14, bold ? .medium : .regular)).foregroundStyle(small ? Theme.muted : Theme.text); Spacer(); Text((n < 0 ? "− " : "") + Fmt.rub(abs(n))).font(Theme.font(small ? 12.5 : 14, bold ? .medium : .regular)).foregroundStyle(n < 0 && !bold ? Theme.muted : Theme.text) }
    }

    // MARK: Операции
    @ViewBuilder private var ops: some View {
        let list = r["ops"].array.filter { !$0["hidden"].bool }.sorted { $0["date"].str > $1["date"].str }
        Section("Операции · \(list.count)") {
            if list.isEmpty { Text("Операций за период нет").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
            ForEach(list.indices, id: \.self) { i in
                let x = list[i], inc = x["dir"].str == "in"
                Button { if !x["expense"].str.isEmpty, let e = admin.data["expenses"].array.first(where: { $0["id"].str == x["expense"].str }) { edit = e } } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(x["cat"].str).font(Theme.font(14)).foregroundStyle(Theme.text)
                            Text([x["date"].str, x["order"]["number"].string.map { "заказ № " + $0 } ?? "", x["note"].str, x["auto"].bool ? "авто" : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(11.5)).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                        Spacer()
                        Text((inc ? "+ " : "− ") + Fmt.rub(Int(abs(x["amount"].double ?? 0).rounded()))).font(Theme.font(14, .medium)).foregroundStyle(inc ? Theme.ok : Theme.text)
                    }
                }.disabled(x["expense"].str.isEmpty)
            }
        }
    }
}

/// Добавить или изменить операцию вручную: дата, категория, сумма, комментарий; удалить
struct ExpenseSheet: View {
    let expense: JSON?
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var admin = Admin.shared
    @State private var date = Date()
    @State private var cat = ""
    @State private var amount = ""
    @State private var note = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        let cats = admin.data["finance"]["categories"].array
        NavigationStack {
            Form {
                DatePicker("Дата", selection: $date, displayedComponents: .date).environment(\.locale, Locale(identifier: "ru_RU"))
                Picker("Категория", selection: $cat) { ForEach(cats.indices, id: \.self) { i in Text(cats[i]["name"].str).tag(cats[i]["id"].str) } }
                TextField("Сумма, ₽", text: $amount).keyboardType(.decimalPad)
                TextField("Комментарий", text: $note)
                if let error { Text(error).foregroundStyle(Theme.danger) }
                Button(expense == nil ? "Добавить" : "Сохранить") { Task { await save() } }.disabled(busy)
                if let e = expense { Button("Удалить операцию", role: .destructive) { Task { await remove(e["id"].str) } } }
            }
            .font(Theme.font(15))
            .navigationTitle(expense == nil ? "Новая операция" : "Операция").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onAppear {
                if let e = expense { date = DateParse.ymd(e["date"].str) ?? Date(); cat = e["categoryId"].str; amount = String(format: "%g", e["amount"].double ?? 0); note = e["note"].str }
                else if cat.isEmpty { cat = cats.first?["id"].str ?? "" }
            }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let b: [String: Any] = ["date": f.string(from: date), "categoryId": cat, "amount": Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0, "note": note]
        do {
            if let e = expense { _ = try await API.shared.json("PUT", "admin/finance/expenses/\(e["id"].str)", body: b) } else { _ = try await AdminAPI.post("finance/expenses", b) }
            done(); dismiss()
        } catch { self.error = error.userMessage }
    }
    private func remove(_ id: String) async {
        do { _ = try await API.shared.raw("DELETE", "admin/finance/expenses/\(id)"); done(); dismiss() } catch { self.error = error.userMessage }
    }
}

enum DateParse {
    static func ymd(_ s: String) -> Date? { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.date(from: s) }
}

/// Себестоимость одной вещи по каждому товару
struct FinanceCosts: View {
    @ObservedObject private var admin = Admin.shared
    @State private var costs: [String: String] = [:]
    @State private var busy = false
    var body: some View {
        Section {
            Text("Цена пошива одной вещи: ткань, пошив, фурнитура, упаковка. Нужна, чтобы считать прибыль. «Приход товара» пересчитывает её сам.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            ForEach(admin.data["products"].array.indices, id: \.self) { i in
                let p = admin.data["products"].array[i], id = p["id"].str
                HStack {
                    VStack(alignment: .leading, spacing: 2) { Text(p["name"].str).font(Theme.font(14)); Text("цена \(Fmt.rub(p["price"].int ?? 0))").font(Theme.font(11.5)).foregroundStyle(Theme.muted) }
                    Spacer()
                    TextField("—", text: Binding(get: { costs[id] ?? "" }, set: { costs[id] = $0.filter { $0.isNumber || $0 == "," || $0 == "." } })).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    Text("₽").foregroundStyle(Theme.muted)
                }
            }
            Button("Сохранить себестоимость") { Task { await save() } }.font(Theme.font(15, .medium)).disabled(busy)
        }
        .onAppear { if costs.isEmpty { for (k, v) in admin.data["finance"]["costs"].dict { costs[k] = String(format: "%g", v.double ?? 0) } } }
    }
    private func save() async {
        busy = true; defer { busy = false }
        var v: [String: Any] = [:]
        for p in admin.data["products"].array { let s = costs[p["id"].str] ?? ""; v[p["id"].str] = s.isEmpty ? "" : (Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0) }
        do { _ = try await API.shared.json("PUT", "admin/finance/costs", body: ["costs": v]); await admin.load(); Toast.shared.show("Себестоимость сохранена") } catch { Toast.shared.show(error.userMessage) }
    }
}

/// Ставки налога и комиссий, категории расходов
struct FinanceSettings: View {
    @ObservedObject private var admin = Admin.shared
    @StateObject private var doc = Doc([:])
    @State private var loaded = false
    var body: some View {
        Section {
            DefForm(defs: [FDef(k: "taxRate", label: "Налог УСН «Доходы», %", kind: .number),
                           FDef(k: "sbpYk", label: "СБП: комиссия ЮKassa, %", kind: .number), FDef(k: "sbpPartner", label: "СБП: комиссия партнёра, %", kind: .number),
                           FDef(k: "otherYk", label: "Карты и другие: комиссия ЮKassa, %", kind: .number), FDef(k: "otherPartner", label: "Карты и другие: комиссия партнёра, %", kind: .number),
                           FDef(k: "partnerMin", label: "Комиссия партнёра не меньше, ₽ с платежа", kind: .number),
                           FDef(k: "codFee", label: "СДЭК за наложенный платёж, %", kind: .number),
                           FDef(k: "categories", label: "Категории расходов и доходов", kind: .rows([FDef(k: "name", label: "Название"), FDef(k: "kind", label: "Вид", kind: .select([("variable", "Продажа и доставка"), ("fixed", "Работа магазина"), ("purchase", "Закупка товара"), ("tax", "Налоги и взносы"), ("income", "Доход")]))]))], doc: doc)
            Button("Сохранить") { Task { await save() } }.font(Theme.font(15, .medium))
        }
        .onAppear {
            guard !loaded else { return }
            let f = admin.data["finance"]
            doc.v = ["taxRate": f["taxRate"].double ?? 2, "sbpYk": f["rates"]["sbp"]["yk"].double ?? 0.4, "sbpPartner": f["rates"]["sbp"]["partner"].double ?? 1.5,
                     "otherYk": f["rates"]["other"]["yk"].double ?? 2.8, "otherPartner": f["rates"]["other"]["partner"].double ?? 1, "partnerMin": f["partnerMin"].double ?? 0.65,
                     "codFee": f["codFee"].double ?? 0, "categories": f["categories"].arrAny]
            loaded = true
        }
    }
    private func save() async {
        let d = JSON(doc.v)
        var cats = (doc.v["categories"] as? [[String: Any]]) ?? []
        for i in cats.indices where (cats[i]["id"] as? String ?? "").hasPrefix("r") || (cats[i]["id"] as? String ?? "").isEmpty { cats[i]["id"] = uid("fc") }
        let v: [String: Any] = ["taxRate": d["taxRate"].double ?? 0, "rates": ["sbp": ["yk": d["sbpYk"].double ?? 0, "partner": d["sbpPartner"].double ?? 0], "other": ["yk": d["otherYk"].double ?? 0, "partner": d["otherPartner"].double ?? 0]],
                                "partnerMin": d["partnerMin"].double ?? 0, "codFee": d["codFee"].double ?? 0, "categories": cats, "costs": admin.data["finance"]["costs"].raw ?? [String: Any]()]
        do { _ = try await API.shared.json("PUT", "admin/finance/settings", body: ["value": v]); await admin.load(); Toast.shared.show("Сохранено") } catch { Toast.shared.show(error.userMessage) }
    }
}

// MARK: - Аналитика: посетители, просмотры, конверсия, выручка, воронка, источники, Метрика, поиск

struct AdminAnalytics: View {
    @ObservedObject private var admin = Admin.shared
    @State private var n = 7
    @State private var mk = ""
    @State private var webvisor = false
    @State private var ya = ""
    @State private var go = ""
    @State private var indexnow = true
    static let src = ["instagram": "Instagram", "telegram": "Telegram", "vk": "ВКонтакте", "yandex": "Яндекс", "google": "Google", "direct": "Прямые заходы", "other": "Другие сайты"]

    private func days(_ n: Int) -> [[String: Any]] {
        let st = admin.data["stats"]
        let ord = admin.orders.filter { $0.payMethod != "exchange" && $0.status != "canceled" && !($0.payMethod == "online" && !["paid", "refunded"].contains($0.payStatus)) }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Europe/Moscow")
        return (0..<n).reversed().map { i in
            let d = f.string(from: Date().addingTimeInterval(-Double(i) * 86400))
            var x = st[d].dictAny; x["day"] = d
            let list = ord.filter { $0.createdAt.map { f.string(from: $0) } == d }
            x["o"] = list.count; x["rev"] = list.reduce(0) { $0 + $1.total - ($1.raw["refunded"].int ?? 0) }
            return x
        }
    }
    private func sum(_ ds: [[String: Any]]) -> [String: Any] {
        var t: [String: Int] = [:], src: [String: Int] = [:], m = 0, d = 0
        for x in ds { let j = JSON(x)
            for k in ["v", "p", "c", "k", "pv", "o", "rev"] { t[k, default: 0] += j[k].int ?? 0 }
            for (k, v) in j["src"].dict { src[k, default: 0] += v.int ?? 0 }
            m += j["dev"]["m"].int ?? 0; d += j["dev"]["d"].int ?? 0
        }
        var out: [String: Any] = t; out["src"] = src; out["m"] = m; out["d"] = d; return out
    }
    private func pct(_ a: Int, _ b: Int) -> String { b > 0 ? String(format: "%.1f%%", Double(min(a, b)) / Double(b) * 100).replacingOccurrences(of: ".", with: ",") : "—" }

    var body: some View {
        let ds = days(n), t = JSON(sum(ds)), prev = JSON(sum(Array(days(n * 2).prefix(n))))
        let v = t["v"].int ?? 0, o = t["o"].int ?? 0, rev = t["rev"].int ?? 0
        let maxV = max(1, ds.map { JSON($0)["v"].int ?? 0 }.max() ?? 1)
        List {
            Section {
                Text("Своя статистика сайта: без cookie и без персональных данных покупателей. Каждый посетитель считается один раз в день.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                Picker("", selection: $n) { Text("7 дней").tag(7); Text("30 дней").tag(30) }.pickerStyle(.segmented)
                HStack(spacing: 8) { AdminStat(title: "Посетители", value: Fmt.num(v), sub: delta(v, prev["v"].int ?? 0)); AdminStat(title: "Просмотры", value: Fmt.num(t["pv"].int ?? 0)) }
                HStack(spacing: 8) { AdminStat(title: "Конверсия", value: pct(o, v), sub: "\(o) зак."); AdminStat(title: "Выручка", value: Fmt.rub(rev), sub: delta(rev, prev["rev"].int ?? 0)); AdminStat(title: "Средний чек", value: o > 0 ? Fmt.rub(rev / o) : "—") }
                if v == 0 { Text("Статистика только начала собираться. Цифры появятся, как только на сайт зайдут первые покупатели.").font(Theme.font(13)).foregroundStyle(Theme.warn) }
            }
            Section("Воронка") {
                let steps = [("Зашли на сайт", v), ("Открыли товар", t["p"].int ?? 0), ("Положили в корзину", t["c"].int ?? 0), ("Начали оформление", t["k"].int ?? 0), ("Оформили заказ", o)]
                ForEach(steps.indices, id: \.self) { i in
                    HStack { Text(steps[i].0).font(Theme.font(14)); Spacer(); Text(Fmt.num(steps[i].1)).font(Theme.font(14, .medium)); if i > 0 { Text(pct(steps[i].1, steps[i - 1].1)).font(Theme.font(12)).foregroundStyle(Theme.muted).frame(width: 56, alignment: .trailing) } }
                }
            }
            Section("Посетители и заказы по дням") {
                HStack(alignment: .bottom, spacing: n == 7 ? 8 : 2) {
                    ForEach(ds.indices, id: \.self) { i in
                        let x = JSON(ds[i])
                        VStack(spacing: 2) {
                            if (x["o"].int ?? 0) > 0 { Text("\(x["o"].int ?? 0)").font(Theme.font(9)).foregroundStyle(Theme.accent) }
                            RoundedRectangle(cornerRadius: 3).fill(Theme.ink).frame(height: max(2, CGFloat(x["v"].int ?? 0) / CGFloat(maxV) * 110))
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 130, alignment: .bottom)
                Text("Столбик — посетители, число над ним — заказы за день").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            }
            Section("Откуда приходят") {
                let src = t["src"].dict.map { ($0.key, $0.value.int ?? 0) }.sorted { $0.1 > $1.1 }, tot = max(1, src.reduce(0) { $0 + $1.1 })
                if src.isEmpty { Text("Пока нет данных").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                ForEach(src, id: \.0) { s in HStack { Text(AdminAnalytics.src[s.0] ?? s.0).font(Theme.font(14)); Spacer(); Text("\(s.1) · \(Int(Double(s.1) / Double(tot) * 100))%").font(Theme.font(13)).foregroundStyle(Theme.muted) } }
                if (t["m"].int ?? 0) + (t["d"].int ?? 0) > 0 { Text("С телефона " + pct(t["m"].int ?? 0, (t["m"].int ?? 0) + (t["d"].int ?? 0)) + " визитов").font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                Text("Ссылки в соцсетях лучше размечать: ?utm_source=instagram — тогда переходы считаются точно").font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
            if admin.can("marketing") {
                Section("Яндекс Метрика") {
                    TextField("Номер счётчика, например 98765432", text: $mk).keyboardType(.numberPad)
                    Toggle("Вебвизор — записи визитов", isOn: $webvisor).tint(Theme.ink)
                    Button("Сохранить") { Task { await saveMetrika() } }.font(Theme.font(15, .medium))
                    if !mk.isEmpty, let u = URL(string: "https://metrika.yandex.ru/dashboard?id=\(mk)") { Link("Открыть Метрику", destination: u) }
                }
                Section("Поиск: Яндекс и Google") {
                    let info = admin.data["seo"]
                    Text("Карта сайта: \(info["url"].str)/sitemap.xml · \(info["pages"].int ?? 0) стр. Фид товаров: \(info["url"].str)/yml.xml").font(Theme.font(12.5)).foregroundStyle(Theme.muted).textSelection(.enabled)
                    Text("Оповещение Яндекса: " + (info["indexnow"].bool ? "включено" : info["https"].bool ? "выключено" : "нужен HTTPS")).font(Theme.font(13))
                    TextField("Код Яндекс Вебмастера", text: $ya).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Код Google Search Console", text: $go).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Toggle("Сразу сообщать Яндексу о новых и изменённых товарах", isOn: $indexnow).tint(Theme.ink)
                    Button("Сохранить") { Task { await saveSeo() } }.font(Theme.font(15, .medium))
                    Button("Отправить все страницы в Яндекс") { Task { do { let r = try await AdminAPI.post("seo-ping"); await admin.load(); Toast.shared.show("Яндекс получил \(r["last"]["count"].int ?? 0) адресов") } catch { Toast.shared.show(error.userMessage) } } }
                }
            }
        }
        .font(Theme.font(15))
        .navigationTitle("Аналитика").navigationBarTitleDisplayMode(.inline)
        .task {
            if !admin.data.exists { await admin.load() }
            let s = admin.data["settings"]; mk = s["metrika"]["id"].str; webvisor = s["metrika"]["webvisor"].bool
            ya = s["seo"]["yandex"].str; go = s["seo"]["google"].str; indexnow = !(s["seo"]["indexnow"].exists && !s["seo"]["indexnow"].bool)
        }
        .refreshable { await admin.load() }
    }
    private func delta(_ a: Int, _ b: Int) -> String { guard b > 0 else { return "" }; let d = Int((Double(a - b) / Double(b) * 100).rounded()); return (d >= 0 ? "▲ " : "▼ ") + "\(abs(d))%" }
    private func code(_ v: String) -> String {
        if let r = v.range(of: #"content\s*=\s*["']([^"']+)["']"#, options: .regularExpression) { return String(v[r]).components(separatedBy: CharacterSet(charactersIn: "\"'"))[1] }
        return v.trimmingCharacters(in: .whitespaces)
    }
    private func saveMetrika() async {
        let id = mk.filter(\.isNumber)
        if !mk.isEmpty && !(5...12).contains(id.count) { Toast.shared.show("Номер счётчика — это 5–12 цифр"); return }
        var s = admin.data["settings"].dictAny; s["metrika"] = ["id": id, "webvisor": webvisor]
        do { try await AdminAPI.saveSettings(s); await admin.load(); Toast.shared.show(id.isEmpty ? "Метрика отключена" : "Метрика подключена") } catch { Toast.shared.show(error.userMessage) }
    }
    private func saveSeo() async {
        let a = code(ya), b = code(go)
        let bad = { (c: String) in !c.isEmpty && c.range(of: #"^[A-Za-z0-9_-]{6,120}$"#, options: .regularExpression) == nil }
        if bad(a) || bad(b) { Toast.shared.show("Код — это латинские буквы и цифры. Скопируйте его из кабинета ещё раз"); return }
        var s = admin.data["settings"].dictAny; var seo = (s["seo"] as? [String: Any]) ?? [:]; seo["yandex"] = a; seo["google"] = b; seo["indexnow"] = indexnow; s["seo"] = seo
        do { try await AdminAPI.saveSettings(s); await admin.load(); Toast.shared.show("Сохранено. Теперь нажмите «Проверить» в кабинете поисковика") } catch { Toast.shared.show(error.userMessage) }
    }
}
