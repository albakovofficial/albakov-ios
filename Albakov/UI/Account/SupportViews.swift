import SwiftUI
import PhotosUI
import ImageIO

// Поддержка (1.0.1, вариант B — как на сайте 13.64.3): у обращения свой номер, тема, заказ и статус.
// Покупатель: список обращений, переписка с фото и отметкой «прочитано», новое обращение — тема плиткой, заказ карточкой.
// Панель: поиск по всем обращениям, заметки для сотрудников, шаблоны ответов, «Взять себе», карточка покупателя.

enum Support {
    static let state = ["open": "Ждёт ответа", "answered": "Есть ответ", "closed": "Решено"]
    static let adminState = ["open": "Ждёт ответа", "answered": "Отвечено", "closed": "Решено"]
    static let topicIcon = ["Заказ": "bag", "Доставка": "shippingbox", "Размер и посадка": "ruler", "Возврат и обмен": "arrow.uturn.left", "Другое": "ellipsis"]

    static func time(_ iso: String) -> String {
        guard let d = ISO.date(iso) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMMM"
        return f.string(from: d)
    }
    static func clock(_ iso: String) -> String {
        guard let d = ISO.date(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    static func day(_ iso: String) -> String {
        guard let d = ISO.date(iso) else { return "" }
        if Calendar.current.isDateInToday(d) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(d) { return "Вчера" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMMM"; return f.string(from: d)
    }
    /// Последнее сообщение без заметок сотрудников: «Фото», если текста нет
    static func preview(_ t: JSON) -> (shop: Bool, text: String) {
        let last = t["messages"].array.filter { $0["from"].str != "note" }.last ?? JSON(nil)
        let text = last["text"].str.isEmpty ? (last["files"].array.isEmpty ? "" : "Фото") : last["text"].str
        return (last["from"].str == "shop", text)
    }
    /// Фото к сообщению из данных файла (аудит IOS-03): JPEG для отправки — до 1600 px по длинной стороне, качество 0,85
    /// (быстро уходит и с мобильного интернета) — и миниатюра для полоски выбранных фото.
    /// Снимок раскодируется один раз и сразу в размере 1600 px (48 Мп целиком — это ≈190 МБ);
    /// миниатюра уменьшается уже из этой картинки
    static func photo(_ data: Data) -> (jpeg: Data, thumbnail: UIImage)? {
        guard let image = downsample(data, maxPixel: 1600), let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        return (jpeg, resized(image, maxPixel: thumbPixels))
    }
    /// Миниатюра для полоски выбранных фото: 64 pt на экране 3x — хватает 300 px по длинной стороне
    static let thumbPixels: CGFloat = 300
    /// Уменьшенная копия уже раскодированной картинки, не крупнее исходной
    private static func resized(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let k = min(1, maxPixel / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * k).rounded(), height: (image.size.height * k).rounded())
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    /// Уменьшенная копия снимка (ImageIO): с учётом поворота из EXIF, не крупнее исходника.
    /// Полноразмерная картинка в памяти не создаётся
    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let side = max(w, h) > 0 ? min(maxPixel, CGFloat(max(w, h))) : maxPixel   // не увеличиваем, как и раньше
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true,
                                     kCGImageSourceThumbnailMaxPixelSize: side]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// «№ 1043» — номер обращения; в работе — цветом раздела
struct SupNumber: View {
    let number: String
    var on = true
    var body: some View {
        Text("№ " + number).font(Theme.font(12, .semibold)).monospacedDigit()
            .foregroundStyle(on ? Theme.accent : Theme.muted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.tint : Theme.surface))
    }
}

/// Статус: «Есть ответ» — заливка цветом раздела, «Решено» — зелёный с галочкой
struct SupStatus: View {
    let status: String
    var admin = false
    var body: some View {
        HStack(spacing: 4) {
            if status == "closed" { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            Text((admin ? Support.adminState : Support.state)[status] ?? status).font(Theme.font(12, .medium))
        }
        .foregroundStyle(status == "answered" ? .white : status == "closed" ? Theme.ok : Theme.muted)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(status == "answered" ? Theme.accent : status == "closed" ? Theme.ok.opacity(0.1) : Theme.surface))
    }
}

// MARK: - Фото к сообщению

/// Выбранные фото: загружаются сразу, в сообщение уходят их имена (до 5).
/// В памяти держим только миниатюры (аудит IOS-03): исходный снимок нужен лишь на время уменьшения
@MainActor
final class SupportAttachments: ObservableObject {
    /// image — миниатюра для полоски (до 300 px), не исходный снимок
    struct Item: Identifiable { let id = UUID(); let image: UIImage; var name: String? }
    @Published var items: [Item] = []
    /// Отправка JPEG на сервер → имя файла. По умолчанию — запрос магазина по адресу uploadPath; в тестах подменяется
    typealias Upload = (Data) async throws -> String
    private let upload: Upload
    init(uploadPath: String, upload: Upload? = nil) {
        self.upload = upload ?? { jpg in
            try await API.shared.json("POST", uploadPath, body: ["dataUrl": "data:image/jpeg;base64," + jpg.base64EncodedString()])["file"].str
        }
    }

    /// Идёт обработка выбранных фото (чтение и уменьшение). Пока она идёт, новый выбор фото и отправка недоступны:
    /// иначе смена выбора отменила бы обработку, а сообщение ушло бы без части фото (ревью этапа A.1)
    @Published private(set) var loading = false
    var busy: Bool { loading || items.contains { $0.name == nil } }
    var names: [String] { items.compactMap(\.name) }
    var left: Int { max(0, 5 - items.count) }

    /// Выбранные фото по одному. Вызывается из .task(id:) экрана. Если экран ушёл (его закрыли или открыли поверх другой),
    /// задача отменяется: оставшиеся фото не обрабатываются и не отправляются, выбор сбрасывается — фото выбирают заново.
    /// Так задумано: обработка занимает около секунды на фото, держать её после ухода с экрана незачем
    func add(_ picks: [PhotosPickerItem]) async {
        loading = true; defer { loading = false }
        for p in picks.prefix(left) {
            if Task.isCancelled { return }
            let data: Data?
            do { data = try await p.loadTransferable(type: Data.self) }
            catch { if !error.isCancel { Toast.shared.show("Не получилось открыть фото") }; continue }
            guard let data else { Toast.shared.show("Не получилось открыть фото"); continue }
            await add(data)
        }
    }
    /// Одно фото из данных файла: JPEG для отправки и миниатюра готовятся вне главного потока
    /// (Task.detached: раскодирование тяжёлое). Дальше держим только миниатюру и JPEG 1600 px;
    /// исходные данные живут до конца этого вызова, то есть и во время отправки, — по одному снимку за раз
    func add(_ data: Data) async {
        let photo = await Task.detached(priority: .userInitiated) { Support.photo(data) }.value
        if Task.isCancelled { return }   // экран закрыли, пока фото готовилось, — не показываем и не отправляем
        guard let photo else { Toast.shared.show("Не получилось открыть фото"); return }
        let item = Item(image: photo.thumbnail, name: nil)
        items.append(item)
        do {
            let name = try await upload(photo.jpeg)
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].name = name }
        } catch {
            items.removeAll { $0.id == item.id }
            Toast.shared.show(error.userMessage)
        }
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    func clear() { items = [] }
}

/// Полоска выбранных фото над полем ввода
struct AttachmentStrip: View {
    @ObservedObject var att: SupportAttachments
    var body: some View {
        if !att.items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(att.items) { it in
                        Image(uiImage: it.image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay { if it.name == nil { ProgressView().tint(.white).frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.35))) } }
                            .overlay(alignment: .topTrailing) {
                                Button { att.remove(it.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(Circle().fill(.black.opacity(0.7)))
                                }.padding(4).accessibilityLabel("Убрать фото")
                            }
                    }
                }
            }
        }
    }
}

