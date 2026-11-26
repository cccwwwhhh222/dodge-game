extends Node
## ===========================================================================
## 全局单例（Autoload 名字：Game）
## 只管数据：当前分数、最高分、存档读写。不碰任何画面，方便单独测试。
## ===========================================================================

const SAVE_PATH: String = "user://dodge_save.cfg"

var score: int = 0
var high_score: int = 0
var best_time: float = 0.0
## 背景音乐开关（持久化）
var music_on: bool = true


func _ready() -> void:
	_load_save()


func reset_score() -> void:
	score = 0


func add_score(amount: int) -> void:
	if amount > 0:
		score += amount


## 结算：刷新最高分/最长存活时间并落盘，返回是否破纪录
func end_game(survived: float) -> bool:
	var is_record: bool = score > high_score
	if is_record:
		high_score = score
	if survived > best_time:
		best_time = survived
	if is_record:
		_save()
	return is_record


func _load_save() -> void:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		high_score = 0
		best_time = 0.0
		music_on = true
		return
	high_score = int(cf.get_value("record", "high_score", 0))
	best_time = float(cf.get_value("record", "best_time", 0.0))
	music_on = bool(cf.get_value("settings", "music_on", true))


func _save() -> void:
	var cf: ConfigFile = ConfigFile.new()
	cf.set_value("record", "high_score", high_score)
	cf.set_value("record", "best_time", best_time)
	cf.set_value("settings", "music_on", music_on)
	cf.save(SAVE_PATH)
	# 网页端存档在 IndexedDB 里，浏览器强杀前可能还没落盘。
	# 需要更强的保障时，可以在关键节点打印 OS.is_userfs_persistent() 自检。


## 开关背景音乐（会立刻落盘，下次启动保持）
func set_music(on: bool) -> void:
	if music_on == on:
		return
	music_on = on
	_save()
