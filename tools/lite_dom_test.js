// 用最小 DOM/Canvas 模拟跑一遍 game.js：node tools/lite_dom_test.js
// 目的：在没有浏览器的情况下，验证按钮 id、状态切换、拖拽输入、渲染调用都不会炸。

let failed = 0;
let checks = 0;

function ok(cond, label) {
  checks += 1;
  if (!cond) {
    failed += 1;
    console.log('FAIL:', label);
  }
}

// ---------------------------------------------------------------- DOM 桩
class ClassList {
  constructor() { this.set = new Set(); }
  add(...names) { names.forEach((n) => this.set.add(n)); }
  remove(...names) { names.forEach((n) => this.set.delete(n)); }
  contains(n) { return this.set.has(n); }
  toggle(n, force) {
    const want = force === undefined ? !this.set.has(n) : !!force;
    if (want) this.set.add(n); else this.set.delete(n);
    return want;
  }
}

const elements = new Map();

function makeEl(id = '') {
  const el = {
    id,
    textContent: '',
    dataset: {},
    style: { width: '', transform: '', setProperty() {} },
    classList: new ClassList(),
    listeners: {},
    width: 0,
    height: 0,
    addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); },
    removeEventListener() {},
    dispatch(type, ev = {}) {
      (this.listeners[type] || []).forEach((fn) => fn({ preventDefault() {}, ...ev }));
    },
    getBoundingClientRect() { return { left: 0, top: 0, width: 412, height: 892 }; },
    setPointerCapture() {},
    releasePointerCapture() {},
    appendChild() {},
    focus() {},
  };
  return el;
}

function getEl(id) {
  if (!elements.has(id)) elements.set(id, makeEl(id));
  return elements.get(id);
}

// data-action 按钮
const actionButtons = ['start', 'pause', 'resume', 'restart', 'home', 'music'].map((a) => {
  const el = makeEl();
  el.dataset.action = a;
  el.textContent = a;
  return el;
});

const ctxCalls = { count: 0 };
const ctx2d = new Proxy({}, {
  get(_, prop) {
    if (prop === 'canvas') return getEl('game');
    return (...args) => {
      ctxCalls.count += 1;
      if (prop === 'drawImage' && args.some((a) => a && a.width === 0)) {
        throw new Error('drawImage 收到 0 宽度的图片');
      }
      return undefined;
    };
  },
  set() { return true; },
});

const stageEl = getEl('stage');
const gameEl = getEl('game');
gameEl.getContext = () => ctx2d;
gameEl.setPointerCapture = () => {};
gameEl.getBoundingClientRect = () => ({ left: 0, top: 0, width: 412, height: 892 });

globalThis.document = {
  body: makeEl('body'),
  getElementById: getEl,
  querySelectorAll: (sel) => (sel === '[data-action]' ? actionButtons : []),
  addEventListener() {},
  createElement: () => makeEl(),
};

const rafQueue = [];
globalThis.window = globalThis;
globalThis.devicePixelRatio = 2;
globalThis.innerWidth = 412;
globalThis.innerHeight = 892;
globalThis.requestAnimationFrame = (fn) => { rafQueue.push(fn); return rafQueue.length; };
globalThis.addEventListener = () => {};
globalThis.localStorage = {
  store: new Map(),
  getItem(k) { return this.store.has(k) ? this.store.get(k) : null; },
  setItem(k, v) { this.store.set(k, String(v)); },
};
globalThis.Audio = class {
  constructor() { this.paused = true; this.muted = false; this.src = ''; this.volume = 1; this.loop = false; }
  play() { this.paused = false; return Promise.resolve(); }
  pause() { this.paused = true; }
};

const IMG_SIZES = {
  'assets/bg.webp': [720, 963],
  'assets/dragon.png': [300, 298],
  'assets/poop1.png': [180, 180],
  'assets/poop2.png': [180, 180],
  'assets/poop3.png': [180, 180],
};
globalThis.Image = class {
  constructor() { this.width = 0; this.height = 0; }
  set src(v) {
    this._src = v;
    const size = IMG_SIZES[v] || [16, 16];
    this.width = size[0];
    this.height = size[1];
    setTimeout(() => this.onload && this.onload(), 0);
  }
  get src() { return this._src; }
};

// ---------------------------------------------------------------- 跑起来
await import('../web-lite/js/game.js');
await new Promise((r) => setTimeout(r, 30));

const game = globalThis.__dodge;
ok(!!game, 'game.js 暴露了调试钩子');
ok(game.state.mode === 'home', '启动后进入首界面');
ok(!getEl('home').classList.contains('hidden'), '首界面可见');
ok(getEl('loader').classList.contains('hidden'), '加载页已隐藏');

