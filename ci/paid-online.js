'use strict';
/* Только для аудита в CI (этап J, M-2), в приложение и на сайт не входит.
   Помечает заказ копии магазина оплаченным онлайн: в копии нет ЮKassa, а экран «Вернуть деньги» в панели
   показывается только у оплаченных онлайн заказов. Расчёт суммы возврата (dry) к ЮKassa не обращается.
   Запуск при остановленном магазине: node ci/paid-online.js <путь к albakov.sqlite> <id заказа> */
const { DatabaseSync } = require('node:sqlite');
const [file, id] = process.argv.slice(2);
const db = new DatabaseSync(file);
const row = db.prepare("SELECT data FROM records WHERE coll = 'orders' AND id = ?").get(id);
if (!row) { console.error('Заказ не найден: ' + id); process.exit(1); }
const o = JSON.parse(row.data);
o.payment = Object.assign({}, o.payment, { method: 'online', status: 'paid', providerId: 'audit-' + id });
db.prepare("UPDATE records SET data = ? WHERE coll = 'orders' AND id = ?").run(JSON.stringify(o), id);
console.log('Заказ № ' + o.number + ' помечен оплаченным онлайн (только копия магазина)');