/// Фото в переписке: открываются на весь экран
struct SupportPhotos: View {
    let files: [String]
    let base: String
    @State private var open: String?
    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: min(files.count, 3))
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(files, id: \.self) { f in
                Button { open = f } label: {
                    RemoteImage(path: base + f).frame(height: files.count == 1 ? 240 : 110).clipShape(RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityLabel("Фото")
            }
        }
        .frame(width: files.count == 1 ? 190 : 250)
        .fullScreenCover(item: Binding(get: { open.map { PhotoRef(path: base + $0) } }, set: { open = $0?.path == nil ? nil : open })) { ref in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                RemoteImage(path: ref.path, contentMode: .fit).ignoresSafeArea()
                Button { open = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.18)))
                }.padding(16).accessibilityLabel("Закрыть")
            }
        }
    }
}
struct PhotoRef: Identifiable { let path: String; var id: String { path } }

// MARK: - Переписка (покупатель и панель)

/// Лента сообщений: разделители по дням, свои — справа цветом раздела, магазина — слева со знаком AV,
/// заметки сотрудников — жёлтые, в конце отметка «Вопрос решён»
struct SupportThread: View {
    let t: JSON
    /// true — смотрит сотрудник: свои сообщения — ответы магазина
    var admin = false
    var body: some View {
        let msgs = t["messages"].array
        let base = admin ? "api/admin/support/file/" : "api/support/file/"
        let readAt = admin ? t["userReadAt"].str : t["shopReadAt"].str
        LazyVStack(spacing: 10) {
            ForEach(Array(msgs.enumerated()), id: \.offset) { i, m in
                let day = Support.day(m["at"].str)
                if i == 0 || Support.day(msgs[i - 1]["at"].str) != day { DayPill(text: day) }
                if m["from"].str == "note" { NoteBubble(m: m) }
                else { Bubble(m: m, mine: (m["from"].str == "shop") == admin, admin: admin, who: admin ? t["name"].str : "", read: !readAt.isEmpty && readAt >= m["at"].str, base: base) }
            }
            if t["status"].str == "closed" {
                HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)); Text(admin ? "Обращение решено" : "Вопрос решён · можно написать снова").font(Theme.font(12, .medium)) }
                    .foregroundStyle(Theme.ok).padding(.horizontal, 11).padding(.vertical, 5).background(Capsule().fill(Theme.ok.opacity(0.1))).padding(.top, 4)
            }
        }
    }
}

private struct DayPill: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.font(12, .medium)).foregroundStyle(Theme.dim).padding(.horizontal, 11).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2)).padding(.top, 6)
    }
}

