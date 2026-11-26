/**
 * 暴龙躲避 · 网页轻量版
 * 只依赖 Canvas 2D，没有引擎、没有 wasm。首屏只加载 4 张图和几十 KB 代码。
 * 规则/数值全部来自 ./core.js（和 Godot 版保持一致）。
 */
import {
  CONFIG, spawnEnemy, stepEnemy, isCulled, hits,
  updatePlayer, spawnInterval, worldSize, createPlayer,
} from './core.js';

const $ = (id) => document.getElementById(id);
const stage = $('stage');
const canvas = $('game');
const ctx = canvas.getContext('2d', { alpha: false });

// ---------------------------------------------------------------------------
// 资源
// ---------------------------------------------------------------------------
const IMG = {};
const ASSET_LIST = [
  ['bg', 'assets/bg.webp'],
  ['dragon', 'assets/dragon.png'],
  ['poop1', 'assets/poop1.png'],
  ['poop2', 'assets/poop2.png'],
  ['poop3', 'assets/poop3.png'],
];

const STORE = {
  best: 'dodge.best',
  bestTime: 'dodge.bestTime',
  music: 'dodge.music',
};

function readInt(key, fallback = 0) {
  try {
    const v = parseInt(localStorage.getItem(key), 10);
    return Number.isFinite(v) ? v : fallback;
  } catch (e) {
    return fallback;
  }
}

function readBool(key, fallback = true) {
  try {
    const v = localStorage.getItem(key);
    return v === null ? fallback : v === '1';
  } catch (e) {
    return fallback;
  }
}

function write(key, value) {
  try {
    localStorage.setItem(key, String(value));
  } catch (e) {
    /* 隐私模式忽略 */
  }
}

// ---------------------------------------------------------------------------
// 状态
// ---------------------------------------------------------------------------
const state = {
  mode: 'loading',            // loading | home | playing | paused | over
  elapsed: 0,
  score: 0,
  scoreFloat: 0,
  best: readInt(STORE.best),
  bestTime: Number(localStorage.getItem(STORE.bestTime) || 0) || 0,
  enemies: [],
  spawnTimer: 0,
  shake: 0,
  deathT: 0,
  musicOn: readBool(STORE.music, true),
  lastTs: 0,
  shownScore: -1,
  record: false,
};

let bounds = { w: CONFIG.worldW, h: CONFIG.minWorldH };
let player = createPlayer(bounds);
const view = { scale: 1, dpr: 1 };

const drag = { active: false, id: null, ox: 0, oy: 0, x: 0, y: 0, dx: 0, dy: 0 };
const keys = new Set();

// ---------------------------------------------------------------------------
// 音频（懒加载：不阻塞进游戏）
// ---------------------------------------------------------------------------
const bgm = new Audio();
bgm.loop = true;
bgm.preload = 'none';
bgm.volume = 0.5;

function startMusic() {
  if (!state.musicOn) return;
  if (!bgm.src) bgm.src = 'assets/bgm.ogg';
  if (!bgm.paused) return;
  bgm.play().catch(() => {
    /* 被自动播放策略拦下：等下一次用户手势再试 */
  });
}

function toggleMusic() {
  state.musicOn = !state.musicOn;
  write(STORE.music, state.musicOn ? 1 : 0);
  bgm.muted = !state.musicOn;
  if (state.musicOn) startMusic();
  updateMusicLabels();
}

function updateMusicLabels() {
  const text = state.musicOn ? '音乐 开' : '音乐 关';
  ['musicHome', 'musicPause'].forEach((id) => {
    const node = $(id);
    if (node) node.textContent = text;
  });
}

// ---------------------------------------------------------------------------
// 画布尺寸 / 视口
// ---------------------------------------------------------------------------
function resize() {
  const rect = stage.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.max(1, Math.round(rect.width * dpr));
  canvas.height = Math.max(1, Math.round(rect.height * dpr));
  canvas.style.width = rect.width + 'px';
  canvas.style.height = rect.height + 'px';

  const size = worldSize(rect.width, rect.height);
  view.scale = size.scale;
  view.dpr = dpr;
  bounds = { w: size.w, h: size.h };

  if (state.mode === 'home' || state.mode === 'over') {
    player.x = bounds.w * 0.5;
    player.y = bounds.h * 0.52;
  }
  clampToBounds();
}

function clampToBounds() {
  player.x = Math.min(Math.max(player.x, player.r), bounds.w - player.r);
  player.y = Math.min(Math.max(player.y, player.r), bounds.h - player.r);
}

