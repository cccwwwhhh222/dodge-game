// 轻量版核心规则测试（不需要浏览器）：node tools/lite_core_test.js
import {
  CONFIG, ramp, spawnInterval, enemySpeed, spawnEnemy, stepEnemy,
  isCulled, hits, updatePlayer, worldSize, createPlayer, clampPlayer,
} from '../web-lite/js/core.js';

let failed = 0;
let checks = 0;

function ok(cond, label) {
  checks += 1;
  if (!cond) {
    failed += 1;
    console.log('FAIL:', label);
  }
}

function near(a, b, eps, label) {
  ok(Math.abs(a - b) <= eps, `${label} (got ${a}, want ~${b})`);
}

// 确定性随机
function seedRandom(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

// 1) 视口换算
{
  const phone = worldSize(360, 640);
  near(phone.scale, 0.5, 1e-9, '9:16 缩放 = 0.5');
  near(phone.w, 720, 1e-6, '9:16 世界宽 = 720');
  near(phone.h, 1280, 1e-6, '9:16 世界高 = 1280');

  const tall = worldSize(412, 892);
  near(tall.w, 720, 1e-6, '20:9 世界宽仍为 720（宽贴合）');
  ok(tall.h > 1280, '20:9 世界更高，多出纵向空间');
}

// 2) 难度曲线
{
  near(ramp(0), 0, 1e-9, '开局难度 0');
  near(ramp(35), 0.5, 1e-9, '35 秒难度 0.5');
  near(ramp(999), 1, 1e-9, '难度封顶 1');

  const rnd = () => 0.5;
  near(spawnInterval(0, rnd), CONFIG.spawnIntervalEasy * (0.85 + 0.5 * 0.35), 1e-9, '开局刷怪间隔');
  const late = spawnInterval(120, rnd);
  ok(late < spawnInterval(0, rnd), '越到后期刷怪越快');

  near(enemySpeed(0, () => 0), CONFIG.speedEasy * 0.85, 1e-9, '开局最慢速度');
  near(enemySpeed(120, () => 1), CONFIG.speedHard * 1.15, 1e-9, '后期最快速度');
}

// 3) 刷怪：出生点在屏幕外，方向朝玩家
{
  const bounds = { w: 720, h: 1280 };
  const player = { x: 360, y: 900, r: 34 };
  for (let s = 0; s < 200; s += 1) {
    const e = spawnEnemy(10, bounds, player, seedRandom(s + 1));
    const outside = e.x < 0 || e.x > bounds.w || e.y < 0 || e.y > bounds.h;
    ok(outside, `敌人 #${s} 出生在屏幕外`);
    ok(e.r >= CONFIG.radiusMin && e.r <= CONFIG.radiusMax, `敌人 #${s} 半径在范围内`);
    ok(e.speed > 0, `敌人 #${s} 有速度`);
    near(Math.hypot(e.dx, e.dy), 1, 1e-9, `敌人 #${s} 方向已归一化`);
    ok(e.shape >= 0 && e.shape < 3, `敌人 #${s} 有三种表情之一`);
    ok(e.wobble === 0 || (e.wobble >= 0.15 && e.wobble <= 0.5), `敌人 #${s} 摆动幅度合法`);
  }
}

// 4) 移动：速度大小恒定；摆动不改变速率
{
  const e = { x: 0, y: 0, dx: 1, dy: 0, speed: 100, wobble: 0.4, phase: 0, life: 0, r: 20 };
  let prev = { x: e.x, y: e.y };
  let maxErr = 0;
  for (let i = 0; i < 240; i += 1) {
    stepEnemy(e, 1 / 60);
    const d = Math.hypot(e.x - prev.x, e.y - prev.y) * 60;
    maxErr = Math.max(maxErr, Math.abs(d - 100));
    prev = { x: e.x, y: e.y };
    near(Math.hypot(e.mvx, e.mvy), 1, 1e-9, '移动方向单位化');
  }
  ok(maxErr < 1e-6, `摆动时速率恒定（误差 ${maxErr.toExponential(1)}）`);
}

// 5) 碰撞：判定半径 = 0.9r + 玩家半径
{
  const player = { x: 0, y: 0, r: CONFIG.playerRadius };
  const e = { x: 0, y: 0, r: 20 };
  ok(hits(e, player), '中心重合算撞');
  const edge = 20 * CONFIG.hitScale + CONFIG.playerRadius;
  ok(hits({ ...e, x: edge - 0.5 }, player), '刚好接触算撞');
  ok(!hits({ ...e, x: edge + 0.5 }, player), '差一点不算撞');
}

// 6) 玩家移动与边界
{
  const bounds = { w: 720, h: 1280 };
  const p = createPlayer(bounds);
  near(p.x, 360, 1e-9, '出生在水平中央');
  near(p.y, 1280 * 0.74, 1e-6, '出生在下方');

  for (let i = 0; i < 60; i += 1) updatePlayer(p, { x: 1, y: 0 }, 1 / 60, bounds);
  near(p.vx, CONFIG.playerSpeed, 1e-6, '按住右 1 秒后达到最高速');

  for (let i = 0; i < 600; i += 1) updatePlayer(p, { x: 1, y: 0 }, 1 / 60, bounds);
  ok(p.x <= bounds.w - p.r + 1e-9, '玩家不会跑出右边界');
  for (let i = 0; i < 600; i += 1) updatePlayer(p, { x: 0, y: -1 }, 1 / 60, bounds);
  ok(p.y >= p.r - 1e-9, '玩家不会跑出上边界');

  // 斜向不应比直向快
  const q = createPlayer(bounds);
  for (let i = 0; i < 60; i += 1) updatePlayer(q, { x: 1, y: 1 }, 1 / 60, bounds);
  near(Math.hypot(q.vx, q.vy), CONFIG.playerSpeed, 1e-6, '斜向速度 = 直向速度');
}

// 7) 整局模拟：玩家不动 → 一定被撞到；敌人不会无限堆积
{
  const bounds = { w: 720, h: 1280 };
  const player = createPlayer(bounds);
  const rnd = seedRandom(20261126);
  const enemies = [];
  let timer = 0.9;
  let elapsed = 0;
  let died = false;
  let maxAlive = 0;

  for (let i = 0; i < 60 * 90 && !died; i += 1) {
    const dt = 1 / 60;
    elapsed += dt;
    timer -= dt;
    if (timer <= 0) {
      enemies.push(spawnEnemy(elapsed, bounds, player, rnd));
      timer = spawnInterval(elapsed, rnd);
    }
    for (const e of enemies) stepEnemy(e, dt);
    for (const e of enemies) {
      if (hits(e, player)) { died = true; break; }
    }
    for (let j = enemies.length - 1; j >= 0; j -= 1) if (isCulled(enemies[j], bounds)) enemies.splice(j, 1);
    maxAlive = Math.max(maxAlive, enemies.length);
    for (const e of enemies) {
      ok(Number.isFinite(e.x) && Number.isFinite(e.y), '敌人坐标不能出现 NaN');
    }
  }

  ok(died, '站着不动最终会被撞到（判定有效）');
  ok(maxAlive <= 40, `同屏敌人数量受控（峰值 ${maxAlive}）`);
  console.log(`  .. 模拟：${elapsed.toFixed(1)} 秒后死亡，同屏峰值 ${maxAlive} 个`);
}

// 8) 计分：12 分/秒
{
  const perSecond = CONFIG.scorePerSecond;
  ok(perSecond === 12, '每秒 12 分');
}

console.log(`=== ${checks} checks, ${failed} failed ===`);
process.exit(failed ? 1 : 0);
