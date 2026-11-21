import Foundation
import os

// Связь с сервером магазина albakovofficial.ru — тем же, что у сайта: товары, корзина, заказы, оплата, кабинет, панель.
// Вход хранится в куки сессии (как в браузере), HTTPCookieStorage сохраняет их между запусками.
struct APIError: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
    static let offline = APIError(message: "Нет соединения с интернетом. Проверьте связь и попробуйте ещё раз.", status: 0)
    /// Тело запроса нельзя записать в JSON: среди значений дата, NaN, бесконечность или свой тип.
    /// Запрос не отправляется. Номер -2 — чтобы не спутать с обрывом связи (0) и непонятным ответом (-1)
    static let invalidBody = APIError(message: "Не удалось подготовить запрос. Проверьте введённые числа; если не поможет — обновите приложение.", status: -2)
}

/// Тело запроса к /api/… (этап L.2.10): JSON, записанный один раз — там, где тело собрано. Data — Sendable, поэтому тело
/// передаётся в сетевой слой из любого контекста. Словарь [String: Any] не Sendable: если он связан с состоянием главного
/// актора (вычисляемое свойство экрана, корзина магазина), Swift 6 не пропускает его в неизолированный API — не может доказать,
/// что словарь больше никому не доступен. Пишется как словарь — body: ["id": id] — или RequestBody(словарь).
/// Записать нельзя (дата, NaN, свой тип) — ошибка сохраняется и выбрасывается при подготовке запроса: запрос не уходит,
/// ошибка та же (APIError.invalidBody), как раньше
struct RequestBody: Sendable, ExpressibleByDictionaryLiteral {
    fileprivate let encoded: Result<Data, any Error>
    init(_ object: [String: Any]) { encoded = Result { try JSONSerialization.checkedData(object) } }
    init(dictionaryLiteral elements: (String, Any)...) { self.init(Dictionary(uniqueKeysWithValues: elements)) }
}

extension JSONSerialization {
    /// data(withJSONObject:) с проверкой. Без неё недопустимое значение не становится ошибкой Swift,
    /// а роняет приложение исключением Objective-C — try и catch его не ловят (аудит Q-B8)
    static func checkedData(_ object: Any, options: WritingOptions = []) throws -> Data {
        guard isValidJSONObject(object) else { throw APIError.invalidBody }
        return try data(withJSONObject: object, options: options)
    }
}

// Sendable (этап L.2.7) — проверяет компилятор: все поля неизменяемые (let) и сами Sendable (URL, URLSession, JSONDecoder).
// Своего изменяемого состояния у API нет: куки — в HTTPCookieStorage, часы сервера — ServerClock под замком. Поэтому общий
// экземпляр безопасен из любого контекста, и запросы, разбор и декодирование идут вне главного актора, как раньше
final class API: Sendable {
    static let shared = API()

    let base: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    private convenience init() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AlbakovBaseURL") as? String ?? "https://albakovofficial.ru"
        self.init(base: URL(string: raw) ?? URL(string: "https://albakovofficial.ru")!, configuration: API.configuration())
    }
    /// Приложение пользуется только API.shared. Отдельный экземпляр — для юнит-тестов (этап I): та же настройка
    /// из configuration() и подмена ответов сервера через protocolClasses, как у ImageCache.init(configuration:)
    init(base: URL, configuration: URLSessionConfiguration) {
        self.base = base
        session = URLSession(configuration: configuration)
    }
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData   // цены и остатки — всегда свежие
        config.httpAdditionalHeaders = ["Accept": "application/json", "X-Albakov-App": "ios"]
        return config
    }

    /// Адрес картинки или страницы сайта: «uploads/…», «/img/…» или полный адрес.
    func url(_ path: String) -> URL? {
        if path.isEmpty { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        if path.hasPrefix("data:") { return nil }
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: clean, relativeTo: base)?.absoluteURL
    }

    /// Запрос к /api/…: ответ сервера { ok: true, … } разбирается в T, { ok: false, error } — в APIError.
    func call<T: Decodable>(_ method: String = "GET", _ path: String, body: RequestBody? = nil, query: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await raw(method, path, body: body, query: query)
        do { return try decoder.decode(T.self, from: data) }
        catch {
            #if DEBUG
            print("Не разобран ответ \(path):", error)
            #endif
            throw APIError(message: "Не удалось прочитать ответ магазина. Обновите приложение или попробуйте позже.", status: -1)
        }
    }

    /// Ответ как свободный JSON — для разделов панели, где поля меняются от настроек.
    /// Не JSON (страница вместо ответа магазина, пустой ответ) — ошибка, а не пустые данные (DEF-I1, этап I): иначе
    /// Shop.load принимал её за пустой каталог и выход покупателя. Файлы (CSV, PDF) берутся через raw
    func json(_ method: String = "GET", _ path: String, body: RequestBody? = nil, query: [String: String] = [:]) async throws -> JSON {
        let data = try await raw(method, path, body: body, query: query)
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            throw APIError(message: "Не удалось прочитать ответ магазина. Обновите приложение или попробуйте позже.", status: -1)
        }
        return JSON(value)
    }

    func raw(_ method: String, _ path: String, body: RequestBody? = nil, query: [String: String] = [:]) async throws -> Data {
        #if DEBUG
        if Demo.on, let d = try await Demo.answer(method, path, real: { try await send(method, path, body: body, query: query) }) { return d }
        #endif
        return try await send(method, path, body: body, query: query)
    }

    /// Запрос к /api/…: без тела (body == nil) — без тела и без Content-Type, как раньше.
    /// Тело, которое нельзя записать в JSON, — ошибка APIError.invalidBody, запрос не уходит
    func request(_ method: String, _ path: String, body: RequestBody?, query: [String: String]) throws -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent("api/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try body.encoded.get()
        }
        return req
    }

    private func send(_ method: String, _ path: String, body: RequestBody?, query: [String: String]) async throws -> Data {
        let req = try request(method, path, body: body, query: query)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(e.code) { throw APIError.offline }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let d = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date") { ServerClock.sync(d) }
        // Панель ответила 401 — сеанс сотрудника истёк или доступ к панели отозван (аудит SEC-1): витрина перепроверяет,
        // кто вошёл; isStaff становится false — Admin стирает данные, DestView закрывает все экраны панели вместе с их состоянием
        if status == 401, path.hasPrefix("admin/") { Task { @MainActor in await Shop.shared.refreshUser() } }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], obj["ok"] as? Bool == false || status >= 400 {
            throw APIError(message: obj["error"] as? String ?? "Что-то пошло не так. Попробуйте ещё раз.", status: status)
        }
        if status >= 400 { throw APIError(message: "Сервер магазина не ответил. Попробуйте позже.", status: status) }
        return data
    }

    /// Загрузка файла (фото товара в панели): ответ — адрес загруженной картинки.
    func upload(_ data: Data, mime: String = "image/jpeg") async throws -> String {
        let r = try await json("POST", "admin/upload", body: ["dataUrl": "data:\(mime);base64," + data.base64EncodedString()])
        return r["url"].str
    }

    func clearSession() {
        for c in HTTPCookieStorage.shared.cookies(for: base) ?? [] where c.name == "sid" { HTTPCookieStorage.shared.deleteCookie(c) }
    }
}

