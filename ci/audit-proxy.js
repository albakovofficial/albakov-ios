'use strict';
/* Посредник для проверки приложения на GitHub (только аудит, в приложение не входит).
   Приложение в симуляторе ходит сюда (порт P), посредник — в копию магазина (порт T).
   Тесты управляют связью: GET /__ctl/<режим>?scope=orders|all|<путь>&ms=…
     scope: orders — только оформление заказа; all — все запросы; иначе — запросы /api/<путь>… (этап B: support, quote,
     support/upload — проверка сообщений об ошибках сети на отдельных экранах)
     on — обычная связь; off — обрыв соединения (с ms — обрыв через ms: ошибка приходит позже); slow — задержка ms;
     drop-after — запрос доходит до магазина, а ответ теряется (один раз);
     502 — ответ «502 Bad Gateway» как от nginx, когда магазин недоступен (один раз).
   GET /__ctl/stats?phone=7… — сколько заказов магазин реально создал (по ответам на POST /api/orders);
     delayed — сколько запросов задержал режим slow-once; adminData — сколько раз загружались данные панели
     (GET /api/admin/data; этап K.2: экран по прямой ссылке загружает их один раз, открытый повторно — не загружает).
   slow-once — задержка ms только для первого подходящего запроса, дальше обычная связь (этап J, M-2: ответ на
     прежний выбор приходит позже ответа на новый).
   GET /__ctl/uploads — фото, загруженные в панели (POST /api/admin/upload), по порядку: адрес на сервере, код ответа,
     размер JPEG в байтах, ширина и высота в пикселях, время загрузки (этап J: M-1 — лишние загрузки, DEF-1 — размеры).
   Запросы поддержки (/api/…support…) пишутся в журнал для диагностики фото (этап A.1): номер запроса посредника,
   метод, путь без параметров, размер тела, код ответа, время и текст ошибки магазина. Куки, токены, тело запроса
   (фото), имена файлов и личные данные не записываются. */