private struct NoteBubble: View {
    let m: JSON
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Заметка · " + (m["by"].string ?? "сотрудник")).font(Theme.font(12, .semibold)).foregroundStyle(Theme.warn)
            Text(m["text"].str).font(Theme.font(14.5)).foregroundStyle(Theme.text).textSelection(.enabled)
            Text(Support.clock(m["at"].str)).font(Theme.font(11)).foregroundStyle(Theme.dim)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#fbf4e2")))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: "#d9c48a"), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

private struct Bubble: View {
    let m: JSON
    let mine: Bool
    let admin: Bool
    let who: String
    let read: Bool
    let base: String
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 48) }
            if !mine { Avatar(text: admin ? String(who.prefix(1)).uppercased() : "AV", dark: !admin) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if !m["text"].str.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        if !mine { Text(admin ? (who.isEmpty ? "Покупатель" : who) : Shop.shared.settings.storeName + (m["by"].str.isEmpty ? "" : " · " + m["by"].str)).font(Theme.font(12.5, .semibold)).foregroundStyle(Theme.accent) }
                        Text(m["text"].str).font(Theme.font(15)).foregroundStyle(mine ? .white : Theme.text).textSelection(.enabled)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(BubbleShape(mine: mine).fill(mine ? Theme.accent : .white))
                    .overlay { if !mine { BubbleShape(mine: false).stroke(Theme.line, lineWidth: 1) } }
                }
                if !m["files"].array.isEmpty { SupportPhotos(files: m["files"].array.map(\.str), base: base) }
                HStack(spacing: 4) {
                    if admin && mine && !m["by"].str.isEmpty { Text(m["by"].str + " ·") }
                    Text(Support.clock(m["at"].str))
                    if mine {
                        Image(systemName: read ? "checkmark.circle.fill" : "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(read ? Theme.accent : Theme.dim)
                            .accessibilityLabel(read ? "Прочитано" : "Отправлено")
                    }
                }.font(Theme.font(11)).foregroundStyle(Theme.dim)
            }
            if !mine { Spacer(minLength: 40) }
        }
    }
}

private struct Avatar: View {
    let text: String
    var dark = true
    var body: some View {
        Text(text).font(Theme.font(11, .semibold)).foregroundStyle(dark ? .white : Theme.accent)
            .frame(width: 30, height: 30).background(Circle().fill(dark ? Theme.ink : Theme.tint))
    }
}

/// Пузырь: скругление 20, у своих сообщений нижний правый угол острее, у собеседника — нижний левый
private struct BubbleShape: Shape {
    let mine: Bool
    func path(in r: CGRect) -> Path {
        let big = min(20, r.height / 2, r.width / 2), small = min(6, big)
        let bl = mine ? big : small, br = mine ? small : big
        var p = Path()
        p.move(to: CGPoint(x: r.minX + big, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - big, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - big, y: r.minY + big), radius: big, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + big))
        p.addArc(center: CGPoint(x: r.minX + big, y: r.minY + big), radius: big, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Поле ввода: скрепка (фото), текст, круглая кнопка отправки цветом раздела
struct SupportComposer: View {
    @Binding var draft: String
    @ObservedObject var att: SupportAttachments
    var placeholder = "Сообщение"
    var busy = false
    let send: () -> Void
    @State private var picks: [PhotosPickerItem] = []
    var body: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && att.names.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            AttachmentStrip(att: att)
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $picks, maxSelectionCount: max(1, att.left), matching: .images) {
                    Image(systemName: "paperclip").font(.system(size: 18, weight: .regular)).foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44).overlay(Circle().strokeBorder(Theme.line))
                }
                .disabled(att.left == 0 || att.busy).accessibilityLabel("Прикрепить фото")
                .task(id: picks) { guard !picks.isEmpty else { return }; await att.add(picks); picks = [] }   // экран ушёл — обработка фото отменяется
                TextField(placeholder, text: $draft, axis: .vertical).font(Theme.font(15)).lineLimit(1...5)
                    .padding(.horizontal, 16).padding(.vertical, 11).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
                Button(action: send) {
                    Group { if busy || att.busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold)) } }
                        .foregroundStyle(.white).frame(width: 44, height: 44).background(Circle().fill(Theme.accent.opacity(empty ? 0.35 : 1)))
                }.disabled(empty || busy || att.busy).accessibilityLabel("Отправить")
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 10)
        .background(Color.white.overlay(alignment: .top) { Divider1() })
    }
}