/// Свободный JSON с удобным доступом: j["orders"][0]["number"].string
struct JSON: Decodable {
    let value: Any?

    init(_ value: Any?) { self.value = value is NSNull ? nil : value }
    init(data: Data) { value = try? JSONSerialization.jsonObject(with: data) }
    init(from decoder: Decoder) throws {
        // Через JSONSerialization надёжнее для произвольной вложенности
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(AnyDecodable.self) { value = v.value } else { value = nil }
    }

    subscript(key: String) -> JSON { JSON((value as? [String: Any])?[key]) }
    subscript(i: Int) -> JSON { let a = value as? [Any]; return JSON(a != nil && i >= 0 && i < a!.count ? a![i] : nil) }
    var array: [JSON] { (value as? [Any])?.map { JSON($0) } ?? [] }
    var dict: [String: JSON] { (value as? [String: Any])?.mapValues { JSON($0) } ?? [:] }
    var string: String? { value as? String ?? (value as? NSNumber).map { $0.stringValue } }
    var str: String { string ?? "" }
    var int: Int? { (value as? NSNumber)?.intValue ?? (value as? String).flatMap { Int($0) } }
    var double: Double? { (value as? NSNumber)?.doubleValue }
    var bool: Bool { (value as? NSNumber)?.boolValue ?? false }
    var exists: Bool { value != nil }
    var raw: Any? { value }
}

private struct AnyDecodable: Decodable {
    let value: Any?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil }
        else if let b = try? c.decode(Bool.self) { value = NSNumber(value: b) }
        else if let i = try? c.decode(Int.self) { value = NSNumber(value: i) }
        else if let d = try? c.decode(Double.self) { value = NSNumber(value: d) }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyDecodable].self) { value = a.map { $0.value ?? NSNull() } }
        else if let o = try? c.decode([String: AnyDecodable].self) { value = o.mapValues { $0.value ?? NSNull() } }
        else { value = nil }
    }
}

/// Часы сервера (1.0.3): срок оплаты считаем по ним, а не по часам телефона — если на телефоне время сбито, отсчёт всё равно верный.
enum ServerClock {
    /// Серверное время − время телефона, в секундах. Пишется из ответов API — они разбираются вне главного потока
    /// и бывают одновременными, читается таймером оплаты в главном. Раньше — static var без защиты: гонка данных (аудит Q-B5)
    static var skew: TimeInterval { state.withLock { $0 } }
    private static let state = OSAllocatedUnfairLock(initialState: TimeInterval(0))
    /// DateFormatter потокобезопасен (iOS 7+); разбор — вне замка, под замком только запись числа
    private static let f: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "GMT"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; return f }()
    static func sync(_ header: String) {
        guard let s = offset(header) else { return }
        state.withLock { $0 = s }
    }
    /// Расхождение по заголовку Date ответа; nil — заголовок не разобран (прежнее значение остаётся)
    static func offset(_ header: String) -> TimeInterval? { f.date(from: header).map { $0.timeIntervalSinceNow + 0.5 } }
}

extension Error {
    /// Запрос отменён (ушли с экрана, ввели следующую букву) — это не ошибка для покупателя
    /// Текст ошибки для человека; отменённый запрос — nil: «отменено» нигде не показываем
    var userMessage: String? { isCancel ? nil : localizedDescription }
    /// CocoaError.userCancelled — человек сам закрыл окно выбора файла (импорт остатков)
    var isCancel: Bool { self is CancellationError || (self as? URLError)?.code == .cancelled || (self as NSError).code == NSURLErrorCancelled || (self as? CocoaError)?.code == .userCancelled }
}
