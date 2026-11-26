/**
 * 游戏核心规则（纯逻辑，不碰 DOM / Canvas）——可以直接在 Node 里跑测试。
 * 所有数值都沿用 Godot 版的调参结果，保证两个版本手感一致。
 */

export const CONFIG = {
  worldW: 720,          // 设计宽度；高度随屏幕比例扩展
  minWorldH: 1280,

  rampTime: 70,         // 难度登顶所需秒数
  scorePerSecond: 12,

  spawnIntervalEasy: 0.95,
  spawnIntervalHard: 0.22,
  speedEasy: 170,
  speedHard: 360,

  radiusMin: 20,
  radiusMax: 34,
  spawnMargin: 120,     // 出生点在屏幕外多远
  cullMargin: 260,      // 出屏多远回收

  playerRadius: 34,
  playerSpeed: 430,
  playerAccel: 6000,
  playerVisualH: 118,

  visualScale: 3,       // 敌人视觉尺寸 = 基准半径 × 3（看起来比判定大）
  hitScale: 0.9,        // 判定半径 = 基准半径 × 0.9
  wobbleChance: 0.35,
};

export const lerp = (a, b, t) => a + (b - a) * t;
export const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
export const ramp = (elapsed) => clamp(elapsed / CONFIG.rampTime, 0, 1);

function moveToward(cur, target, delta) {
  if (cur < target) return Math.min(cur + delta, target);
  return Math.max(cur - delta, target);
}

/** 刷怪间隔（秒） */
export function spawnInterval(elapsed, rnd = Math.random) {
  return lerp(CONFIG.spawnIntervalEasy, CONFIG.spawnIntervalHard, ramp(elapsed)) * (0.85 + rnd() * 0.35);
}

/** 敌人速度（px/s） */
export function enemySpeed(elapsed, rnd = Math.random) {
  return lerp(CONFIG.speedEasy, CONFIG.speedHard, ramp(elapsed)) * (0.85 + rnd() * 0.3);
}

/**
 * 生成一个敌人。从屏幕外四边随机出生，朝玩家附近（带 22% 屏幕尺寸的随机偏移）飞。
 */
export function spawnEnemy(elapsed, bounds, player, rnd = Math.random) {
  const r = lerp(CONFIG.radiusMin, CONFIG.radiusMax, rnd());
  const m = CONFIG.spawnMargin;
  let x;
  let y;
  switch (Math.floor(rnd() * 4)) {
    case 0: x = rnd() * bounds.w; y = -m; break;                    // 上
    case 1: x = bounds.w + m; y = rnd() * bounds.h; break;          // 右
    case 2: x = rnd() * bounds.w; y = bounds.h + m; break;          // 下
    default: x = -m; y = rnd() * bounds.h; break;                   // 左
  }

  const tx = player.x + (rnd() * 2 - 1) * bounds.w * 0.22;
  const ty = player.y + (rnd() * 2 - 1) * bounds.h * 0.22;
  const len = Math.hypot(tx - x, ty - y) || 1;

  return {
    x, y,
    dx: (tx - x) / len,
    dy: (ty - y) / len,
    mvx: 0, mvy: 0,
    speed: enemySpeed(elapsed, rnd),
    r,
    wobble: rnd() < CONFIG.wobbleChance ? 0.15 + rnd() * 0.35 : 0,
    phase: rnd() * Math.PI * 2,
    life: 0,
    shape: Math.floor(rnd() * 3),
  };
}

/** 推进一个敌人（直线 + 可选正弦摆动） */
export function stepEnemy(e, dt) {
  e.life += dt;
  let mx = e.dx;
  let my = e.dy;
  if (e.wobble > 0) {
    const s = Math.sin(e.life * 2.4 + e.phase) * e.wobble;
    mx = e.dx - e.dy * s;
    my = e.dy + e.dx * s;
    const l = Math.hypot(mx, my) || 1;
    mx /= l;
    my /= l;
  }
  e.mvx = mx;
  e.mvy = my;
  e.x += mx * e.speed * dt;
  e.y += my * e.speed * dt;
}

export function isCulled(e, bounds) {
  const m = CONFIG.cullMargin;
  return e.x < -m || e.x > bounds.w + m || e.y < -m || e.y > bounds.h + m;
}

/** 圆形判定：敌人判定半径 vs 玩家判定半径 */
export function hits(e, player) {
  const rr = e.r * CONFIG.hitScale + player.r;
  const dx = e.x - player.x;
  const dy = e.y - player.y;
  return dx * dx + dy * dy < rr * rr;
}

export function clampPlayer(p, bounds) {
  p.x = clamp(p.x, p.r, bounds.w - p.r);
  p.y = clamp(p.y, p.r, bounds.h - p.r);
}

/** 玩家移动：输入向量（长度 0~1）→ 加速到目标速度，再叠加位移 */
export function updatePlayer(p, input, dt, bounds) {
  let ix = input.x;
  let iy = input.y;
  const len = Math.hypot(ix, iy);
  if (len > 1) {
    ix /= len;
    iy /= len;
  }
  p.vx = moveToward(p.vx, ix * CONFIG.playerSpeed, CONFIG.playerAccel * dt);
  p.vy = moveToward(p.vy, iy * CONFIG.playerSpeed, CONFIG.playerAccel * dt);
  p.x += p.vx * dt;
  p.y += p.vy * dt;
  clampPlayer(p, bounds);
  if (Math.abs(p.vx) > 30) p.faceLeft = p.vx < 0;
}

/** 世界尺寸：宽度固定 720，高度按屏幕比例扩展（等价于 Godot 的 canvas_items + expand） */
export function worldSize(cssW, cssH) {
  const scale = Math.min(cssW / CONFIG.worldW, cssH / CONFIG.minWorldH);
  return {
    scale,
    w: cssW / scale,
    h: cssH / scale,
  };
}

export function createPlayer(bounds) {
  return {
    x: bounds.w * 0.5,
    y: bounds.h * 0.74,
    vx: 0,
    vy: 0,
    r: CONFIG.playerRadius,
    faceLeft: false,
  };
}