/// Карточка заказа над перепиской: фото, номер и статус, первая вещь
struct SupportOrderCard: View {
    let o: JSON
    var body: some View {
        let name = [o["name"].str, [o["color"].str, o["size"].str].filter { !$0.isEmpty }.joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " · ")
        HStack(spacing: 12) {
            RemoteImage(path: o["image"].str).frame(width: 42, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Заказ № \(o["number"].str) · \((Order.statusRu[o["status"].str] ?? "").lowercased())").font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
                Text(name + ((o["items"].int ?? 1) > 1 ? " и ещё \((o["items"].int ?? 1) - 1)" : "")).font(Theme.font(12.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.dim)
        }
        .padding(9).padding(.trailing, 4).softCard(18)
    }
}

// MARK: - Покупатель: список обращений

struct SupportListView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var shop: Shop
    @State private var tickets: [JSON] = []
    @State private var topics: [String] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var compose = false
    var body: some View {
        let open = tickets.filter { $0["status"].str != "closed" }, done = tickets.filter { $0["status"].str == "closed" }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button { compose = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.pencil").font(.system(size: 18)).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Написать в поддержку").font(Theme.font(16, .semibold))
                            Text(hours + "Ответ придёт сюда, на почту и уведомлением").font(Theme.font(12.5)).opacity(0.82).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white).padding(16).background(RoundedRectangle(cornerRadius: 22).fill(Theme.accentGradient))
                }.buttonStyle(Pressable())
                if !open.isEmpty { group(open) }
                if !done.isEmpty {
                    Text("РЕШЁННЫЕ").font(Theme.font(12, .medium)).kerning(0.9).foregroundStyle(Theme.dim).padding(.horizontal, 4).padding(.top, 8)
                    group(done)
                }
                if let loadError, tickets.isEmpty {
                    EmptyState.loadFailed(loadError) { Task { await load() } }.padding(.horizontal, -Theme.gutter).padding(.top, 6)
                } else if !loading && tickets.isEmpty {
                    Text("Обращений пока нет. Напишите — номер обращения появится сразу, по нему вас быстро найдут.").font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 6)
                }
            }.padding(Theme.gutter)
        }
        .background(Theme.surface.opacity(0.6))
        .overlay { if loading && tickets.isEmpty { ProgressView() } }
        .navigationTitle("Поддержка").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $compose) { NewTicketSheet(topics: topics) { id in compose = false; Task { await load() }; router.push(.ticket(id), on: .account) } }
    }
    private var hours: String {
        let h = shop.settings.hours
        return h.isEmpty ? "" : "Отвечаем " + h.prefix(1).lowercased() + h.dropFirst() + ". "
    }
    private func group(_ list: [JSON]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, t in
                if i > 0 { Divider1() }
                Button { router.push(.ticket(t["id"].str), on: .account) } label: { TicketCard(t: t) }.buttonStyle(.plain)
            }
        }
        .softCard(22)
    }
    private func load() async {
        defer { loading = false }
        do {
            let r = try await API.shared.json("GET", "support")
            tickets = r["tickets"].array; topics = r["topics"].array.map(\.str); loadError = nil
        } catch {
            guard let m = error.userMessage else { return }   // загрузку отменили (ушли с экрана)
            if tickets.isEmpty { loadError = m } else { Toast.shared.show(m) }   // список уже есть — оставляем его
        }
    }
}

