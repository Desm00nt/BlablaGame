class_name GameHUD
extends CanvasLayer

## In-game UI, built in code like everything else in the project (no scenes
## with theme resources to maintain). Listens to Player signals:
##   HP / stamina bars, hotbar slot, interact prompt, inventory panel,
##   damage flash, death overlay, and a throttled perf readout.
##
## All text updates are event-driven; the only per-frame work is the damage
## flash fade and a 2 Hz perf label.

var _player: Player
var _hp_fill: ColorRect
var _st_fill: ColorRect
var _prompt: Label
var _hotbar_label: Label
var _slot_panel: PanelContainer
var _slot_normal: StyleBoxFlat
var _slot_equipped: StyleBoxFlat
var _equip_button: Button
var _inventory_panel: CenterContainer
var _flash_rect: ColorRect
var _death_overlay: Control
var _perf: Label
var _flash_a: float = 0.0
var _perf_t: float = 0.0
var _instances: int = 0


func _ready() -> void:
	layer = 10
	_build_bars()
	_build_hotbar()
	_build_prompt_and_cross()
	_build_inventory()
	_build_overlays()


## Must be called after the player is in the tree.
func setup(player: Player, instance_count: int) -> void:
	_player = player
	_instances = instance_count
	player.hp_changed.connect(_on_hp)
	player.stamina_changed.connect(_on_stamina)
	player.sword_state_changed.connect(_on_sword)
	player.prompt_changed.connect(_on_prompt)
	player.inventory_toggled.connect(_on_inventory)
	player.hurt.connect(_on_hurt)
	player.died.connect(_on_died)
	player.respawned.connect(_on_respawned)
	_on_hp(player.hp, player.max_hp)
	_on_stamina(player.stamina, player.max_stamina)
	_on_sword(player.has_sword, player.sword_equipped)
	_on_prompt("")


func _process(delta: float) -> void:
	if _flash_a > 0.0:
		_flash_a = maxf(_flash_a - delta * 1.5, 0.0)
		_flash_rect.color.a = _flash_a * 0.45
	_perf_t += delta
	if _perf_t >= 0.5:
		_perf_t = 0.0
		_perf.text = "fps %d · props %d" % [Engine.get_frames_per_second(), _instances]


# --- builders ---------------------------------------------------------------

func _bar(color: Color, bottom: float, height: float, width: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.anchor_top = 1.0
	r.anchor_bottom = 1.0
	r.offset_left = 16.0
	r.offset_top = -bottom - height
	r.offset_right = 16.0 + width
	r.offset_bottom = -bottom
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build_bars() -> void:
	var hp_bg := _bar(Color(0.08, 0.08, 0.1, 0.7), 52.0, 20.0, 264.0)
	add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.78, 0.16, 0.12)
	_hp_fill.position = Vector2(2, 2)
	_hp_fill.size = Vector2(260, 16)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bg.add_child(_hp_fill)

	var st_bg := _bar(Color(0.08, 0.08, 0.1, 0.7), 24.0, 14.0, 200.0)
	add_child(st_bg)
	_st_fill = ColorRect.new()
	_st_fill.color = Color(0.2, 0.62, 0.25)
	_st_fill.position = Vector2(2, 2)
	_st_fill.size = Vector2(196, 10)
	_st_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st_bg.add_child(_st_fill)


