extends Node2D
## ===========================================================================
## 关卡总控：状态机 + 刷怪 + 计分 + 暂停 + 震屏 + 结算
## 状态：HOME（首界面）→ PLAYING（游戏中）⇄ PAUSED（暂停）→ GAME_OVER（结算）
## ===========================================================================

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
## 三种表情的敌人贴图（由 tools/cut_enemies.py 从原图抠出来的透明 PNG）
const ENEMY_TEXTURES: Array[Texture2D] = [
	preload("res://assets/enemy_happy.png"),
	preload("res://assets/enemy_shocked.png"),
	preload("res://assets/enemy_angry.png"),
]

## 每秒得多少分
const SCORE_PER_SECOND: float = 12.0
## 难度从最简单爬到最难需要多少秒
const RAMP_TIME: float = 70.0
## 刷怪间隔：开局 → 最难
const SPAWN_INTERVAL_EASY: float = 0.95
const SPAWN_INTERVAL_HARD: float = 0.22
## 敌人速度：开局 → 最难
const SPEED_EASY: float = 170.0
const SPEED_HARD: float = 360.0
## 敌人出生点离屏幕外多远
const SPAWN_MARGIN: float = 120.0
## 背景音乐音量（dB）；关闭时用 -80 近似静音
const MUSIC_DB: float = -8.0
const MUSIC_DB_OFF: float = -80.0

enum State { HOME, PLAYING, PAUSED, GAME_OVER }

@onready var playfield: Node2D = $Playfield
@onready var player: DodgePlayer = $Playfield/Player
@onready var enemies: Node2D = $Playfield/Enemies
@onready var joystick: TouchJoystick = $TouchLayer/Joystick
@onready var hud: DodgeHUD = $HUD
@onready var home: HomeScreen = $Home
@onready var bgm: AudioStreamPlayer = $Bgm

var state: State = State.HOME
## 当前可见区域（720×1280 基准，aspect=expand 时会随屏幕比例变化）
var bounds: Rect2 = Rect2()
var elapsed: float = 0.0

var _spawn_timer: float = 0.0
var _score_pool: float = 0.0
var _shake: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()

	_apply_viewport()
	get_viewport().size_changed.connect(_apply_viewport)

	home.start_pressed.connect(_on_start_pressed)
	home.music_pressed.connect(_on_music_pressed)
	hud.pause_pressed.connect(_on_pause_pressed)
	hud.resume_pressed.connect(_on_resume_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	hud.home_pressed.connect(_on_home_pressed)
	hud.music_pressed.connect(_on_music_pressed)
	joystick.input_changed.connect(_on_joystick_input)

	_setup_music()
	_enter_home()


# ---------------------------------------------------------------------------
# 状态切换
# ---------------------------------------------------------------------------
func _enter_home() -> void:
	get_tree().paused = false
	state = State.HOME
	elapsed = 0.0
	_spawn_timer = 0.0
	_score_pool = 0.0
	_shake = 0.0
	_clear_enemies()
	player.reset_state()
	player.set_home_mode(true)
	player.position = _home_point()
	joystick.set_enabled(false)
	joystick.reset()
	Game.reset_score()
	hud.set_score(0)
	hud.set_best(Game.high_score)
	hud.hide_all()
	home.set_music_state(Game.music_on)
	home.show_screen(Game.high_score)
	bgm.stream_paused = false


func _start_playing() -> void:
	get_tree().paused = false
	state = State.PLAYING
	home.hide_screen()
	_clear_enemies()
	player.set_home_mode(false)
	player.reset_state()
	player.position = _play_point()
	_shake = 0.0
	elapsed = 0.0
	_spawn_timer = 0.9
	_score_pool = 0.0
	Game.reset_score()
	hud.set_score(0)
	hud.set_best(Game.high_score)
	hud.show_game_hud()
	joystick.set_enabled(true)
	bgm.stream_paused = false


func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	joystick.set_enabled(false)
	joystick.reset()
	hud.set_music_state(Game.music_on)
	hud.show_pause_menu()
	# 用引擎级暂停：敌人的物理、计分、刷怪全部停住，HUD 因为 process_mode=ALWAYS 还能点
	get_tree().paused = true
	bgm.stream_paused = true


func _resume() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	state = State.PLAYING
	hud.show_game_hud()
	joystick.set_enabled(true)
	bgm.stream_paused = false


func _on_start_pressed() -> void:
	if state != State.HOME:
		return
	_start_playing()


func _on_pause_pressed() -> void:
	_pause()


func _on_resume_pressed() -> void:
	_resume()


func _on_restart_pressed() -> void:
	_start_playing()


func _on_home_pressed() -> void:
	_enter_home()


func _on_music_pressed() -> void:
	Game.set_music(not Game.music_on)
	_apply_music_volume()
	home.set_music_state(Game.music_on)
	hud.set_music_state(Game.music_on)


# ---------------------------------------------------------------------------
# 背景音乐
# ---------------------------------------------------------------------------
func _setup_music() -> void:
	# 循环播放（不同 Godot 版本属性名有差异，用 set 更稳）
	if bgm.stream != null and "loop" in bgm.stream:
		bgm.stream.set("loop", true)
	_apply_music_volume()
	if not bgm.playing:
		bgm.play()
	home.set_music_state(Game.music_on)
	hud.set_music_state(Game.music_on)


func _apply_music_volume() -> void:
	bgm.volume_db = MUSIC_DB if Game.music_on else MUSIC_DB_OFF


# ---------------------------------------------------------------------------
# 每帧逻辑
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_update_shake(delta)

	if state != State.PLAYING:
		return

	elapsed += delta

	# 计分：攒够 1 分再加，避免每帧改 Label 触发重排
	_score_pool += delta * SCORE_PER_SECOND
	if _score_pool >= 1.0:
		var gained: int = int(_score_pool)
		_score_pool -= float(gained)
		Game.add_score(gained)
		hud.set_score(Game.score)

	# 刷怪节拍
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_enemy()
		_spawn_timer = _next_spawn_interval()


func _update_shake(delta: float) -> void:
	if _shake <= 0.0:
		if playfield.position != Vector2.ZERO:
			playfield.position = Vector2.ZERO
		return
	_shake = maxf(_shake - delta * 3.0, 0.0)
	var amp: float = 16.0 * _shake
	playfield.position = Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp))