private struct TicketCard: View {
    let t: JSON
    var body: some View {
        let p = Support.preview(t), closed = t["status"].str == "closed"
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                SupNumber(number: t["number"].str, on: !closed)
                Text(t["topic"].str).font(Theme.font(15.5, .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if t["unread"].bool { Circle().fill(Theme.accent).frame(width: 10, height: 10).accessibilityLabel("Новый ответ") }
            }
            (Text(p.shop ? Shop.shared.settings.storeName + ": " : "Вы: ").font(Theme.font(14, p.shop ? .semibold : .regular)) + Text(p.text).font(Theme.font(14)))
                .foregroundStyle(t["unread"].bool ? Theme.text : Theme.muted).lineLimit(2).multilineTextAlignment(.leading)
            HStack(spacing: 10) {
                SupStatus(status: t["status"].str)
                if !t["orderNumber"].str.isEmpty { Text("Заказ № " + t["orderNumber"].str) }
                Spacer()
                Text(Support.time(t["updatedAt"].str))
            }.font(Theme.font(12.5)).foregroundStyle(Theme.dim)
        }
        .foregroundStyle(Theme.text).padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

// MARK: - Покупатель: новое обращение

struct NewTicketSheet: View {
    let topics: [String]
    let created: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var att = SupportAttachments(uploadPath: "support/upload")
    @State private var topic = ""
    @State private var text = ""
    @State private var orders: [JSON] = []
    @State private var orderId = ""
    @State private var busy = false
    @State private var error: String?
    @State private var picks: [PhotosPickerItem] = []
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    caption("О чём вопрос")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(topics.filter { $0 != "Другое" }, id: \.self) { tile($0) }
                    }
                    if topics.contains("Другое") { tile("Другое", wide: true) }
                    if !orders.isEmpty {
                        caption("Какой заказ").padding(.top, 6)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(orders.prefix(8).enumerated()), id: \.offset) { _, o in orderCard(o) }
                                Button { orderId = "" } label: {
                                    Text("Без заказа").font(Theme.font(13, .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 62)
                                        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(orderId.isEmpty ? Theme.accent : Theme.line, lineWidth: orderId.isEmpty ? 2 : 1))
                                }.buttonStyle(.plain)
                            }.padding(.vertical, 1)
                        }
                    }
                    caption("Сообщение").padding(.top, 6)
                    TextField("Что случилось и чем помочь", text: $text, axis: .vertical).font(Theme.font(15.5)).lineLimit(4...10)
                        .padding(14).background(RoundedRectangle(cornerRadius: 18).fill(.white)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line))
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $picks, maxSelectionCount: max(1, att.left), matching: .images) {
                            Image(systemName: "photo").font(.system(size: 20, weight: .light)).foregroundStyle(Theme.muted).frame(width: 64, height: 64)
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        .disabled(att.left == 0 || att.busy).accessibilityLabel("Добавить фото")
                        .task(id: picks) { guard !picks.isEmpty else { return }; await att.add(picks); picks = [] }   // экран ушёл — обработка фото отменяется
                        if att.items.isEmpty { Text("Фото вещи или бирки — до 5 штук. Так ответим быстрее").font(Theme.font(13)).foregroundStyle(Theme.dim) }
                        else { AttachmentStrip(att: att) }
                    }
                    ErrorText(text: error)
                    PrimaryButton(title: "Отправить", busy: busy || att.busy, disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && att.names.isEmpty) { Task { await send() } }
                    Text("Номер обращения появится сразу — по нему вас быстро найдут").font(Theme.font(12.5)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
                }.padding(Theme.gutter)
            }
            .background(Theme.surface.opacity(0.6))
            .navigationTitle("Новое обращение").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onAppear { if topic.isEmpty { topic = topics.last ?? "" } }
            .task { if let r = try? await API.shared.json("GET", "orders") { orders = r["orders"].array } }
        }
    }
    private func caption(_ s: String) -> some View { Text(s.uppercased()).font(Theme.font(12, .medium)).kerning(0.9).foregroundStyle(Theme.dim).padding(.horizontal, 4) }
    private func tile(_ t: String, wide: Bool = false) -> some View {
        let on = topic == t
        return Button { topic = t; Haptic.tap() } label: {
            Group {
                if wide {
                    HStack(spacing: 10) { Image(systemName: Support.topicIcon[t] ?? "ellipsis").font(.system(size: 18, weight: .light)); Text(t).font(Theme.font(14.5, .medium)); Spacer() }
                } else {
                    VStack(alignment: .leading, spacing: 10) { Image(systemName: Support.topicIcon[t] ?? "ellipsis").font(.system(size: 20, weight: .light)); Text(t).font(Theme.font(14.5, .medium)).multilineTextAlignment(.leading); Spacer(minLength: 0) }
                }
            }
            .foregroundStyle(on ? .white : Theme.text).padding(14).frame(maxWidth: .infinity, minHeight: wide ? 50 : 92, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(on ? Theme.accent : .white))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(on ? Theme.accent : Theme.line))
        }.buttonStyle(.plain)
    }
    private func orderCard(_ o: JSON) -> some View {
        let on = orderId == o["id"].str
        let img = o["items"].array.first { !$0["image"].str.isEmpty }?["image"].str ?? ""
        return Button { orderId = o["id"].str; topic = topic == "Другое" ? "Заказ" : topic } label: {
            HStack(spacing: 10) {
                RemoteImage(path: img).frame(width: 34, height: 42).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("№ " + o["number"].str).font(Theme.font(13.5, .semibold))
                    Text((Order.statusRu[o["status"].str] ?? "").lowercased()).font(Theme.font(12)).foregroundStyle(Theme.dim)
                }
            }
            .foregroundStyle(Theme.text).padding(9).padding(.trailing, 6).frame(height: 62)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(on ? Theme.accent : Theme.line, lineWidth: on ? 2 : 1))
        }.buttonStyle(.plain)
    }
    private func send() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let r = try await API.shared.json("POST", "support", body: ["topic": topic, "orderId": orderId, "text": text, "files": att.names])
            Haptic.success(); Toast.shared.show("Обращение № \(r["ticket"]["number"].str) отправлено")
            created(r["ticket"]["id"].str)
        } catch { self.error = error.userMessage; Haptic.error() }
    }
}

// MARK: - Покупатель: переписка

