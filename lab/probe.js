const fs = require('fs'), zlib = require('zlib');
const maps = () => [...new Set(fs.readFileSync('/proc/self/maps','utf8').split('\n').filter(l=>/brotli/i.test(l)).map(l=>l.trim().split(/\s+/).pop()))];
console.log(`[node] ${process.execPath} ${process.version} process.versions.brotli=${process.versions.brotli}`);
console.log(`[node] zlib.brotliDecompressSync: ${zlib.brotliDecompressSync(fs.readFileSync(process.argv[2]))}`);
(async () => {
  if (typeof fetch === 'function') {
    try { const r = await fetch('http://127.0.0.1:8765/'); console.log(`[node] fetch() body=${await r.text()}`); }
    catch (e) { console.log(`[node] fetch() ERROR ${e.cause?.message || e.message}`); }
  } else console.log('[node] fetch: not available');
  console.log(`[node] libbrotli mapped in process: ${JSON.stringify(maps()) || 'NONE'}`);
})();
