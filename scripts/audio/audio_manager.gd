class_name AudioManager
extends Node

## Central sound hub. Builds the SfxBank once, keeps the ambient loops alive
## (wind everywhere, crackle at every registered fire, the dark drone) and
## spawns throwaway players for one-shots - 3D positional when a world
## position is given, plain 2D otherwise.
##
## Lookup contract for gameplay scripts: anything can call
##   get_tree().get_first_node_in_group("audio")
## and duck-type play()/play_at(). Player and Enemy cache the lookup lazily
## because their _ready() runs before Main adds this node.

var _streams: Dictionary = {}


func _ready() -> void:
	add_to_group("audio")
	_streams = SfxBank.build_all()
	_start_ambient()
	print("[Audio] %d streams synthesized" % _streams.size())


# --- public API --------------------------------------------------------------

## UI / non-positional one-shot.
func play(sfx_name: String, volume_db: float = 0.0) -> void:
	var stream := _streams.get(sfx_name) as AudioStreamWAV
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## World-positioned one-shot.
func play_at(sfx_name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := _streams.get(sfx_name) as AudioStreamWAV
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 7.0
	p.max_distance = 60.0
	p.position = pos
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func has_stream(sfx_name: String) -> bool:
	return _streams.has(sfx_name)


func stream_count() -> int:
	return _streams.size()


## Registers a fire position; a looping crackle player is planted there.
func add_fire(pos: Vector3, quiet: bool = false) -> void:
	var stream := _streams.get("fire") as AudioStreamWAV
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = -8.0 if quiet else -4.0
	p.unit_size = 4.5
	p.max_distance = 26.0
	p.position = pos
	add_child(p)
	p.play()


# --- ambient -----------------------------------------------------------------

func _start_ambient() -> void:
	var wind := _streams.get("wind") as AudioStreamWAV
	if wind != null:
		var w := AudioStreamPlayer.new()
		w.stream = wind
		w.volume_db = -16.0
		add_child(w)
		w.play()
	var music := _streams.get("music") as AudioStreamWAV
	if music != null:
		var m := AudioStreamPlayer.new()
		m.stream = music
		m.volume_db = -17.0
		add_child(m)
		m.play()