struct TicketView: View {
    let id: String
    @EnvironmentObject private var router: Router
    @StateObject private var att = SupportAttachments(uploadPath: "support/upload")
    @State private var t = JSON(nil)
    @State private var loadError: String?
    @State private var draft = ""
    @State private var busy = false
    var body: some View {
        let closed = t["status"].str == "closed"
        VStack(spacing: 0) {
            if let loadError, !t.exists { EmptyState.loadFailed(loadError) { Task { await load() } }.padding(.top, 24) }
            if t["order"].exists {
                Button { router.push(.order(t["order"]["id"].str), on: .account) } label: { SupportOrderCard(o: t["order"]) }.buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.top, 10)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    SupportThread(t: t).padding(.horizontal, 14).padding(.vertical, 12)
                    Color.clear.frame(height: 1).id("end")
                }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: t["messages"].array.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            if t.exists {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if !closed { chip("Вопрос решён", icon: "checkmark") { Task { await close() } } }
                        if t["order"].exists {
                            let swap = ["Возврат и обмен", "Размер и посадка"].contains(t["topic"].str)
                            chip(swap ? "Обменять размер или вернуть" : "Открыть заказ № " + t["order"]["number"].str) { router.push(.order(t["order"]["id"].str), on: .account) }
                        }
                    }.padding(.horizontal, 12)
                }.padding(.bottom, 8)
            }
            SupportComposer(draft: $draft, att: att, placeholder: closed ? "Написать — обращение откроется снова" : "Сообщение", busy: busy) { Task { await send() } }
        }
        .background(Theme.surface.opacity(0.6))
        .navigationTitle(t["number"].string.map { "Обращение № " + $0 } ?? "Обращение").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(t["number"].string.map { "Обращение № " + $0 } ?? "Обращение").font(Theme.font(16, .semibold))
                    if t.exists { Text(t["topic"].str + " · " + (Support.state[t["status"].str] ?? "").lowercased()).font(Theme.font(11.5)).foregroundStyle(t["status"].str == "answered" ? Theme.accent : Theme.dim) }
                }
            }
        }
        .task { await load(); await poll() }
        .refreshable { await load() }
    }
    private func chip(_ title: String, icon: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ok) }
                Text(title).font(Theme.font(13.5, .medium))
            }
            .foregroundStyle(Theme.text).padding(.horizontal, 14).frame(height: 36).background(Capsule().fill(.white)).overlay(Capsule().strokeBorder(Theme.lineStrong))
        }.buttonStyle(Pressable())
    }
    private func load() async {
        do {
            t = try await API.shared.json("GET", "support/\(id)")["ticket"]; loadError = nil
            await Shop.shared.refreshUser()
        } catch {
            guard let m = error.userMessage else { return }   // загрузку отменили (ушли с экрана)
            if t.exists { Toast.shared.show(m) } else { loadError = m }   // переписка уже на экране — оставляем её
        }
    }
    // Пока переписка открыта, ответы магазина и отметка «прочитано» подгружаются сами.
    // Ошибка фонового обновления не показывается: через 15 секунд будет следующая попытка
    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if Task.isCancelled { break }
            if let r = try? await API.shared.json("GET", "support/\(id)") { t = r["ticket"] }
        }
    }
    private func send() async {
        busy = true; defer { busy = false }
        do {
            let r = try await API.shared.json("POST", "support/\(id)", body: ["text": draft, "files": att.names])
            t = r["ticket"]; draft = ""; att.clear(); Haptic.tap()
        } catch { Toast.shared.show(error.userMessage); Haptic.error() }
    }
    private func close() async {
        do { t = try await API.shared.json("POST", "support/\(id)/close")["ticket"]; Haptic.success(); Toast.shared.show("Рады, что помогли") }
        catch { Toast.shared.show(error.userMessage); Haptic.error() }
    }
}

// MARK: - Панель: все обращения с поиском

struct AdminSupportView: View {
    @EnvironmentObject private var router: Router
    @State private var tickets: [JSON] = []
    @State private var filter = "active"
    @State private var q = ""
    @State private var loading = true
    @State private var loadError: String?
    private let filters = [("active", "В работе"), ("open", "Ждут ответа"), ("closed", "Решённые"), ("all", "Все")]
    var body: some View {
        let shown = tickets.filter { (q.isEmpty ? match(filter, $0) : true) && Self.search($0, q) }
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filters, id: \.0) { f in
                            Button { filter = f.0 } label: {
                                HStack(spacing: 5) { Text(f.1); Text("\(tickets.filter { match(f.0, $0) }.count)").opacity(0.6) }
                                    .font(Theme.font(13, .medium)).foregroundStyle(filter == f.0 && q.isEmpty ? .white : Theme.text)
                                    .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(filter == f.0 && q.isEmpty ? Theme.ink : Theme.surface))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)).listRowSeparator(.hidden)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, t in
                Button { router.push(.adminTicket(t["id"].str), on: .account) } label: { AdminTicketRow(t: t) }
            }
            if let loadError, tickets.isEmpty {
                EmptyState.loadFailed(loadError) { Task { await load() } }.listRowSeparator(.hidden).listRowInsets(EdgeInsets())
            } else if !loading && shown.isEmpty {
                Text(q.isEmpty ? "Здесь пусто." : "Ничего не нашлось. Ищем по номеру обращения, имени, телефону, почте, номеру заказа и тексту.").font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.plain)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "№, имя, телефон, почта, заказ, текст")
        .navigationTitle("Поддержка").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }
    private func match(_ f: String, _ t: JSON) -> Bool {
        switch f {
        case "all": return true
        case "closed": return t["status"].str == "closed"
        case "open": return t["status"].str == "open"
        default: return t["status"].str != "closed"
        }
    }
    /// Поиск как на сайте: номер, имя, почта, номер заказа, тема и текст переписки; телефон — по цифрам
    static func search(_ t: JSON, _ raw: String) -> Bool {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "№", with: "").trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        let hay = ([t["number"].str, t["name"].str, t["email"].str, t["orderNumber"].str, t["topic"].str] + t["messages"].array.map { $0["text"].str }).joined(separator: " ").lowercased()
        if hay.contains(q) { return true }
        let d = q.filter(\.isNumber)
        return d.count >= 4 && t["phone"].str.filter(\.isNumber).contains(d)
    }
    private func load() async {
        defer { loading = false }
        do { tickets = try await API.shared.json("GET", "admin/support")["tickets"].array; loadError = nil }
        catch {
            guard let m = error.userMessage else { return }   // загрузку отменили (ушли с экрана)
            if tickets.isEmpty { loadError = m } else { Toast.shared.show(m) }   // список уже есть — оставляем его
        }
    }
}

