import Foundation
import os

/// Ключи гостевых заказов: секрет из ссылки /order/<номер>?t=<ключ> открывает заказ без входа — с именем, телефоном и
/// адресом покупателя. Ключи сохраняют оформление заказа, покупка сертификата и ссылка из письма или push; читают
/// «Мои заказы» гостя, экран заказа и заявка на возврат или обмен; стирает выход и удаление аккаунта (Shop.forgetUser).
///
/// На телефоне хранится не больше `limit` ключей (L8-08): при сохранении 51-го забывается сохранённый раньше всех.
/// Порядок — порядок сохранения. Ключ, сохранённый снова (ссылка из письма на старый заказ), становится последним и не
/// дублируется: заказ, который покупатель открывает сейчас, не вытесняется. Забытый ключ стирается только с телефона —
/// заказ на сервере остаётся и по-прежнему открывается по ссылке из письма (ключ из ссылки сохраняется заново).
///
/// Формат в UserDefaults: массив пар [номер, ключ] от старой к новой. До этапа L.8.5 — словарь [номер: ключ] без порядка;
/// он переписывается один раз (migrate, при запуске) — порядок восстанавливается по времени создания из номера заказа.
/// Чтение и запись — под замком: одновременные сохранения не теряют ключи (каждое читает список, уже изменённый другим)
enum OrderTokens {
    static let limit = 50
    static let storeKey = "orderTokens"
    private static let lock = OSAllocatedUnfairLock()

    static func save(_ id: String, _ t: String) {
        lock.withLockUnchecked {
            var list = load().filter { $0[0] != id }
            list.append([id, t])
            store(Array(list.suffix(limit)))
        }
    }
    /// Номер заказа → ключ
    static var all: [String: String] {
        lock.withLockUnchecked { Dictionary(load().map { ($0[0], $0[1]) }, uniquingKeysWith: { _, last in last }) }
    }
    static func clear() { lock.withLockUnchecked { UserDefaults.standard.removeObject(forKey: storeKey) } }
    /// Прежний словарь — в список не длиннее limit. Повторный вызов ничего не меняет: список уже в новом формате
    static func migrate() { lock.withLockUnchecked { _ = load() } }

    /// Пары [номер, ключ] от старой к новой. Прежний словарь переписывается здесь же. Записи нет или она другого типа —
    /// пусто; неполные пары и пары без номера пропускаются. Следующее сохранение запишет список заново
    private static func load() -> [[String]] {
        let raw = UserDefaults.standard.object(forKey: storeKey)
        if let list = raw as? [[String]] { return list.filter { $0.count == 2 && !$0[0].isEmpty } }
        guard let old = raw as? [String: String] else { return [] }
        let list = old.map { [$0.key, $0.value] }.sorted { a, b in
            let x = createdAt(a[0]) ?? Int.min, y = createdAt(b[0]) ?? Int.min
            return x != y ? x < y : a[0] < b[0]
        }
        let kept = Array(list.suffix(limit))
        store(kept)
        return kept
    }
    private static func store(_ list: [[String]]) { UserDefaults.standard.set(list, forKey: storeKey) }

    /// Время создания заказа (мс) из номера: сервер выдаёт "o" + Date.now() в base36 + 8 шестнадцатеричных знаков
    /// (albakov-shop, server.js, uid). Номер другого вида — nil: при переписывании словаря такой ключ считается самым старым
    private static func createdAt(_ id: String) -> Int? {
        guard id.hasPrefix("o"), id.count >= 17, id.suffix(8).allSatisfy(\.isHexDigit) else { return nil }
        return Int(id.dropFirst().dropLast(8), radix: 36)
    }
}
