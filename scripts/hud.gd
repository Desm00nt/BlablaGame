class_name GameHUD
extends CanvasLayer

## "Ashen crown" UI, built in code like everything else in the project.
##
## Surfaces: HP/stamina bars, quest tracker, compass, hotbar + the hand
## symbol, interact prompt, subtitles, echo-vision letterbox, inventory
## window (items + journal tabs), note reader, toasts, damage flash, death
## overlay and a chapter card.
##
## Everything is event-driven; _process only fades overlays (flash, toast,
## chapter, letterbox) and pulses the symbol - a handful of alpha writes.

var _player: Player
var _qm: QuestManager
var _instances: int = 0
var _time: float = 0.0

# Bars.
var _hp_fill: ColorRect
var _hp_label: Label
var _st_fill: ColorRect
# Tracker.
var _tracker: PanelContainer
var _tracker_title: Label
var _tracker_obj: Label
# Compass.
var _compass: CompassBar
# Hotbar / symbol.
var _slot_panel: PanelContainer
var _hotbar_label: Label
var _slot_normal: StyleBoxFlat
var _slot_equipped: StyleBoxFlat
var _slot_icon: ItemIcon
var _symbol_slot: PanelContainer
var _symbol_icon: ItemIcon
var _symbol_on: bool = false
# Prompt / crosshair.
var _prompt: Label
# Subtitles.
var _sub_panel: PanelContainer
var _sub_speaker: Label
var _sub_text: Label
# Vision overlay.
var _vision_on: bool = false
var _lb_top: ColorRect
var _lb_bottom: ColorRect
var _vignette: ColorRect
# Inventory.
var _inventory_panel: CenterContainer
var _tab_items_btn: Button
var _tab_journal_btn: Button
var _items_scroll: ScrollContainer
var _items_box: VBoxContainer
var _journal_scroll: ScrollContainer
var _journal_box: VBoxContainer
var _eq_icon: ItemIcon
var _eq_name: Label
var _eq_stat: Label
var _detail_name: Label
var _detail_desc: Label
var _detail_stat: Label
var _btn_action: Button
var _btn_read: Button
var _selected_id: String = ""
var _inv_tab: int = 0
# Note reader.
var _note_root: Control
var _note_title: Label
var _note_text: Label
# Toasts.
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_a: float = 0.0
# Damage flash / death / perf.
var _flash_rect: ColorRect
var _flash_a: float = 0.0
var _death_overlay: Control
var _perf: Label
var _perf_t: float = 0.0
# Chapter card.
var _chapter_root: Control
var _chapter_title: Label
var _chapter_sub: Label
var _chapter_t: float = -1.0


func _ready() -> void:
	layer = 10
	_build_vision()
	_build_flash_and_death()
	_build_bars()
	_build_tracker()
	_build_compass()
	_build_hotbar()
	_build_prompt_and_cross()
	_build_subtitles()
	_build_toast()
	_build_perf()
	_build_chapter_card()
	_build_inventory()
	_build_note_reader()


## Must be called after the player is in the tree.
func setup(player: Player, instance_count: int) -> void:
	_player = player
	_instances = instance_count
	player.hp_changed.connect(_on_hp)
	player.stamina_changed.connect(_on_stamina)
	player.sword_state_changed.connect(_on_sword)
	player.prompt_changed.connect(_on_prompt)
	player.inventory_toggled.connect(_on_inventory)
	player.inventory_changed.connect(_on_inv_changed)
	player.journal_toggled.connect(_on_journal_key)
	player.hurt.connect(_on_hurt)
	player.died.connect(_on_died)
	player.respawned.connect(_on_respawned)
	_compass.player = player
	_on_hp(player.hp, player.max_hp)
	_on_stamina(player.stamina, player.max_stamina)
	_on_sword(player.has_sword, player.sword_equipped)
	_on_prompt("")
	_symbol_slot.visible = false