private struct AdminTicketRow: View {
    let t: JSON
    var body: some View {
        let p = Support.preview(t)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                SupNumber(number: t["number"].str, on: t["status"].str != "closed")
                Text(t["name"].string ?? "Покупатель").font(Theme.font(15, .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if t["unreadShop"].bool { Circle().fill(Theme.accent).frame(width: 9, height: 9) }
                Text(Support.time(t["updatedAt"].str)).font(Theme.font(12)).foregroundStyle(Theme.dim)
            }
            Text(t["topic"].str + (t["orderNumber"].str.isEmpty ? "" : " · заказ № " + t["orderNumber"].str) + (t["assignee"]["name"].str.isEmpty ? "" : " · " + t["assignee"]["name"].str))
                .font(Theme.font(12.5)).foregroundStyle(Theme.dim)
            Text((p.shop ? "Вы: " : "") + p.text).font(Theme.font(13.5, t["unreadShop"].bool ? .medium : .regular)).foregroundStyle(t["unreadShop"].bool ? Theme.text : Theme.muted).lineLimit(2)
            SupStatus(status: t["status"].str, admin: true)
        }.foregroundStyle(Theme.text).padding(.vertical, 4)
    }
}

// MARK: - Панель: переписка, заметки, шаблоны, карточка покупателя

struct AdminTicketView: View {
    let id: String
    @EnvironmentObject private var router: Router
    @StateObject private var att = SupportAttachments(uploadPath: "admin/support/upload")
    @State private var t = JSON(nil)
    @State private var customer = JSON(nil)
    @State private var loadError: String?
    @State private var templates: [JSON] = []
    /// Шаблоны загружены. До этого редактор шаблонов закрыт: открытый с пустым списком, он сохранил бы пустоту
    /// поверх настоящих шаблонов (Q-3)
    @State private var templatesLoaded = false
    @State private var draft = ""
    @State private var note = false
    @State private var busy = false
    @State private var showCustomer = false
    @State private var editTemplates = false
    var body: some View {
        let closed = t["status"].str == "closed"
        let mine = t["assignee"]["id"].str == (Shop.shared.user?.id ?? "")
        VStack(spacing: 0) {
            if let loadError, !t.exists { EmptyState.loadFailed(loadError) { Task { await load() } }.padding(.top, 24) }
            if t.exists {
                HStack(spacing: 8) {
                    Text(info).font(Theme.font(12)).foregroundStyle(Theme.dim).lineLimit(2)
                    Spacer(minLength: 4)
                    if t["order"].exists {
                        Button("Заказ № " + t["order"]["number"].str) { router.push(.adminOrder(t["order"]["id"].str), on: .account) }.font(Theme.font(12.5, .medium)).buttonStyle(.bordered).tint(Theme.ink)
                    }
                }.padding(.horizontal, 14).padding(.vertical, 8).background(.white)
                Divider1()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    SupportThread(t: t, admin: true).padding(.horizontal, 14).padding(.vertical, 12)
                    Color.clear.frame(height: 1).id("end")
                }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: t["messages"].array.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(templates.enumerated()), id: \.offset) { _, x in
                        Button(x["title"].str) { draft = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? x["text"].str : draft + "\n\n" + x["text"].str }
                            .font(Theme.font(12.5)).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(.white)).overlay(Capsule().strokeBorder(Theme.line))
                    }
                    Button("Шаблоны…") { editTemplates = true }.disabled(!templatesLoaded).font(Theme.font(12.5)).foregroundStyle(Theme.muted).padding(.horizontal, 12).frame(height: 32)
                        .overlay(Capsule().strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    Toggle(isOn: $note) { Text("Заметка").font(Theme.font(12.5, .medium)) }.toggleStyle(.button).tint(Theme.warn).controlSize(.small)
                }.padding(.horizontal, 12)
            }.padding(.vertical, 6)
            SupportComposer(draft: $draft, att: att, placeholder: note ? "Заметка для сотрудников" : "Ответ покупателю", busy: busy) { Task { await send() } }
                .background(note ? Color(hex: "#fbf4e2") : .white)
        }
        .background(Theme.surface.opacity(0.6))
        .navigationTitle(t["number"].string.map { "№ " + $0 } ?? "Обращение").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text((t["number"].string.map { "№ " + $0 + " · " } ?? "") + t["topic"].str).font(Theme.font(15, .semibold))
                    Text(t["name"].string ?? "").font(Theme.font(11.5)).foregroundStyle(Theme.dim)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showCustomer = true } label: { Label("Покупатель", systemImage: "person.crop.circle") }
                    Button { Task { await patch(["assign": !mine]) } } label: { Label(mine ? "Снять с себя" : "Взять себе", systemImage: "person.badge.plus") }
                    Button { Task { await patch(["status": closed ? "open" : "closed"]) } } label: { Label(closed ? "Открыть снова" : "Решено", systemImage: closed ? "arrow.uturn.left" : "checkmark.circle") }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 18)) }
            }
        }
        .sheet(isPresented: $showCustomer) { SupportCustomerSheet(c: customer, name: t["name"].str).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $editTemplates) { SupportTemplatesSheet(list: templates.map { ($0["title"].str, $0["text"].str) }) { templates = $0 } }
        .task { await load(); await poll() }
    }
    private var info: String {
        var s = "Создано " + Support.time(t["createdAt"].str)
        if let a = ISO.date(t["createdAt"].str), let b = ISO.date(t["firstReplyAt"].str) { s += " · ответили за " + Self.ago(b.timeIntervalSince(a)) }
        if !t["assignee"]["name"].str.isEmpty { s += " · ведёт " + t["assignee"]["name"].str }
        return s
    }
    static func ago(_ sec: TimeInterval) -> String {
        let m = max(1, Int(sec / 60))
        return m < 60 ? "\(m) мин" : m < 1440 ? "\(m / 60) ч" : "\(m / 1440) дн"
    }
    private func load() async {
        do {
            let r = try await API.shared.json("GET", "admin/support/\(id)")
            t = r["ticket"]; customer = r["customer"]; loadError = nil
            // отметка «прочитано» — попутная: не получилось — отметится при следующем открытии
            if t["unreadShop"].bool { _ = try? await API.shared.raw("PATCH", "admin/support/\(id)", body: ["read": true]) }
        } catch {
            guard let m = error.userMessage else { return }   // загрузку отменили (ушли с экрана)
            if t.exists { Toast.shared.show(m) } else { loadError = m }   // переписка уже на экране — оставляем её
        }
        guard !templatesLoaded else { return }
        do { templates = try await API.shared.json("GET", "admin/support")["templates"].array; templatesLoaded = true }
        catch { if let m = error.userMessage { Toast.shared.show("Шаблоны ответов не загрузились: " + m) } }
    }
    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if Task.isCancelled { break }
            if let r = try? await API.shared.json("GET", "admin/support/\(id)") { t = r["ticket"] }
        }
    }
    private func patch(_ b: [String: Any]) async {
        do { _ = try await API.shared.raw("PATCH", "admin/support/\(id)", body: b); await load(); Haptic.success() }
        catch { Toast.shared.show(error.userMessage) }
    }
    private func send() async {
        busy = true; defer { busy = false }
        do {
            let r = try await API.shared.json("POST", "admin/support/\(id)", body: ["text": draft, "files": note ? [String]() : att.names, "note": note])
            t = r["ticket"]; draft = ""; att.clear(); Haptic.success()
            Toast.shared.show(note ? "Заметка сохранена" : r["mailed"].bool ? "Ответ отправлен и продублирован на почту" : "Ответ отправлен")
            note = false
        } catch { Toast.shared.show(error.userMessage); Haptic.error() }
    }
}

