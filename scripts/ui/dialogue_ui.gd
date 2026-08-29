class_name DialogueUI
extends CanvasLayer

## Bottom-sheet dialogue runner. Reads DIALOGUES from StoryData, walks the
## steps (lines and choice branches), applies effects through QuestManager
## at the end, and UI-locks the player while open.
##
## Input: click / E / Space / Enter advances a line; number keys 1..9 (or
## mouse) pick options. The panel is deliberately slim: names in gold, text
## on dark parchment-ink, no portraits anywhere in the project.

signal dialogue_finished(id: String)

var player: Player = null
var quest_manager: QuestManager = null

var _panel: PanelContainer
var _speaker: Label
var _body: Label
var _choices_box: VBoxContainer
var _hint: Label
var _dialogue_id: String = ""
var _npc_name: String = ""
var _steps: Array = []
var _root_effects: Array = []
var _index: int = 0
var _awaiting_choice: bool = false
var _open: bool = false


func _ready() -> void:
	layer = 12
	visible = false
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := UIStyle.framed_panel()
	sb.content_margin_left = 26.0
	sb.content_margin_right = 26.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -460.0
	_panel.offset_right = 460.0
	_panel.offset_top = -236.0
	_panel.offset_bottom = -26.0
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)

	_speaker = UIStyle.title_label("", 15)
	v.add_child(_speaker)

	_body = UIStyle.label("", 16)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(0, 96)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	v.add_child(_choices_box)

	_hint = UIStyle.label("Пробел · E · клик — далее", 12, UIStyle.PARCHMENT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_hint)


func open(dialogue_id: String) -> void:
	var data: Dictionary = StoryData.DIALOGUES.get(dialogue_id, {})
	if data.is_empty():
		return
	_dialogue_id = dialogue_id
	_npc_name = str(data.get("npc", ""))
	_steps = data.get("steps", [])
	_root_effects = data.get("effects", [])
	_index = 0
	_open = true
	visible = true
	if player != null:
		player.set_ui_lock(true)
	_show_step()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_awaiting_choice = false
	if player != null:
		player.set_ui_lock(false)
	dialogue_finished.emit(_dialogue_id)


func is_open() -> bool:
	return _open


func _show_step() -> void:
	_clear_choices()
	_awaiting_choice = false
	if _index >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_index]
	if str(step.get("type", "line")) == "choice":
		_speaker.text = _npc_name
		_body.text = str(step.get("prompt", ""))
		_hint.text = "Выбери ответ"
		_awaiting_choice = true
		var options: Array = step.get("options", [])
		var num := 1
		for opt in options:
			var o: Dictionary = opt
			var btn := UIStyle.button("%d.  %s" % [num, str(o.get("text", ""))], 14)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var idx := num - 1
			btn.pressed.connect(_choose.bind(idx))
			_choices_box.add_child(btn)
			num += 1
	else:
		var speaker := str(step.get("speaker", _npc_name))
		_speaker.text = speaker
		_body.text = str(step.get("text", ""))
		_hint.text = "Пробел · E · клик — далее"


func _choose(idx: int) -> void:
	if not _awaiting_choice or _index >= _steps.size():
		return
	var step: Dictionary = _steps[_index]
	var options: Array = step.get("options", [])
	if idx < 0 or idx >= options.size():
		return
	var o: Dictionary = options[idx]
	_awaiting_choice = false
	if quest_manager != null and player != null:
		quest_manager.run_effects(o.get("effects", []), player)
	if o.has("goto"):
		_index = int(o["goto"])
	else:
		_index = _steps.size()  # no target - run the epilogue
	_show_step()


func _advance() -> void:
	_index += 1
	_show_step()


func _finish() -> void:
	if quest_manager != null and player != null:
		quest_manager.run_effects(_root_effects, player)
	close()


## Test hook: apply the epilogue effects and close without playing
## the timeline. Headless smoke test uses this.
func finish_instant() -> void:
	if not _open:
		return
	if quest_manager != null and player != null:
		quest_manager.run_effects(_root_effects, player)
	close()


func _clear_choices() -> void:
	for c in _choices_box.get_children():
		(c as Node).queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	# Number keys choose options directly.
	if _awaiting_choice and event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			var num := -1
			if key.keycode >= KEY_1 and key.keycode <= KEY_9:
				num = key.keycode - KEY_1
			elif key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_9:
				num = key.keycode - KEY_KP_1
			if num >= 0:
				_choose(num)
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") \
			or event.is_action_pressed("attack"):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
		if not _awaiting_choice:
			_advance()
			get_viewport().set_input_as_handled()
