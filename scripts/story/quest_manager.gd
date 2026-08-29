class_name QuestManager
extends Node

## Story state machine for "Пепельная Корона". One active quest at a time,
## linear stages inside it, plus a completed list for the journal.
##
## Landmarks register marker positions here (set_marker) and the HUD/compass
## read the current stage's marker. Kill objectives are fed by main.gd, which
## forwards Enemy.died(tag) into notify_kill().
##
## run_effects() is the single interpreter for story effects - used by the
## dialogue UI, the echo points and (in tests) directly.

signal quest_started(id: String, title: String)
signal stage_changed(id: String, stage: int, objective: String, marker: String)
signal quest_completed(id: String, title: String)
signal counter_changed(id: String, current: int, need: int)
signal symbol_revealed
signal chapter_finished(chapter: int)

var active_id: String = ""
var active_stage: int = 0
var completed: Array[String] = []
var markers: Dictionary = {}
var _counters: Dictionary = {}
var _chapters_done: Array[int] = []


func set_marker(key: String, pos: Vector3) -> void:
	markers[key] = pos


func get_marker(key: String) -> Vector3:
	return markers.get(key, Vector3.INF)


func is_active(id: String) -> bool:
	return active_id == id


func start_quest(id: String) -> void:
	if id == active_id or id in completed or not StoryData.QUESTS.has(id):
		return
	active_id = id
	active_stage = 0
	_counters.clear()
	var data: Dictionary = StoryData.QUESTS[id]
	print("[Quest] started '%s' - %s" % [id, data["title"]])
	quest_started.emit(id, data["title"])
	_emit_stage()


## Moves the active quest one stage forward. With expected_stage >= 0 the
## call only applies when the quest really sits on that stage - this is how
## echoes/triggers guard against firing out of order.
func advance(id: String, expected_stage: int = -1) -> void:
	if id != active_id:
		return
	if expected_stage >= 0 and active_stage != expected_stage:
		return
	active_stage += 1
	var stages: Array = StoryData.stages(id)
	if active_stage >= stages.size():
		var title: String = StoryData.quest(id).get("title", id)
		completed.append(id)
		active_id = ""
		active_stage = 0
		print("[Quest] completed '%s'" % id)
		quest_completed.emit(id, title)
	else:
		_emit_stage()


func notify_kill(tag: String) -> void:
	if active_id == "" or not StoryData.stages(active_id)[active_stage].has("counter"):
		return
	var counter: Dictionary = StoryData.stages(active_id)[active_stage]["counter"]
	if counter["tag"] != tag:
		return
	var need := int(counter["need"])
	var cur := int(_counters.get(tag, 0)) + 1
	_counters[tag] = cur
	print("[Quest] kill '%s' %d/%d" % [tag, cur, need])
	counter_changed.emit(active_id, cur, need)
	if cur >= need:
		advance(active_id)


func counter_progress() -> String:
	if active_id == "":
		return ""
	var stage: Dictionary = StoryData.stages(active_id)[active_stage]
	if not stage.has("counter"):
		return ""
	var counter: Dictionary = stage["counter"]
	var cur := int(_counters.get(counter["tag"], 0))
	return "(%d/%d)" % [cur, int(counter["need"])]


func current_objective() -> String:
	if active_id == "":
		return ""
	var stage: Dictionary = StoryData.stages(active_id)[active_stage]
	return str(stage.get("objective", ""))


func current_marker_key() -> String:
	if active_id == "":
		return ""
	var stage: Dictionary = StoryData.stages(active_id)[active_stage]
	return str(stage.get("marker", ""))


func stage_journal(id: String, stage: int) -> String:
	var stages: Array = StoryData.stages(id)
	if stage < 0 or stage >= stages.size():
		return ""
	return str(stages[stage].get("journal", ""))


## The one effect interpreter for the whole story layer.
func run_effects(effects: Array, player: Node) -> void:
	for e in effects:
		var effect: Dictionary = e
		if effect.has("advance_quest"):
			advance(str(effect["advance_quest"]))
		elif effect.has("start_quest"):
			start_quest(str(effect["start_quest"]))
		elif effect.has("complete_quest"):
			# Force-complete regardless of the current stage (dialogue-driven).
			var id: String = str(effect["complete_quest"])
			if id == active_id:
				var stages: Array = StoryData.stages(id)
				active_stage = stages.size()
				advance(id)
		elif effect.has("give_item"):
			if player != null and player.has_method("add_item"):
				player.add_item(str(effect["give_item"]))
		elif effect.has("show_symbol"):
			symbol_revealed.emit()
		elif effect.has("chapter_end"):
			var chapter := int(effect["chapter_end"])
			if chapter not in _chapters_done:
				_chapters_done.append(chapter)
				chapter_finished.emit(chapter)


func _emit_stage() -> void:
	var stage: Dictionary = StoryData.stages(active_id)[active_stage]
	stage_changed.emit(active_id, active_stage, str(stage.get("objective", "")),
			str(stage.get("marker", "")))