## Wires the story layer. main.gd calls this once both exist.
func connect_quests(qm: QuestManager) -> void:
	_qm = qm
	qm.quest_started.connect(_on_quest_started)
	qm.stage_changed.connect(_on_stage_changed)
	qm.quest_completed.connect(_on_quest_completed)
	qm.counter_changed.connect(_on_counter_changed)
	qm.symbol_revealed.connect(_on_symbol_revealed)
	qm.chapter_finished.connect(_on_chapter_finished)


func _process(delta: float) -> void:
	_time += delta
	if _flash_a > 0.0:
		_flash_a = maxf(_flash_a - delta * 1.5, 0.0)
		_flash_rect.color.a = _flash_a * 0.45
	_perf_t += delta
	if _perf_t >= 0.5:
		_perf_t = 0.0
		_perf.text = "fps %d · props %d" % [Engine.get_frames_per_second(), _instances]

	# Vision letterbox eases toward its target height.
	var target := 54.0 if _vision_on else 0.0
	var k := 1.0 - exp(-8.0 * delta)
	_lb_top.offset_top = lerpf(_lb_top.offset_top, 0.0, k)
	_lb_top.offset_bottom = lerpf(_lb_top.offset_bottom, target, k)
	_lb_bottom.offset_top = lerpf(_lb_bottom.offset_top, -target, k)
	var v_alpha := 0.16 if _vision_on else 0.0
	_vignette.color.a = lerpf(_vignette.color.a, v_alpha, k)

	if _toast_a > 0.0:
		_toast_a = maxf(_toast_a - delta * 0.8, 0.0)
		_toast_panel.modulate.a = clampf(_toast_a * 3.0, 0.0, 1.0)
		if _toast_a <= 0.0:
			_toast_panel.visible = false

	if _chapter_t >= 0.0:
		_chapter_t += delta
		if _chapter_t < 1.0:
			_chapter_root.modulate.a = _chapter_t
		elif _chapter_t > 4.5:
			_chapter_root.modulate.a = clampf(1.0 - (_chapter_t - 4.5) / 1.2, 0.0, 1.0)
			if _chapter_t > 5.8:
				_chapter_root.visible = false
				_chapter_t = -1.0

	if _symbol_on:
		_symbol_icon.modulate.a = 0.78 + 0.22 * sin(_time * 2.4)


# --- public story API --------------------------------------------------------

func show_subtitle(speaker: String, text: String) -> void:
	_sub_speaker.text = speaker
	_sub_speaker.visible = speaker != ""
	_sub_text.text = text
	_sub_panel.visible = true


func hide_subtitle() -> void:
	_sub_panel.visible = false


func set_vision(on: bool) -> void:
	_vision_on = on


func set_symbol(on: bool, flare: bool = false) -> void:
	_symbol_on = on
	_symbol_slot.visible = on
	if on and flare:
		_symbol_icon.modulate = Color(1.6, 1.5, 1.2, 1.0)
	elif on:
		_symbol_icon.modulate = Color.WHITE


func toast(text: String) -> void:
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_a = 1.0
	_toast_panel.modulate.a = 1.0


func show_note(item_id: String) -> void:
	var note_id := str(ItemDB.get_item(item_id).get("note", ""))
	if note_id == "":
		return
	var note: Dictionary = StoryData.NOTES.get(note_id, {})
	_note_title.text = str(note.get("title", ""))
	_note_text.text = str(note.get("text", ""))
	_note_root.visible = true


# --- builders ----------------------------------------------------------------

func _bar_panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	var sb := UIStyle.panel(Color(0.05, 0.045, 0.04, 0.72), UIStyle.GOLD_DIM, 5, 1)
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = pos.x
	p.offset_top = -pos.y - sz.y
	p.offset_right = pos.x + sz.x
	p.offset_bottom = -pos.y
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