# ---------------------------------------------------------------------------
# 刷怪
# ---------------------------------------------------------------------------
func _spawn_enemy() -> void:
	var t: float = clampf(elapsed / RAMP_TIME, 0.0, 1.0)

	var speed: float = lerpf(SPEED_EASY, SPEED_HARD, t) * _rng.randf_range(0.85, 1.15)
	var radius: float = _rng.randf_range(20.0, 34.0)
	var start: Vector2 = _edge_point(SPAWN_MARGIN)

	# 大致朝玩家所在区域飞，但带随机偏移：既压迫又不至于必死
	var target: Vector2 = player.position + Vector2(
		_rng.randf_range(-bounds.size.x * 0.22, bounds.size.x * 0.22),
		_rng.randf_range(-bounds.size.y * 0.22, bounds.size.y * 0.22)
	)
	var dir: Vector2 = (target - start).normalized()

	# 35% 概率变成蛇形走位，增加读图难度
	var wobble: float = 0.0
	if _rng.randf() < 0.35:
		wobble = _rng.randf_range(0.15, 0.5)

	var enemy: DodgeEnemy = ENEMY_SCENE.instantiate()
	enemies.add_child(enemy)
	var texture: Texture2D = ENEMY_TEXTURES[_rng.randi_range(0, ENEMY_TEXTURES.size() - 1)]
	enemy.setup(start, dir, speed, texture, radius, wobble)
	enemy.hit_player.connect(_on_player_hit)


func _next_spawn_interval() -> float:
	var t: float = clampf(elapsed / RAMP_TIME, 0.0, 1.0)
	return lerpf(SPAWN_INTERVAL_EASY, SPAWN_INTERVAL_HARD, t) * _rng.randf_range(0.85, 1.2)


## 在屏幕外一圈随机取一个出生点
func _edge_point(margin: float) -> Vector2:
	var point: Vector2 = Vector2.ZERO
	match _rng.randi_range(0, 3):
		0:  # 上
			point = Vector2(_rng.randf_range(bounds.position.x, bounds.end.x), bounds.position.y - margin)
		1:  # 右
			point = Vector2(bounds.end.x + margin, _rng.randf_range(bounds.position.y, bounds.end.y))
		2:  # 下
			point = Vector2(_rng.randf_range(bounds.position.x, bounds.end.x), bounds.end.y + margin)
		_:  # 左
			point = Vector2(bounds.position.x - margin, _rng.randf_range(bounds.position.y, bounds.end.y))
	return point


# ---------------------------------------------------------------------------
# 死亡 / 结算
# ---------------------------------------------------------------------------
func _on_player_hit() -> void:
	if state != State.PLAYING:
		return
	state = State.GAME_OVER
	joystick.set_enabled(false)
	joystick.reset()
	player.die()
	_shake = 1.0

	var is_record: bool = Game.end_game(elapsed)
	hud.set_best(Game.high_score)
	hud.show_game_over(Game.score, Game.high_score, is_record, elapsed)


# ---------------------------------------------------------------------------
# 系统事件：切后台自动暂停 / 安卓返回键
# ---------------------------------------------------------------------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED:
			_enter_home()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------
func _on_joystick_input(dir: Vector2) -> void:
	player.move_input = dir


func _apply_viewport() -> void:
	bounds = Rect2(Vector2.ZERO, get_viewport_rect().size)
	player.set_bounds(bounds)
	if state == State.HOME:
		player.position = _home_point()
	elif state != State.PLAYING:
		player.position = _play_point()


## 首界面里龙站在画面中间当「看板」
func _home_point() -> Vector2:
	return Vector2(bounds.size.x * 0.5, bounds.size.y * 0.52)


func _play_point() -> Vector2:
	return Vector2(bounds.size.x * 0.5, bounds.size.y * 0.74)


func _clear_enemies() -> void:
	for child in enemies.get_children():
		# 先脱离场景树再排队释放：否则重启那一帧旧敌人还能碰到玩家
		enemies.remove_child(child)
		child.queue_free()