// ---------------------------------------------------------------------------
// 输入：拖拽（手机）+ 键盘（桌面）
// ---------------------------------------------------------------------------
const JOY_RADIUS = 62;   // CSS px，只是视觉半径

function updateDragVisual() {
  const stick = $('stick');
  if (!drag.active) {
    stick.classList.remove('on');
    return;
  }
  stick.classList.add('on');
  stick.style.transform = `translate(${drag.ox}px, ${drag.oy}px)`;
  $('knob').style.transform = `translate(${drag.kx - drag.ox}px, ${drag.ky - drag.oy}px)`;
}

canvas.addEventListener('pointerdown', (ev) => {
  if (state.mode !== 'playing') return;
  startMusic();
  if (drag.active) return;
  const rect = stage.getBoundingClientRect();
  drag.active = true;
  drag.id = ev.pointerId;
  drag.ox = drag.x = drag.kx = ev.clientX - rect.left;
  drag.oy = drag.y = drag.ky = ev.clientY - rect.top;
  drag.dx = drag.dy = 0;
  canvas.setPointerCapture(ev.pointerId);
  updateDragVisual();
});

canvas.addEventListener('pointermove', (ev) => {
  if (!drag.active || ev.pointerId !== drag.id) return;
  const rect = stage.getBoundingClientRect();
  drag.x = ev.clientX - rect.left;
  drag.y = ev.clientY - rect.top;
  let dx = drag.x - drag.ox;
  let dy = drag.y - drag.oy;
  const len = Math.hypot(dx, dy);

  // 拖出底盘：摇杆跟着走，保证方向不会突然中断
  if (len > JOY_RADIUS) {
    drag.ox = drag.x - (dx / len) * JOY_RADIUS;
    drag.oy = drag.y - (dy / len) * JOY_RADIUS;
    drag.kx = drag.x;
    drag.ky = drag.y;
    dx = drag.kx - drag.ox;
    dy = drag.ky - drag.oy;
  } else {
    drag.kx = drag.x;
    drag.ky = drag.y;
  }

  const strength = Math.min(1, Math.hypot(dx, dy) / JOY_RADIUS);
  if (strength < 0.08) {
    drag.dx = drag.dy = 0;
  } else {
    drag.dx = (dx / (Math.hypot(dx, dy) || 1)) * strength;
    drag.dy = (dy / (Math.hypot(dx, dy) || 1)) * strength;
  }
  updateDragVisual();
});

function endDrag(ev) {
  if (!drag.active || (ev && ev.pointerId !== drag.id)) return;
  drag.active = false;
  drag.id = null;
  drag.dx = drag.dy = 0;
  updateDragVisual();
}

canvas.addEventListener('pointerup', endDrag);
canvas.addEventListener('pointercancel', endDrag);

window.addEventListener('keydown', (ev) => {
  if (ev.repeat) return;
  const k = ev.key.toLowerCase();
  if (['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright'].includes(k)) {
    keys.add(k);
    ev.preventDefault();
    if (state.mode === 'playing') startMusic();
  }
});

window.addEventListener('keyup', (ev) => keys.delete(ev.key.toLowerCase()));

function inputVector() {
  if (drag.active && (drag.dx || drag.dy)) return { x: drag.dx, y: drag.dy };
  let x = 0;
  let y = 0;
  if (keys.has('a') || keys.has('arrowleft')) x -= 1;
  if (keys.has('d') || keys.has('arrowright')) x += 1;
  if (keys.has('w') || keys.has('arrowup')) y -= 1;
  if (keys.has('s') || keys.has('arrowdown')) y += 1;
  return { x, y };
}

// ---------------------------------------------------------------------------
// 状态切换
// ---------------------------------------------------------------------------
function setMode(mode) {
  state.mode = mode;
  document.body.dataset.mode = mode;
  $('loader').classList.toggle('hidden', mode !== 'loading');
  $('home').classList.toggle('hidden', mode !== 'home');
  $('pause').classList.toggle('hidden', mode !== 'paused');
  $('over').classList.toggle('hidden', mode !== 'over');
  $('hud').classList.toggle('hidden', mode !== 'playing' && mode !== 'paused');
  if (mode !== 'playing') endDrag();
  if (mode === 'home') {
    $('homeBest').textContent = `最高分   ${state.best}`;
    $('home').classList.remove('anim');
    requestAnimationFrame(() => $('home').classList.add('anim'));
  }
}