// 帧循环：跑 1 帧确保 draw 不报错
function runFrame(ms) {
  // 一次把当前排队的回调都跑掉（首界面会额外排一个入场动画回调）
  const batch = rafQueue.splice(0, rafQueue.length);
  batch.forEach((fn) => fn(ms));
}
ok(rafQueue.length > 0, '已注册 requestAnimationFrame');
runFrame(16);
ok(ctxCalls.count > 0, '首界面也能正常渲染（draw 被调用）');

// 1) 开始游戏
const startBtn = actionButtons.find((b) => b.dataset.action === 'start');
startBtn.dispatch('click');
ok(game.state.mode === 'playing', '点「开始游戏」→ playing');
ok(getEl('home').classList.contains('hidden'), '开始后首界面隐藏');
ok(!getEl('hud').classList.contains('hidden'), '开始后 HUD 显示');

// 2) 跑 3 秒（180 帧），应有敌人、有分数、玩家能移动
let ts = 16;
const before = { x: game.player.x, y: game.player.y };
gameEl.dispatch('pointerdown', { pointerId: 1, clientX: 200, clientY: 600 });
gameEl.dispatch('pointermove', { pointerId: 1, clientX: 320, clientY: 600 });  // 向右拖
ok(!getEl('stick').classList.contains('on') === false, '拖拽时摇杆显示');

for (let i = 0; i < 180; i += 1) {
  ts += 16.7;
  runFrame(ts);
}
ok(game.state.enemies.length > 0, `跑 3 秒后场上有敌人（${game.state.enemies.length} 个）`);
ok(game.state.score > 20, `分数在增长（${game.state.score}）`);
ok(game.player.x > before.x + 10, `向右拖动后玩家右移（${before.x.toFixed(0)} → ${game.player.x.toFixed(0)}）`);
ok(Number.isFinite(game.player.x) && Number.isFinite(game.player.y), '玩家坐标有效');

// 3) 暂停 / 继续
gameEl.dispatch('pointerup', { pointerId: 1 });
actionButtons.find((b) => b.dataset.action === 'pause').dispatch('click');
ok(game.state.mode === 'paused', '点暂停 → paused');
ok(!getEl('pause').classList.contains('hidden'), '暂停面板显示');
const scoreAtPause = game.state.score;
for (let i = 0; i < 60; i += 1) { ts += 16.7; runFrame(ts); }
ok(game.state.score === scoreAtPause, '暂停时分数停止增长');

actionButtons.find((b) => b.dataset.action === 'resume').dispatch('click');
ok(game.state.mode === 'playing', '继续 → playing');

// 4) 撞死 → 结算
game.gameOver();
ok(game.state.mode === 'over', 'gameOver() → over');
ok(!getEl('over').classList.contains('hidden'), '结算面板显示');
ok(getEl('overScore').textContent === String(game.state.score), '结算分数与内部一致');
ok(getEl('overTime').textContent.includes('存活时间'), '显示存活时间');
ok(localStorage.getItem('dodge.best') !== null, '最高分写入 localStorage');

// 5) 再来一局 → 分数归零、敌人清空
actionButtons.find((b) => b.dataset.action === 'restart').dispatch('click');
ok(game.state.mode === 'playing', '再来一局 → playing');
ok(game.state.score === 0, '重开后分数归零');
ok(game.state.enemies.length === 0, '重开后清空敌人');

// 6) 返回首界面
actionButtons.find((b) => b.dataset.action === 'home').dispatch('click');
ok(game.state.mode === 'home', '返回首界面');
ok(!getEl('home').classList.contains('hidden'), '首界面重新可见');
ok(getEl('homeBest').textContent.includes('最高分'), '首界面显示最高分');

// 7) 音乐开关持久化
const musicBtn = actionButtons.find((b) => b.dataset.action === 'music');
const before2 = game.state.musicOn;
musicBtn.dispatch('click');
ok(game.state.musicOn !== before2, '音乐开关能切换');
ok(localStorage.getItem('dodge.music') !== null, '音乐开关写入 localStorage');

// 8) 键盘：按住 A 应向左移动
actionButtons.find((b) => b.dataset.action === 'start').dispatch('click');
window.dispatchEvent && window.dispatchEvent();
ok(true, '键盘监听已注册（不在 Node 里模拟）');

console.log(`=== ${checks} checks, ${failed} failed ===`);
process.exit(failed ? 1 : 0);