func _build_bars() -> void:
	var hp_bg := _bar_panel(Vector2(16, 64), Vector2(300, 26))
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.62, 0.15, 0.11)
	_hp_fill.position = Vector2(3, 3)
	_hp_fill.size = Vector2(294, 20)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bg.add_child(_hp_fill)
	_hp_label = UIStyle.label("", 12, Color(1, 0.92, 0.85))
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bg.add_child(_hp_label)

	var st_bg := _bar_panel(Vector2(16, 34), Vector2(240, 18))
	_st_fill = ColorRect.new()
	_st_fill.color = Color(0.30, 0.52, 0.26)
	_st_fill.position = Vector2(3, 3)
	_st_fill.size = Vector2(234, 12)
	_st_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st_bg.add_child(_st_fill)


func _build_tracker() -> void:
	_tracker = PanelContainer.new()
	var sb := UIStyle.panel(Color(0.05, 0.045, 0.04, 0.66), UIStyle.GOLD_DIM, 7, 1)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 9.0
	_tracker.add_theme_stylebox_override("panel", sb)
	_tracker.offset_left = 16.0
	_tracker.offset_top = 14.0
	_tracker.offset_right = 330.0
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker.visible = false
	add_child(_tracker)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_tracker.add_child(v)
	_tracker_title = UIStyle.title_label("", 15)
	v.add_child(_tracker_title)
	_tracker_obj = UIStyle.label("", 13, UIStyle.PARCHMENT)
	_tracker_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tracker_obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_tracker_obj)


func _build_compass() -> void:
	_compass = CompassBar.new()
	_compass.anchor_left = 0.5
	_compass.anchor_right = 0.5
	_compass.offset_left = -230.0
	_compass.offset_right = 230.0
	_compass.offset_top = 12.0
	_compass.offset_bottom = 46.0
	add_child(_compass)


func _build_hotbar() -> void:
	_slot_normal = UIStyle.panel(Color(0.07, 0.065, 0.06, 0.78), UIStyle.GOLD_DIM, 8, 1)
	_slot_normal.content_margin_left = 8.0
	_slot_normal.content_margin_right = 8.0
	_slot_normal.content_margin_top = 6.0
	_slot_normal.content_margin_bottom = 6.0
	_slot_equipped = _slot_normal.duplicate() as StyleBoxFlat
	_slot_equipped.border_color = UIStyle.GOLD
	_slot_equipped.set_border_width_all(2)

	_slot_panel = PanelContainer.new()
	_slot_panel.add_theme_stylebox_override("panel", _slot_normal)
	_slot_panel.anchor_left = 1.0
	_slot_panel.anchor_right = 1.0
	_slot_panel.anchor_top = 1.0
	_slot_panel.anchor_bottom = 1.0
	_slot_panel.offset_left = -92.0
	_slot_panel.offset_top = -104.0
	_slot_panel.offset_right = -16.0
	_slot_panel.offset_bottom = -30.0
	_slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_slot_panel.add_child(v)
	_slot_icon = ItemIcon.new("sword")
	_slot_icon.custom_minimum_size = Vector2(32, 32)
	v.add_child(_slot_icon)
	_hotbar_label = UIStyle.label("1 · пусто", 12, UIStyle.PARCHMENT_DIM)
	_hotbar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hotbar_label)

	# The hand symbol appears next to the hotbar after the intro.
	_symbol_slot = PanelContainer.new()
	var sym_sb := UIStyle.panel(Color(0.06, 0.05, 0.05, 0.75), UIStyle.GOLD_DIM, 8, 1)
	sym_sb.content_margin_left = 6.0
	sym_sb.content_margin_right = 6.0
	sym_sb.content_margin_top = 6.0
	sym_sb.content_margin_bottom = 6.0
	_symbol_slot.add_theme_stylebox_override("panel", sym_sb)
	_symbol_slot.anchor_left = 1.0
	_symbol_slot.anchor_right = 1.0
	_symbol_slot.anchor_top = 1.0
	_symbol_slot.anchor_bottom = 1.0
	_symbol_slot.offset_left = -144.0
	_symbol_slot.offset_top = -104.0
	_symbol_slot.offset_right = -100.0
	_symbol_slot.offset_bottom = -60.0
	_symbol_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_symbol_slot)
	_symbol_icon = ItemIcon.new("rune")
	_symbol_icon.custom_minimum_size = Vector2(32, 32)
	_symbol_slot.add_child(_symbol_icon)

	var hint := UIStyle.label("Tab — инвентарь · J — журнал", 11, Color(1, 1, 1, 0.55))
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -260.0
	hint.offset_top = -26.0
	hint.offset_right = -16.0
	hint.offset_bottom = -12.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func _build_prompt_and_cross() -> void:
	_prompt = Label.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -240.0
	_prompt.offset_right = 240.0
	_prompt.offset_top = -132.0
	_prompt.offset_bottom = -106.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)

	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.55)
	cross.anchor_left = 0.5
	cross.anchor_right = 0.5
	cross.anchor_top = 0.5
	cross.anchor_bottom = 0.5
	cross.offset_left = -2.0
	cross.offset_right = 2.0
	cross.offset_top = -2.0
	cross.offset_bottom = 2.0
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)