func _build_hotbar() -> void:
	_slot_normal = StyleBoxFlat.new()
	_slot_normal.bg_color = Color(0.1, 0.1, 0.12, 0.75)
	_slot_normal.set_corner_radius_all(6)
	_slot_normal.border_color = Color(0.45, 0.45, 0.5)
	_slot_normal.set_border_width_all(2)
	_slot_normal.content_margin_left = 10.0
	_slot_normal.content_margin_right = 10.0
	_slot_normal.content_margin_top = 6.0
	_slot_normal.content_margin_bottom = 6.0
	_slot_equipped = _slot_normal.duplicate() as StyleBoxFlat
	_slot_equipped.border_color = Color(0.85, 0.68, 0.25)

	_slot_panel = PanelContainer.new()
	_slot_panel.add_theme_stylebox_override("panel", _slot_normal)
	_slot_panel.anchor_left = 1.0
	_slot_panel.anchor_right = 1.0
	_slot_panel.anchor_top = 1.0
	_slot_panel.anchor_bottom = 1.0
	_slot_panel.offset_left = -84.0
	_slot_panel.offset_top = -92.0
	_slot_panel.offset_right = -16.0
	_slot_panel.offset_bottom = -48.0
	_slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_panel)

	_hotbar_label = Label.new()
	_hotbar_label.text = "1 · пусто"
	_hotbar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_panel.add_child(_hotbar_label)

	var hint := Label.new()
	hint.text = "Tab — инвентарь"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -140.0
	hint.offset_top = -40.0
	hint.offset_right = -16.0
	hint.offset_bottom = -26.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func _build_prompt_and_cross() -> void:
	_prompt = Label.new()
	_prompt.text = ""
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -200.0
	_prompt.offset_right = 200.0
	_prompt.offset_top = -120.0
	_prompt.offset_bottom = -96.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)

	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.5)
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


func _build_inventory() -> void:
	_inventory_panel = CenterContainer.new()
	_inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_panel.visible = false
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_inventory_panel)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.12, 0.92)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(0.85, 0.68, 0.25)
	sb.set_border_width_all(2)
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", sb)
	_inventory_panel.add_child(panel)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(380, 0)
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var title := Label.new()
	title.text = "Инвентарь"
	title.add_theme_font_size_override("font_size", 22)
	v.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)

	var icon := ColorRect.new()
	icon.color = Color(0.78, 0.80, 0.84)
	icon.custom_minimum_size = Vector2(34, 34)
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = "Стальной меч\nУрон 34 · надёжный спутник наёмника"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	_equip_button = Button.new()
	_equip_button.text = "Экипировать"
	_equip_button.custom_minimum_size = Vector2(130, 0)
	_equip_button.pressed.connect(_on_equip_pressed)
	row.add_child(_equip_button)

	var hint := Label.new()
	hint.text = "Tab — закрыть · 1 — быстро экипировать/снять"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(hint)


func _build_overlays() -> void:
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(0.8, 0.1, 0.1, 0.0)
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	_death_overlay = Control.new()
	_death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_overlay.visible = false
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death_overlay)

	var dark := ColorRect.new()
	dark.color = Color(0.05, 0.02, 0.02, 0.6)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(dark)

	var label := Label.new()
	label.text = "Вы погибли\nВозрождение..."
	label.add_theme_font_size_override("font_size", 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_top = -60.0
	label.offset_bottom = 60.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(label)

	_perf = Label.new()
	_perf.text = ""
	_perf.anchor_left = 1.0
	_perf.anchor_right = 1.0
	_perf.offset_left = -170.0
	_perf.offset_right = -10.0
	_perf.offset_top = 8.0
	_perf.offset_bottom = 26.0
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf.add_theme_font_size_override("font_size", 12)
	_perf.modulate = Color(1, 1, 1, 0.55)
	_perf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_perf)


# --- signal handlers --------------------------------------------------------

func _on_hp(hp: float, max_hp: float) -> void:
	var ratio := clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_hp_fill.size.x = 260.0 * ratio


func _on_stamina(value: float, max_value: float) -> void:
	var ratio := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
	_st_fill.size.x = 196.0 * ratio


func _on_sword(has_sword: bool, equipped: bool) -> void:
	_hotbar_label.text = "1 · Стальной меч" if has_sword else "1 · пусто"
	_slot_panel.add_theme_stylebox_override("panel", _slot_equipped if equipped else _slot_normal)
	_equip_button.text = "Снять" if equipped else "Экипировать"


func _on_prompt(text: String) -> void:
	_prompt.text = text


func _on_inventory(open: bool) -> void:
	_inventory_panel.visible = open


func _on_equip_pressed() -> void:
	if _player != null:
		_player.toggle_equip()


func _on_hurt(_amount: float) -> void:
	_flash_a = 1.0


func _on_died() -> void:
	_death_overlay.visible = true


func _on_respawned() -> void:
	_death_overlay.visible = false
