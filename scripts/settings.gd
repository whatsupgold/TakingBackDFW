extends Node
## Player settings, saved to user://settings.cfg. Registered as the "Settings" autoload.

signal changed

const PATH := "user://settings.cfg"

var pixel_scale := 3          # 2 = sharper, 4 = chunkier pixels
var fullscreen := false
var show_debug := false       # developer stats panel (F4 in game)
var pan_speed := 1.0          # camera pan multiplier
var edge_scroll := true       # pan when the mouse touches the screen edge
var sector := ""              # the map picked under New game: a sector id, "custom" (data/real_map.json) or "" (generated)


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	pixel_scale = clampi(cfg.get_value("video", "pixel_scale", pixel_scale), 2, 4)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	show_debug = cfg.get_value("game", "show_debug", show_debug)
	pan_speed = clampf(cfg.get_value("game", "pan_speed", pan_speed), 0.5, 2.0)
	edge_scroll = cfg.get_value("game", "edge_scroll", edge_scroll)
	sector = cfg.get_value("game", "sector", sector)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "pixel_scale", pixel_scale)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("game", "show_debug", show_debug)
	cfg.set_value("game", "pan_speed", pan_speed)
	cfg.set_value("game", "edge_scroll", edge_scroll)
	cfg.set_value("game", "sector", sector)
	cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	changed.emit()