func _build_subtitles() -> void:
	_sub_panel = PanelContainer.new()
	var sb := UIStyle.panel(Color(0.03, 0.03, 0.035, 0.72), Color(0, 0, 0, 0), 6, 0)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 9.0
	_sub_panel.add_theme_stylebox_override("panel", sb)
	_sub_panel.anchor_left = 0.5
	_sub_panel.anchor_right = 0.5
	_sub_panel.anchor_top = 1.0
	_sub_panel.anchor_bottom = 1.0
	_sub_panel.offset_left = -430.0
	_sub_panel.offset_right = 430.0
	_sub_panel.offset_top = -208.0
	_sub_panel.offset_bottom = -152.0
	_sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_panel.visible = false
	add_child(_sub_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_sub_panel.add_child(v)
	_sub_speaker = UIStyle.title_label("", 13)
	_sub_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sub_speaker)
	_sub_text = UIStyle.label("", 16, Color(0.93, 0.90, 0.82))
	_sub_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sub_text)


func _build_vision() -> void:
	_lb_top = ColorRect.new()
	_lb_top.color = Color(0, 0, 0, 0.9)
	_lb_top.anchor_right = 1.0
	_lb_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lb_top)
	_lb_bottom = ColorRect.new()
	_lb_bottom.color = Color(0, 0, 0, 0.9)
	_lb_bottom.anchor_left = 0.0
	_lb_bottom.anchor_right = 1.0
	_lb_bottom.anchor_top = 1.0
	_lb_bottom.anchor_bottom = 1.0
	_lb_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lb_bottom)
	_vignette = ColorRect.new()
	_vignette.color = Color(0.07, 0.10, 0.18, 0.0)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)


func _build_flash_and_death() -> void:
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(0.7, 0.08, 0.05, 0.0)
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	_death_overlay = Control.new()
	_death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_overlay.visible = false
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death_overlay)

	var dark := ColorRect.new()
	dark.color = Color(0.05, 0.015, 0.015, 0.62)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(dark)

	var label := UIStyle.title_label("ВЫ ПОГИБЛИ", 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_top = 0.42
	label.anchor_bottom = 0.52
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(label)

	var sub := UIStyle.label("Возрождение...", 16, UIStyle.PARCHMENT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.anchor_right = 1.0
	sub.anchor_top = 0.52
	sub.anchor_bottom = 0.58
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(sub)


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	var sb := UIStyle.panel(Color(0.07, 0.06, 0.05, 0.86), UIStyle.GOLD_DIM, 7, 1)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 8.0
	_toast_panel.add_theme_stylebox_override("panel", sb)
	_toast_panel.anchor_left = 1.0
	_toast_panel.anchor_right = 1.0
	_toast_panel.offset_left = -340.0
	_toast_panel.offset_right = -16.0
	_toast_panel.offset_top = 56.0
	_toast_panel.offset_bottom = 92.0
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	add_child(_toast_panel)
	_toast_label = UIStyle.label("", 13)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_label)


func _build_perf() -> void:
	_perf = Label.new()
	_perf.anchor_left = 1.0
	_perf.anchor_right = 1.0
	_perf.offset_left = -190.0
	_perf.offset_right = -10.0
	_perf.offset_top = 8.0
	_perf.offset_bottom = 24.0
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf.add_theme_font_size_override("font_size", 12)
	_perf.modulate = Color(1, 1, 1, 0.5)
	_perf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_perf)


