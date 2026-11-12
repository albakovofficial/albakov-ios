# Мост «сайт ↔ приложение»

Приложение открывает albakovofficial.ru во встроенном браузере (WKWebView). Сайт узнаёт приложение так:

- в User-Agent есть `AlbakovApp/1.0.0 (iOS)`;
- у `<html>` есть классы `in-app` и `in-app-ios` (ставятся до загрузки стилей);
- есть объект `window.AlbakovApp` (`platform`, `version`, `post(msg)`).

Сообщения принимаются **только от главной страницы albakovofficial.ru по https** — страница оплаты, банка или встроенная рамка звать приложение не может.

## Сайт → приложение: `window.AlbakovApp.post({...})`

| type | поля | что делает |
|---|---|---|
| `ready` | — | магазин отрисован — приложение убирает свою заставку (сайт шлёт после первой отрисовки) |
| `share` | `url`, `text` | системное окно «Поделиться». `url` может быть путём (`/product/…`) |
| `haptic` | `style`: `light` `medium` `heavy` `selection` `success` `warning` `error` | виброотклик |
| `push.request` | — | спросить разрешение на уведомления; ответ — `push.status`, затем `push.token` |
| `push.status` | — | узнать, разрешены ли уведомления; ответ — `push.status` |
| `badge` | `count` | число на значке приложения (0 — убрать) |
| `open.external` | `url` | открыть ссылку в Safari / звонилке / почте |
| `open.settings` | — | открыть настройки приложения (если уведомления выключены) |
| `app.info` | — | ответ — `app.info` (версия, сборка, iOS, окружение push) |

## Приложение → сайт: событие `albakov-native`

`window.addEventListener('albakov-native', (e) => e.detail)`:

- `push.token` `{ token, env }` — после каждой загрузки страницы, если уведомления разрешены. Сайт (`public/js/push.js`)
  отправляет его на сервер: `POST /api/push/subscribe { apns: { token, env }, scope: 'customer' | 'staff' }`.
- `push.status` `{ status: 'granted' | 'denied' | 'default' }`, `push.error` `{ message }`, `share.result` `{ completed, activity }`.

## Сервер (albakov-shop, с версии 13.61)

- Адрес устройства хранится как подписка `apns:<token>` рядом с подписками браузеров — все уведомления сайта
  (заказ, поддержка, бонусы, сотрудникам — заказы и вопросы) уходят и туда, и туда (`lib/apns.js`, HTTP/2 + JWT ES256).
- Нажатие на уведомление открывает страницу из поля `url` payload.
- Ответ Apple `410` или `400 BadDeviceToken` — адрес удаляется.