function resetBoard() {
  state.enemies.length = 0;
  state.elapsed = 0;
  state.score = 0;
  state.scoreFloat = 0;
  state.spawnTimer = 0.9;
  state.shake = 0;
  state.deathT = 0;
  state.record = false;
  player = createPlayer(bounds);
  player.y = bounds.h * 0.74;
  updateScoreText(0);
}

function goHome() {
  resetBoard();
  player.x = bounds.w * 0.5;
  player.y = bounds.h * 0.52;
  state.best = readInt(STORE.best);
  setMode('home');
  updateMusicLabels();
}

function startGame() {
  resetBoard();
  setMode('playing');
  $('best').textContent = `最高 ${state.best}`;
  updateMusicLabels();
  $('hud').classList.remove('hidden');
  startMusic();
}

function pauseGame() {
  if (state.mode !== 'playing') return;
  setMode('paused');
  bgm.pause();
  updateMusicLabels();
}

function resumeGame() {
  if (state.mode !== 'paused') return;
  setMode('playing');
  if (state.musicOn) bgm.play().catch(() => {});
}

function gameOver() {
  if (state.mode !== 'playing') return;
  state.deathT = 0.0001;
  state.shake = 1;
  const score = state.score;
  const survived = state.elapsed;
  const isRecord = score > state.best;
  if (isRecord) {
    state.best = score;
    write(STORE.best, score);
  }
  if (survived > state.bestTime) {
    state.bestTime = survived;
    write(STORE.bestTime, survived.toFixed(1));
  }
  state.record = isRecord;

  $('overScore').textContent = String(score);
  $('overTime').textContent = `存活时间    ${survived.toFixed(1)} 秒`;
  $('overBest').textContent = `最高分      ${state.best}`;
  $('overRecord').classList.toggle('hidden', !isRecord);
  setMode('over');
  bgm.pause();
}

// ---------------------------------------------------------------------------
// 主循环
// ---------------------------------------------------------------------------
function update(dt) {
  if (state.mode === 'playing') {
    state.elapsed += dt;

    state.scoreFloat += dt * CONFIG.scorePerSecond;
    if (state.scoreFloat >= 1) {
      const add = Math.floor(state.scoreFloat);
      state.scoreFloat -= add;
      state.score += add;
      updateScoreText(state.score);
    }

    state.spawnTimer -= dt;
    if (state.spawnTimer <= 0) {
      state.enemies.push(spawnEnemy(state.elapsed, bounds, player));
      state.spawnTimer = spawnInterval(state.elapsed);
    }

    for (const e of state.enemies) stepEnemy(e, dt);

    for (const e of state.enemies) {
      if (hits(e, player)) {
        gameOver();
        break;
      }
    }
    state.enemies = state.enemies.filter((e) => !isCulled(e, bounds));

    updatePlayer(player, inputVector(), dt, bounds);
  } else if (state.mode === 'over') {
    // 死亡后敌人继续飞走，看起来很自然
    for (const e of state.enemies) stepEnemy(e, dt);
    state.enemies = state.enemies.filter((e) => !isCulled(e, bounds));
    if (state.deathT > 0) state.deathT += dt;
  }

  if (state.shake > 0) state.shake = Math.max(0, state.shake - dt * 3);
}

function updateScoreText(v) {
  if (v === state.shownScore) return;
  state.shownScore = v;
  $('score').textContent = String(v);
}

function draw() {
  const k = view.dpr * view.scale;
  ctx.setTransform(k, 0, 0, k, 0, 0);
  ctx.fillStyle = '#0b0f18';
  ctx.fillRect(0, 0, bounds.w, bounds.h);

  if (state.shake > 0) {
    const amp = 16 * state.shake;
    ctx.translate((Math.random() * 2 - 1) * amp, (Math.random() * 2 - 1) * amp);
  }

  drawBackground();
  for (const e of state.enemies) drawEnemy(e);
  drawPlayer();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
}

function drawBackground() {
  const img = IMG.bg;
  if (!img) return;
  const s = Math.max(bounds.w / img.width, bounds.h / img.height);
  const w = img.width * s;
  const h = img.height * s;
  ctx.drawImage(img, (bounds.w - w) / 2, (bounds.h - h) / 2, w, h);
}