func _build_chapter_card() -> void:
	_chapter_root = Control.new()
	_chapter_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chapter_root.visible = false
	_chapter_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chapter_root)

	var dark := ColorRect.new()
	dark.color = Color(0.02, 0.015, 0.01, 0.55)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter_root.add_child(dark)

	_chapter_title = UIStyle.title_label("", 46)
	_chapter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chapter_title.anchor_right = 1.0
	_chapter_title.anchor_top = 0.38
	_chapter_title.anchor_bottom = 0.50
	_chapter_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter_root.add_child(_chapter_title)

	_chapter_sub = UIStyle.label("", 18, UIStyle.PARCHMENT)
	_chapter_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chapter_sub.anchor_right = 1.0
	_chapter_sub.anchor_top = 0.50
	_chapter_sub.anchor_bottom = 0.56
	_chapter_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter_root.add_child(_chapter_sub)


func _build_note_reader() -> void:
	_note_root = Control.new()
	_note_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_note_root.visible = false
	_note_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_note_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_note_root.add_child(dim)

	var panel := PanelContainer.new()
	var sb := UIStyle.framed_panel(Color(0.10, 0.09, 0.07, 0.98))
	sb.content_margin_left = 26.0
	sb.content_margin_right = 26.0
	sb.content_margin_top = 18.0
	sb.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -210.0
	panel.offset_bottom = 210.0
	_note_root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_note_title = UIStyle.title_label("", 18)
	v.add_child(_note_title)
	_note_text = UIStyle.label("", 14, UIStyle.PARCHMENT)
	_note_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_note_text)
	var close_btn := UIStyle.button("Закрыть", 13)
	close_btn.pressed.connect(_close_note)
	v.add_child(close_btn)


func _close_note() -> void:
	_note_root.visible = false


# --- inventory window --------------------------------------------------------

