'use strict';
/* Посредник для проверки приложения на GitHub (только аудит, в приложение не входит).
   Приложение в симуляторе ходит сюда (порт P), посредник — в копию магазина (порт T).
   Тесты управляют связью: GET /__ctl/<режим>?scope=orders|all&ms=…
     on — обычная связь; off — обрыв соединения; slow — задержка ms;
     drop-after — запрос доходит до магазина, а ответ теряется (один раз);
     502 — ответ «502 Bad Gateway» как от nginx, когда магазин недоступен (один раз).
   GET /__ctl/stats?phone=7… — сколько заказов магазин реально создал (по ответам на POST /api/orders). */
const http = require('http');
const [P, T] = process.argv.slice(2).map(Number);
let mode = 'on', scope = 'all', ms = 0;
const created = new Map();   // id заказа → телефон
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname.startsWith('/__ctl/')) {
    const m = u.pathname.slice(7);
    res.setHeader('Content-Type', 'application/json');
    if (m === 'stats') {
      const ph = u.searchParams.get('phone');
      const ids = [...created].filter(([, p]) => !ph || p === ph).map(([id]) => id);
      return res.end(JSON.stringify({ orders: ids.length, ids }));
    }
    mode = m; scope = u.searchParams.get('scope') || 'orders'; ms = Number(u.searchParams.get('ms') || 0);
    console.log(new Date().toISOString(), 'режим', mode, scope, ms);
    return res.end('{"ok":true}');
  }
  const isOrder = req.method === 'POST' && u.pathname === '/api/orders';
  const hit = scope === 'all' || isOrder;
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    if (hit && mode === 'off') { req.socket.destroy(); return; }
    if (hit && mode === '502') { mode = 'on'; res.writeHead(502, { 'Content-Type': 'text/html' }); res.end('<html><body><center><h1>502 Bad Gateway</h1></center><hr><center>nginx</center></body></html>'); return; }
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
          if (hit && mode === 'drop-after') { mode = 'on'; req.socket.destroy(); return; }
          res.writeHead(pr.statusCode, pr.headers); res.end(buf);
        });
      });
      r2.on('error', () => { res.writeHead(502); res.end(); });
      r2.end(body);
    };
    if (hit && mode === 'slow') setTimeout(go, ms); else go();
  });
}).listen(P, '127.0.0.1', () => console.log('посредник', P, '→', T));
