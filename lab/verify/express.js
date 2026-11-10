// (a) Express5 / 素のhttp が Content-Encoding: br のリクエストボディを展開するか
const http = require('http'), fs = require('fs'), zlib = require('zlib');
const br = fs.readFileSync('/v/hello.br');
const post = (port, path) => new Promise(res => { const r = http.request({port, path, method:'POST', headers:{'Content-Type':'text/plain','Content-Encoding':'br','Content-Length':br.length}}, x => { let b=''; x.on('data',d=>b+=d); x.on('end',()=>res(x.statusCode+' '+b)); }); r.end(br); });
(async () => {
  const express = require('/app/node_modules/express');
  console.log('express', require('/app/node_modules/express/package.json').version, 'body-parser', require('/app/node_modules/body-parser/package.json').version);
  const app = express(); app.use(express.text()); app.post('/', (q, s) => s.send('handler saw: ' + JSON.stringify(q.body)));
  const s1 = app.listen(8771); console.log('[express5 + express.text()]', await post(8771, '/')); s1.close();
  const app2 = express(); app2.use(express.json()); app2.post('/', (q, s) => s.send('handler saw: ' + JSON.stringify(q.body)));
  const s2 = app2.listen(8772); console.log('[express5 + express.json(), text/plain body]', await post(8772, '/')); s2.close();
  const s3 = http.createServer((q, s) => { const c=[]; q.on('data',d=>c.push(d)); q.on('end',()=>s.end('handler saw raw bytes: ' + Buffer.concat(c).toString('hex'))); }).listen(8773);
  console.log('[bare http server]', await post(8773, '/')); s3.close();
})();