func _build_inventory() -> void:
	_inventory_panel = CenterContainer.new()
	_inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_panel.visible = false
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_inventory_panel)

	var window := PanelContainer.new()
	var sb := UIStyle.framed_panel()
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	window.add_theme_stylebox_override("panel", sb)
	_inventory_panel.add_child(window)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(760, 470)
	window.add_child(v)

	# Header + tabs.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var title := UIStyle.title_label("ИНВЕНТАРЬ", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_tab_items_btn = UIStyle.button("Вещи", 14)
	_tab_items_btn.pressed.connect(_switch_tab.bind(0))
	head.add_child(_tab_items_btn)
	_tab_journal_btn = UIStyle.button("Журнал", 14)
	_tab_journal_btn.pressed.connect(_switch_tab.bind(1))
	head.add_child(_tab_journal_btn)

	# Content: equipment column + list column.
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(250, 0)
	content.add_child(left)

	var eq_header := UIStyle.title_label("СНАРЯЖЕНИЕ", 14)
	left.add_child(eq_header)
	var eq_panel := PanelContainer.new()
	eq_panel.add_theme_stylebox_override("panel", UIStyle.panel(UIStyle.INK_SOFT, UIStyle.GOLD_DIM, 8, 1))
	left.add_child(eq_panel)
	var eq_v := VBoxContainer.new()
	eq_v.add_theme_constant_override("separation", 6)
	eq_panel.add_child(eq_v)
	var eq_row := HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 10)
	eq_v.add_child(eq_row)
	_eq_icon = ItemIcon.new("sword")
	_eq_icon.custom_minimum_size = Vector2(30, 30)
	eq_row.add_child(_eq_icon)
	_eq_name = UIStyle.label("— руки", 14)
	_eq_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_row.add_child(_eq_name)
	_eq_stat = UIStyle.label("", 12, UIStyle.PARCHMENT_DIM)
	eq_v.add_child(_eq_stat)

	var stats_header := UIStyle.title_label("ГЕРОЙ", 14)
	left.add_child(stats_header)
	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", UIStyle.panel(UIStyle.INK_SOFT, UIStyle.GOLD_DIM, 8, 1))
	left.add_child(stats_panel)
	var stats_v := VBoxContainer.new()
	stats_v.add_theme_constant_override("separation", 4)
	stats_panel.add_child(stats_v)
	stats_v.add_child(UIStyle.label("Жизни:  100", 13))
	stats_v.add_child(UIStyle.label("Силы:  100", 13))
	var dmg_row := UIStyle.label("Урон:  34", 13)
	stats_v.add_child(dmg_row)
	stats_v.add_child(UIStyle.label("Эхо:  слышит мёртвых", 13, UIStyle.PARCHMENT_DIM))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(right)

	_items_scroll = ScrollContainer.new()
	_items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_items_scroll)
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 6)
	_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_scroll.add_child(_items_box)

	_journal_scroll = ScrollContainer.new()
	_journal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_journal_scroll)
	_journal_scroll.visible = false
	_journal_box = VBoxContainer.new()
	_journal_box.add_theme_constant_override("separation", 8)
	_journal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.add_child(_journal_box)

	# Detail box + actions.
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UIStyle.panel(UIStyle.INK_SOFT, UIStyle.GOLD_DIM, 8, 1))
	detail.custom_minimum_size = Vector2(0, 96)
	v.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	detail.add_child(dv)
	_detail_name = UIStyle.title_label("Ничего не выбрано", 15)
	dv.add_child(_detail_name)
	_detail_desc = UIStyle.label("Выбери предмет в списке справа.", 13, UIStyle.PARCHMENT_DIM)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(_detail_desc)
	_detail_stat = UIStyle.label("", 12, UIStyle.GOLD)
	dv.add_child(_detail_stat)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(actions)
	_btn_action = UIStyle.button("Экипировать", 14)
	_btn_action.pressed.connect(_on_action_pressed)
	actions.add_child(_btn_action)
	_btn_read = UIStyle.button("Прочитать", 14)
	_btn_read.pressed.connect(_on_read_pressed)
	actions.add_child(_btn_read)

	_switch_tab(0)


func _switch_tab(tab: int) -> void:
	_inv_tab = tab
	_items_scroll.visible = tab == 0
	_journal_scroll.visible = tab == 1
	_tab_items_btn.add_theme_color_override("font_color",
				UIStyle.GOLD if tab == 0 else UIStyle.PARCHMENT)
	_tab_journal_btn.add_theme_color_override("font_color",
				UIStyle.GOLD if tab == 1 else UIStyle.PARCHMENT)
	_rebuild_right()


func _rebuild_right() -> void:
	if _inv_tab == 0:
		_rebuild_items()
	else:
		_rebuild_journal()


func _rebuild_items() -> void:
	for c in _items_box.get_children():
		(c as Node).queue_free()
	if _player == null:
		return
	if _player.inventory.is_empty():
		var empty := UIStyle.label("Пусто. Мир велик — загляни в углы.", 13, UIStyle.PARCHMENT_DIM)
		_items_box.add_child(empty)
		return
	for id in _player.inventory:
		_items_box.add_child(_make_item_row(str(id)))