const http = require('http');
const [P, T] = process.argv.slice(2).map(Number);
let mode = 'on', scope = 'all', ms = 0;
const created = new Map();   // id заказа → телефон
let seq = 0;                 // номер запроса посредника — технический идентификатор в журнале
const uploads = [];          // фото панели: { url, status, bytes, w, h, ms }
let delayed = 0;             // сколько запросов задержал режим slow-once — тест проверяет, что задержка была
let adminData = 0;           // сколько раз загружались данные панели (GET /api/admin/data)
/** Ширина и высота JPEG — из заголовка кадра (SOF0–SOF15, кроме DHT/JPG/DAC), без раскодирования */
function jpegSize(b) {
  let i = 2;
  while (i + 9 < b.length && b[i] === 0xFF) {
    const m = b[i + 1], len = b.readUInt16BE(i + 2);
    if (m >= 0xC0 && m <= 0xCF && m !== 0xC4 && m !== 0xC8 && m !== 0xCC) return { h: b.readUInt16BE(i + 5), w: b.readUInt16BE(i + 7) };
    i += 2 + len;
  }
  return { w: 0, h: 0 };
}
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname.startsWith('/__ctl/')) {
    const m = u.pathname.slice(7);
    res.setHeader('Content-Type', 'application/json');
    if (m === 'uploads') return res.end(JSON.stringify({ uploads }));
    if (m === 'stats') {
      const ph = u.searchParams.get('phone');
      const ids = [...created].filter(([, p]) => !ph || p === ph).map(([id]) => id);
      return res.end(JSON.stringify({ orders: ids.length, ids, delayed, adminData }));
    }
    mode = m; scope = u.searchParams.get('scope') || 'orders'; ms = Number(u.searchParams.get('ms') || 0);
    console.log(new Date().toISOString(), 'режим', mode, scope, ms);
    return res.end('{"ok":true}');
  }
  const isOrder = req.method === 'POST' && u.pathname === '/api/orders';
  const isSupport = u.pathname.startsWith('/api/') && u.pathname.includes('support');
  const isUpload = req.method === 'POST' && u.pathname === '/api/admin/upload';
  const rid = ++seq, t0 = Date.now();
  if (req.method === 'GET' && u.pathname === '/api/admin/data') adminData++;
  const hit = scope === 'all' || (scope === 'orders' ? isOrder : u.pathname.startsWith('/api/' + scope));
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const logSupport = (status, note) => {
      if (isSupport) console.log(new Date().toISOString(), 'support #' + rid, req.method, u.pathname.replace(/\/file\/[^/]+$/, '/file/…'), 'тело', body.length, 'Б →', status, (Date.now() - t0) + ' мс', note || '');
    };
    if (hit && mode === 'off') { logSupport('обрыв (режим off' + (ms ? ', через ' + ms + ' мс' : '') + ')'); if (ms > 0) setTimeout(() => req.socket.destroy(), ms); else req.socket.destroy(); return; }
    if (hit && mode === '502') { logSupport(502, 'ответ 502 (режим 502)'); mode = 'on'; res.writeHead(502, { 'Content-Type': 'text/html' }); res.end('<html><body><center><h1>502 Bad Gateway</h1></center><hr><center>nginx</center></body></html>'); return; }
    const go = () => {
      const r2 = http.request({ host: '127.0.0.1', port: T, method: req.method, path: req.url, headers: Object.assign({}, req.headers, { host: '127.0.0.1:' + T }) }, (pr) => {
        const out = [];
        pr.on('data', (c) => out.push(c));
        pr.on('end', () => {
          const buf = Buffer.concat(out);
          if (isOrder) {
            try { const j = JSON.parse(buf); if (j.ok && j.order) created.set(j.order.id, String((j.order.customer || {}).phone || '')); } catch (e) { /* не JSON */ }
            console.log(new Date().toISOString(), 'POST /api/orders →', pr.statusCode, buf.toString().slice(0, 160));
          }
          if (isUpload) {
            // JPEG из тела запроса (dataUrl base64) — только размеры; само фото и адреса страниц в журнал не пишутся
            let bytes = 0, w = 0, h = 0, url = '';
            try { const d = Buffer.from(String(JSON.parse(body).dataUrl || '').replace(/^data:[^,]*,/, ''), 'base64'); bytes = d.length; ({ w, h } = jpegSize(d)); } catch (e) { /* не JSON */ }
            try { url = String(JSON.parse(buf).url || ''); } catch (e) { /* не JSON */ }
            uploads.push({ url, status: pr.statusCode, bytes, w, h, ms: Date.now() - t0 });
            console.log(new Date().toISOString(), 'upload #' + rid, '→', pr.statusCode, 'JPEG', bytes, 'Б', w + '×' + h, (Date.now() - t0) + ' мс');
          }
          if (isSupport) {
            let note = 'ok';
            try { const j = JSON.parse(buf); if (j.ok === false || pr.statusCode >= 400) note = 'ошибка: ' + String(j.error || '').slice(0, 120); } catch (e) { note = 'ответ не JSON, ' + buf.length + ' Б'; }
            logSupport(pr.statusCode, note + (hit && mode === 'drop-after' ? ' — ответ потерян (режим drop-after)' : ''));
          }
          if (hit && mode === 'drop-after') { mode = 'on'; req.socket.destroy(); return; }
          res.writeHead(pr.statusCode, pr.headers); res.end(buf);
        });
      });
      r2.on('error', (e) => { logSupport(502, 'магазин недоступен: ' + e.code); res.writeHead(502); res.end(); });
      r2.end(body);
    };
    if (hit && mode === 'slow-once') { mode = 'on'; delayed++; console.log(new Date().toISOString(), 'задержка', ms, 'мс один раз:', req.method, u.pathname); setTimeout(go, ms); }
    else if (hit && mode === 'slow') setTimeout(go, ms); else go();
  });
}).listen(P, '127.0.0.1', () => console.log('посредник', P, '→', T));
