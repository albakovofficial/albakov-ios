# ALBAKOV для iPhone

Приложение интернет-магазина [albakovofficial.ru](https://albakovofficial.ru) для App Store.
SwiftUI + WKWebView: магазин внутри приложения плюс то, чего у сайта в браузере нет, — push-уведомления Apple
(заказ в пути, ждёт в пункте выдачи, ответ поддержки; сотрудникам — новые заказы и вопросы), системное «Поделиться»,
виброотклик, число на значке, ссылки albakovofficial.ru сразу в приложении, пароли из «Связки ключей», экран «Нет соединения».

- Bundle ID: `ru.albakovofficial.app`, название «ALBAKOV», iPhone, iOS 16+, светлая тема, портрет.
- Mac не нужен: проект собирается на GitHub Actions (Xcode 26 — App Store принимает только сборки Xcode 26 / iOS 26 SDK).
- Файла `.xcodeproj` в репозитории нет — его создаёт [XcodeGen](https://github.com/yonaskolb/XcodeGen) из `project.yml`.
- Оплата — как на сайте (ЮKassa): вещи — физический товар, покупки через Apple для них не нужны (правило App Store 3.1.5(a)).
  Страницы оплаты и проверки карты в банке открываются внутри приложения, после оплаты покупатель возвращается в магазин.

## Устройство

```
project.yml                     описание проекта (XcodeGen)
Albakov/App/                    точка входа, Router (ссылки, push, albakov://), заставка и «Нет соединения»
Albakov/Web/WebController.swift WKWebView, правила переходов, мост window.AlbakovApp
Albakov/Native/                 Bridge (команды сайта), PushManager (APNs), Haptics
Albakov/Resources/              Info.plist, entitlements, PrivacyInfo.xcprivacy, иконка и цвета
ci/ExportOptions.plist          настройки выгрузки в App Store Connect
.github/workflows/ios.yml       сборка и выгрузка в TestFlight
BRIDGE.md                       как сайт и приложение общаются
```

## Сборка

- **Каждый push в `main`** — проверочная сборка под симулятор (без подписи). Ошибки — во вкладке Actions.
- **Выпуск в TestFlight** — Actions → iOS → Run workflow → галочка «TestFlight» (или тег `V1.0.1` — номер версии берётся из тега).
  Номер сборки = номер запуска, растёт сам. Если Mac с `macos-26` долго не находится — выберите `macos-15-intel`.

## Что нужно один раз

1. **Секреты GitHub** — репозиторий → Settings → Secrets and variables → Actions → New repository secret:
   `APPLE_TEAM_ID` (Membership details в developer.apple.com), `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (весь текст файла `.p8`
   ключа App Store Connect API с ролью Admin).
2. **App ID** — developer.apple.com → Identifiers → `ru.albakovofficial.app` с Push Notifications и Associated Domains.
3. **Карточка приложения** — App Store Connect → Apps → «+» → New App: iOS, «ALBAKOV», русский, Bundle ID `ru.albakovofficial.app`.
4. **Ключ APNs для push** — developer.apple.com → Keys → «+» → Apple Push Notifications service. Файл `.p8`, Key ID и Team ID
   вводятся на сайте: панель → «Push-уведомления» → «Приложение iPhone» (не в этот репозиторий). С ключом сайт сам отдаёт
   файл Universal Links `https://albakovofficial.ru/.well-known/apple-app-site-association`.

## Перед отправкой на проверку

- Скриншоты iPhone 6,9" (1320×2868 или 1290×2796) — 3–10 штук.
- Политика конфиденциальности (есть на сайте), анкета «App Privacy», возрастной рейтинг.
- Тестовый аккаунт для проверяющего — в App Review Information.
- В заметках для проверяющего перечислить нативные функции (push о заказе, «Поделиться», Universal Links, виброотклик) —
  это снижает риск отказа по правилу 4.2 «сайт в обёртке».