function drawPlayer() {
  const img = IMG.dragon;
  if (!img) return;

  let alpha = 1;
  let scale = 1;
  if (state.mode === 'over' && state.deathT > 0) {
    const t = Math.min(1, state.deathT / 0.22);
    alpha = 1 - t;
    scale = 1 + 0.9 * t;
  }
  if (alpha <= 0.01) return;

  ctx.save();
  ctx.globalAlpha = alpha;

  // 影子
  if (state.mode !== 'over') {
    ctx.beginPath();
    ctx.ellipse(player.x, player.y + 34, 40, 13, 0, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.fill();
  }

  // 青色光圈：在花花绿绿的农场里能一眼找到自己
  ctx.beginPath();
  ctx.arc(player.x, player.y, 50 * scale, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(90,210,255,0.06)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(100,240,255,0.65)';
  ctx.lineWidth = 2.5;
  ctx.stroke();

  const dh = CONFIG.playerVisualH * scale;
  const dw = dh * (img.width / img.height);
  ctx.translate(player.x, player.y);
  if (player.faceLeft) ctx.scale(-1, 1);
  ctx.drawImage(img, -dw / 2, -dh / 2, dw, dh);
  ctx.restore();
}

function drawEnemy(e) {
  const img = IMG['poop' + (e.shape + 1)];
  const size = e.r * CONFIG.visualScale;

  // 红色提示环：褐色便便 + 褐色土路，不加提示很容易看漏
  const rr = e.r * 1.55 * (1 + Math.sin(e.life * 3.4 + e.phase) * 0.08);
  ctx.beginPath();
  ctx.arc(e.x, e.y, rr, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(255,89,89,0.10)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(255,89,89,0.55)';
  ctx.lineWidth = 3;
  ctx.stroke();

  if (!img) return;
  const dirx = e.mvx || e.dx;
  ctx.save();
  ctx.translate(e.x, e.y);
  ctx.rotate(dirx * 0.22);
  if (dirx < -0.05) ctx.scale(-1, 1);
  ctx.drawImage(img, -size / 2, -size / 2, size, size);
  ctx.restore();
}

function frame(ts) {
  requestAnimationFrame(frame);
  if (!state.lastTs) state.lastTs = ts;
  const dt = Math.min((ts - state.lastTs) / 1000, 0.05);
  state.lastTs = ts;
  if (state.mode === 'playing' || state.mode === 'over') update(dt);
  draw();
}

// ---------------------------------------------------------------------------
// 按钮 / 事件
// ---------------------------------------------------------------------------
document.querySelectorAll('[data-action]').forEach((btn) => {
  btn.addEventListener('click', (ev) => {
    ev.preventDefault();
    startMusic();
    switch (btn.dataset.action) {
      case 'start': startGame(); break;
      case 'pause': pauseGame(); break;
      case 'resume': resumeGame(); break;
      case 'restart': startGame(); break;
      case 'home': goHome(); break;
      case 'music': toggleMusic(); break;
      default: break;
    }
  });
});

document.addEventListener('visibilitychange', () => {
  if (document.hidden) pauseGame();
});

window.addEventListener('blur', pauseGame);
window.addEventListener('resize', () => { resize(); });
window.addEventListener('orientationchange', () => setTimeout(resize, 120));

document.addEventListener('gesturestart', (e) => e.preventDefault());
document.addEventListener('dblclick', (e) => e.preventDefault(), { passive: false });

// ---------------------------------------------------------------------------
// 启动
// ---------------------------------------------------------------------------
function loadAssets() {
  let done = 0;
  const total = ASSET_LIST.length;
  const bar = $('loaderBar');
  const hint = $('loaderHint');

  return Promise.all(ASSET_LIST.map(([key, src]) => new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      IMG[key] = img;
      done += 1;
      bar.style.width = Math.round((done / total) * 100) + '%';
      hint.textContent = `正在加载 ${done}/${total}`;
      resolve();
    };
    img.onerror = () => {
      done += 1;
      bar.style.width = Math.round((done / total) * 100) + '%';
      console.warn('[loader] 图片加载失败', src);
      resolve();
    };
    img.src = src;
  })));
}

async function boot() {
  resize();
  window.addEventListener('resize', resize);
  bgm.muted = !state.musicOn;
  updateMusicLabels();
  await loadAssets();
  player = createPlayer(bounds);
  goHome();
  requestAnimationFrame(frame);
}

// 调试/自动化测试用的只读钩子（不影响游戏本身）
window.__dodge = {
  state,
  get player() { return player; },
  get bounds() { return bounds; },
  startGame,
  pauseGame,
  resumeGame,
  gameOver,
  goHome,
};

boot();
