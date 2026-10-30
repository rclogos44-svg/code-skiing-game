extends Node
## One-shot sound effects (procedurally generated WAVs in res://assets/audio).

const DIR := "res://assets/audio/"
var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)


func get_stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[name] = s
	return s


func play(name: String, volume_db := 0.0, pitch := 1.0, bus := "SFX") -> void:
	var s := get_stream(name)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus
	p.play()


func ui(name := "ui_click") -> void:
	play(name, -4.0, randf_range(0.97, 1.03), "UI")