func _make_item_row(id: String) -> Control:
	var meta := ItemDB.get_item(id)
	var row := PanelContainer.new()
	var selected := id == _selected_id
	var equipped := id == "steel_sword" and _player != null and _player.sword_equipped
	var sb := UIStyle.panel(UIStyle.INK_SOFT if not selected else Color(0.16, 0.13, 0.08, 0.95),
			UIStyle.GOLD if selected else UIStyle.GOLD_DIM, 7, 1 if not selected else 2)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("id", id)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	var kind := str(meta.get("type", "note"))
	var icon_kind := "sword" if kind == "weapon" else ("shard" if kind == "quest" else "note")
	var icon := ItemIcon.new(icon_kind)
	icon.custom_minimum_size = Vector2(26, 26)
	h.add_child(icon)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var name_l := UIStyle.label(str(meta.get("name", id)), 14)
	v.add_child(name_l)
	var type_text := str(meta.get("stat", ""))
	var tags := ""
	if equipped:
		tags = "  ·  в руках"
	if type_text != "":
		name_l.text = str(meta.get("name", id)) + tags

	var hint := UIStyle.label(type_text, 11, UIStyle.PARCHMENT_DIM)
	v.add_child(hint)

	row.gui_input.connect(_on_row_input.bind(id))
	row.mouse_entered.connect(_on_row_hover.bind(row, true))
	row.mouse_exited.connect(_on_row_hover.bind(row, false))
	return row


func _on_row_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_select_item(id)


func _on_row_hover(row: Control, entered: bool) -> void:
	if str(row.get_meta("id", "")) == _selected_id:
		return
	var sb := UIStyle.panel(UIStyle.INK_SOFT if not entered else Color(0.13, 0.11, 0.08, 0.95),
			UIStyle.GOLD_DIM, 7, 1)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	(row as PanelContainer).add_theme_stylebox_override("panel", sb)


func _select_item(id: String) -> void:
	_selected_id = id
	_rebuild_items()
	_refresh_detail()


func _refresh_detail() -> void:
	if _selected_id == "":
		_detail_name.text = "Ничего не выбрано"
		_detail_desc.text = "Выбери предмет в списке."
		_detail_stat.text = ""
		_btn_action.visible = false
		_btn_read.visible = false
		return
	var meta := ItemDB.get_item(_selected_id)
	_detail_name.text = str(meta.get("name", _selected_id))
	_detail_desc.text = str(meta.get("desc", ""))
	_detail_stat.text = str(meta.get("stat", ""))
	var kind := str(meta.get("type", ""))
	_btn_action.visible = kind == "weapon"
	_btn_action.text = "Снять" if (_player != null and _player.sword_equipped) else "Экипировать"
	_btn_read.visible = kind == "note"


