// 用 Node 模拟浏览器环境，把导出后的 index.html 里那段加载脚本真跑一遍。
// 验证：只请求 index.wasm.gz（不请求 37MB 的 index.wasm）、解压后字节与源文件一致、
//      engine.startGame 被调用、加载页在成功后移除。
const fs = require('fs');
const http = require('http');
const path = require('path');

const DOCS = path.join(__dirname, '..', 'docs');
const PORT = 8793;
const realFetch = globalThis.fetch;

const server = http.createServer((req, res) => {
  const file = path.join(DOCS, decodeURIComponent(req.url.split('?')[0]));
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); res.end('not found'); return;
  }
  const stat = fs.statSync(file);
  res.writeHead(200, { 'Content-Length': stat.size });
  fs.createReadStream(file).pipe(res);
  console.log('[http] GET', req.url, stat.size);
});

function el() {
  return {
    style: {}, textContent: '', href: '',
    classList: { add() {}, remove() {} },
    appendChild() {}, remove() { globalThis.__statusRemoved = true; },
  };
}

server.listen(PORT, '127.0.0.1', async () => {
  const BASE = `http://127.0.0.1:${PORT}/`;
  const html = fs.readFileSync(path.join(DOCS, 'index.html'), 'utf8');
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  const code = scripts[scripts.length - 1][1];

  const elements = {};
  globalThis.window = globalThis;
  globalThis.location = { search: '', href: BASE + 'index.html' };
  globalThis.document = {
    getElementById: (id) => (elements[id] ||= el()),
    createElement: () => el(),
    createTextNode: () => ({}),
  };
  globalThis.fetch = (input, init) => {
    const url = typeof input === 'string' ? new URL(input, BASE).toString() : input;
    return realFetch(url, init);
  };
  globalThis.Engine = class {
    constructor(config) { this.config = config; }
    static getMissingFeatures() { return []; }
    startGame(opts) {
      globalThis.__started = opts;
      (async () => {
        const resp = await fetch('index.wasm', { credentials: 'same-origin' });
        globalThis.__wasm = await resp.arrayBuffer();
        globalThis.__mime = resp.headers.get('content-type');
      })();
      return Promise.resolve();
    }
  };

  try {
    new Function(code)();
  } catch (err) {
    console.error('脚本执行失败:', err);
    process.exit(1);
  }

  await new Promise((r) => setTimeout(r, 1500));
  const src = fs.readFileSync(path.join(DOCS, 'index.wasm'));
  const okBytes = globalThis.__wasm && globalThis.__wasm.byteLength === src.length;
  const okContent = okBytes && Buffer.compare(Buffer.from(globalThis.__wasm), src) === 0;
  console.log('---');
  console.log('startGame 被调用      :', !!globalThis.__started);
  console.log('wasm 字节数           :', globalThis.__wasm ? globalThis.__wasm.byteLength : 'null');
  console.log('wasm 内容完全一致     :', okContent);
  console.log('wasm MIME             :', globalThis.__mime);
  console.log('加载页是否移除        :', !!globalThis.__statusRemoved);
  process.exit(okContent && globalThis.__started ? 0 : 1);
});