/// Карточка покупателя: контакты, бонусы, заказы и прошлые обращения
private struct SupportCustomerSheet: View {
    let c: JSON
    let name: String
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if c.exists {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c["name"].string ?? name).font(Theme.font(18, .semibold))
                            Text("С нами с " + Fmt.date(ISO.date(c["createdAt"].str))).font(Theme.font(12.5)).foregroundStyle(Theme.dim)
                        }
                        if !c["phone"].str.isEmpty, let u = URL(string: "tel:+" + c["phone"].str.filter(\.isNumber)) { Link(Fmt.phone(c["phone"].str), destination: u) }
                        if !c["email"].str.isEmpty, let u = URL(string: "mailto:" + c["email"].str) { Link(c["email"].str, destination: u) }
                        Text("Бонусы: \(c["bonus"].int ?? 0)")
                    }
                    if !c["orders"].array.isEmpty {
                        Section("Заказы") {
                            ForEach(Array(c["orders"].array.enumerated()), id: \.offset) { _, o in
                                Button { dismiss(); router.push(.adminOrder(o["id"].str), on: .account) } label: {
                                    HStack { Text("№ " + o["number"].str + " · " + (Order.statusRu[o["status"].str] ?? "").lowercased()); Spacer(); Text(Fmt.rub(o["total"].int ?? 0)).foregroundStyle(Theme.dim) }
                                }
                            }
                        }
                    }
                    if !c["tickets"].array.isEmpty {
                        Section("Другие обращения") {
                            ForEach(Array(c["tickets"].array.enumerated()), id: \.offset) { _, x in
                                Button { dismiss(); router.push(.adminTicket(x["id"].str), on: .account) } label: {
                                    HStack { Text("№ " + x["number"].str + " · " + x["topic"].str); Spacer(); Text((Support.adminState[x["status"].str] ?? "").lowercased()).foregroundStyle(Theme.dim) }
                                }
                            }
                        }
                    }
                } else {
                    Text(name.isEmpty ? "Аккаунт удалён" : name + " — аккаунт удалён").foregroundStyle(Theme.muted)
                }
            }
            .font(Theme.font(14.5)).foregroundStyle(Theme.text)
            .navigationTitle("Покупатель").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

/// Шаблоны ответов: название кнопки и текст, одни на всех сотрудников (как на сайте)
private struct SupportTemplatesSheet: View {
    @State var list: [(String, String)]
    let saved: ([JSON]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                ForEach(list.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Название", text: Binding(get: { list[i].0 }, set: { list[i].0 = $0 })).font(Theme.font(15, .medium))
                        TextField("Текст ответа", text: Binding(get: { list[i].1 }, set: { list[i].1 = $0 }), axis: .vertical).font(Theme.font(14)).lineLimit(2...6)
                    }.padding(.vertical, 4)
                }
                .onDelete { list.remove(atOffsets: $0) }
                Button { list.append(("", "")) } label: { Label("Добавить шаблон", systemImage: "plus") }
            }
            .navigationTitle("Шаблоны ответов").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { Task { await save() } }.disabled(busy) }
            }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        let body: [[String: Any]] = list.map { ["title": $0.0, "text": $0.1] }
        do { let r = try await API.shared.json("PUT", "admin/support/templates", body: ["templates": body]); saved(r["templates"].array); Haptic.success(); dismiss() }
        catch { Toast.shared.show(error.userMessage) }
    }
}