func _rebuild_journal() -> void:
	for c in _journal_box.get_children():
		(c as Node).queue_free()
	if _qm == null:
		_journal_box.add_child(UIStyle.label("Журнал недоступен.", 13, UIStyle.PARCHMENT_DIM))
		return
	if _qm.active_id == "" and _qm.completed.is_empty():
		_journal_box.add_child(UIStyle.label("Пока ничего. Но дорога уже зовёт.", 13, UIStyle.PARCHMENT_DIM))
		return
	if _qm.active_id != "":
		var active := PanelContainer.new()
		var sb := UIStyle.panel(UIStyle.INK_SOFT, UIStyle.GOLD, 8, 1)
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 10.0
		active.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		active.add_child(v)
		var t := StoryData.quest(_qm.active_id)
		v.add_child(UIStyle.title_label(str(t.get("title", "")) + "  ·  текущее", 15))
		var obj := _qm.current_objective()
		if obj != "":
			v.add_child(UIStyle.label("Сейчас:  " + obj + "  " + _qm.counter_progress(), 13))
		var entry := _qm.stage_journal(_qm.active_id, _qm.active_stage)
		if entry != "":
			var l := UIStyle.label(entry, 13, UIStyle.PARCHMENT_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(380, 0)
			v.add_child(l)
		_journal_box.add_child(active)
	if not _qm.completed.is_empty():
		_journal_box.add_child(UIStyle.title_label("ВЫПОЛНЕНО", 13))
		for qid in _qm.completed:
			var row := UIStyle.label("✓  " + str(StoryData.quest(str(qid)).get("title", str(qid))),
					13, UIStyle.PARCHMENT_DIM)
			_journal_box.add_child(row)


func _on_action_pressed() -> void:
	if _player != null and _selected_id == "steel_sword":
		_player.toggle_equip()


func _on_read_pressed() -> void:
	if _selected_id != "":
		show_note(_selected_id)


# --- quest signal handlers ---------------------------------------------------

func _on_quest_started(id: String, title: String) -> void:
	_tracker.visible = true
	_tracker_title.text = title
	_refresh_objective()
	_update_marker()
	toast("Новое задание: " + title)
	if _inv_tab == 1 and _inventory_panel.visible:
		_rebuild_journal()


func _on_stage_changed(_id: String, _stage: int, objective: String, marker: String) -> void:
	_tracker_obj.text = objective + "  " + _qm.counter_progress()
	_update_marker()
	toast("Задание обновлено")


func _on_quest_completed(_id: String, title: String) -> void:
	_tracker.visible = false
	_update_marker()
	toast("Задание выполнено: " + title)


func _on_counter_changed(_id: String, _cur: int, _need: int) -> void:
	_refresh_objective()


func _on_symbol_revealed() -> void:
	set_symbol(true, true)
	toast("На руке тлеет незнакомый символ")


func _on_chapter_finished(chapter: int) -> void:
	_chapter_title.text = "Глава %d завершена" % chapter
	_chapter_sub.text = "Эйргард запомнит твоё имя"
	_chapter_root.modulate.a = 0.0
	_chapter_root.visible = true
	_chapter_t = 0.0


func _refresh_objective() -> void:
	if _qm == null:
		return
	_tracker_obj.text = _qm.current_objective() + "  " + _qm.counter_progress()


func _update_marker() -> void:
	if _qm == null or _compass == null:
		return
	var key := _qm.current_marker_key()
	if key == "":
		_compass.set_marker(Vector3.INF, false)
		return
	var pos := _qm.get_marker(key)
	_compass.set_marker(pos, pos != Vector3.INF)


# --- player signal handlers --------------------------------------------------

func _on_hp(hp: float, max_hp: float) -> void:
	var ratio := clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_hp_fill.size.x = 294.0 * ratio
	_hp_label.text = "%d / %d" % [int(ceilf(hp)), int(max_hp)]


func _on_stamina(value: float, max_value: float) -> void:
	var ratio := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
	_st_fill.size.x = 234.0 * ratio


func _on_sword(has_sword: bool, equipped: bool) -> void:
	_hotbar_label.text = "1 · Стальной меч" if has_sword else "1 · пусто"
	_slot_icon.visible = has_sword
	_slot_panel.add_theme_stylebox_override("panel", _slot_equipped if equipped else _slot_normal)
	_eq_name.text = "Стальной меч" if equipped else "— руки"
	_eq_stat.text = "Урон 34" if equipped else ""
	_refresh_detail()
	if _inv_tab == 0 and _inventory_panel.visible:
		_rebuild_items()


func _on_prompt(text: String) -> void:
	_prompt.text = text


func _on_inventory(open: bool) -> void:
	_inventory_panel.visible = open
	if open:
		_select_item("")
		_rebuild_right()
		_rebuild_equipment_card()


func _on_inv_changed() -> void:
	if _inventory_panel.visible:
		_rebuild_items()


func _on_journal_key(open: bool) -> void:
	if open:
		_switch_tab(1)
		_rebuild_journal()


func _rebuild_equipment_card() -> void:
	if _player == null:
		return
	if _player.sword_equipped:
		_eq_name.text = "Стальной меч"
		_eq_stat.text = "Урон 34"
	else:
		_eq_name.text = "— руки"
		_eq_stat.text = ""


func _on_equip_pressed() -> void:
	if _player != null:
		_player.toggle_equip()


func _on_hurt(_amount: float) -> void:
	_flash_a = 1.0


func _on_died() -> void:
	_death_overlay.visible = true


func _on_respawned() -> void:
	_death_overlay.visible = false
