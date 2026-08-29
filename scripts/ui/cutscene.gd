class_name CutscenePlayer
extends CanvasLayer

## Intro cinematic for "Пепельная Корона", Act I.
##
## Timeline (all timings in seconds, driven by _process, no Tween nodes):
##   0.0-12.5  black screen, five lore slides fading in/out
##   12.5-15.0 fade from black; the camera hangs high over the wrecked camp
##   15.0-21.0 slow descend toward the hero lying in the ashes, letterboxed
##   21.0      the hero wakes, the hand symbol flares (HUD)
##   21.0-26.0 title card "ПЕПЕЛЬНАЯ КОРОНА" + "Глава I · Пепел"
##   26.0      finished - control returns to the player
##
## Any key / mouse press skips to the end. The player camera is made current
## again in _finish().

signal finished

const SLIDES := [
	"ЭЙРГАРД.\nСтрана гор, хвойных лесов и древних крепостей.",
	"Триста лет назад последний король объединил страну\nс помощью Пепельной Короны — артефакта,\nчто позволял говорить с мёртвыми богами.",
	"После его смерти Корону раскололи на семь частей.\nСемь замков — как говорили жрецы.\nЛегенда стала сказкой. Сказка забылась.",
	"В этот месяц из старых курганов вышли мёртвые.\nИх называют Пустыми.",
	"Этой ночью на караван напали.\nВсе погибли.\n\nКроме тебя.",
]

# Camera keyframes: [t, position]. Look target is always the hero's chest.
const CAM_PATH := [
	[12.5, Vector3(2.0, 13.0, -14.0)],
	[16.0, Vector3(4.5, 6.0, -8.5)],
	[21.0, Vector3(3.4, 1.7, -3.6)],
]

const TITLE_AT: float = 21.0
const END_AT: float = 26.0

var player: Player = null
var hud: GameHUD = null

var _cam: Camera3D
var _black: ColorRect
var _slide_label: Label
var _title_label: Label
var _subtitle_label: Label
var _letterbox_top: ColorRect
var _letterbox_bottom: ColorRect
var _skip_label: Label
var _t: float = 0.0
var _slide_idx: int = -1
var _done: bool = false
var _look_target: Vector3


func _ready() -> void:
	layer = 20
	visible = false


## Called by main once the player and HUD exist. Builds the overlay, takes
## the camera and starts the timeline.
func start() -> void:
	visible = true
	_build()
	if player != null:
		_look_target = player.global_position + Vector3(0.0, 0.9, 0.0)
	_cam = Camera3D.new()
	_cam.fov = 58.0
	get_parent().add_child(_cam)
	_cam.global_position = CAM_PATH[0][1]
	_cam.look_at(_look_target, Vector3.UP)
	_cam.make_current()
	_t = 0.0
	_slide_idx = -1


func _build() -> void:
	_black = ColorRect.new()
	_black.color = Color(0.015, 0.012, 0.01, 1.0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)

	_slide_label = Label.new()
	_slide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slide_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slide_label.add_theme_font_size_override("font_size", 20)
	_slide_label.add_theme_color_override("font_color", UIStyle.PARCHMENT)
	_slide_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slide_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.add_child(_slide_label)

	var lb_h := 54.0
	_letterbox_top = ColorRect.new()
	_letterbox_top.color = Color(0, 0, 0, 0.92)
	_letterbox_top.anchor_right = 1.0
	_letterbox_top.offset_bottom = 0.0
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_top)
	_letterbox_bottom = ColorRect.new()
	_letterbox_bottom.color = Color(0, 0, 0, 0.92)
	_letterbox_bottom.anchor_left = 0.0
	_letterbox_bottom.anchor_right = 1.0
	_letterbox_bottom.anchor_top = 1.0
	_letterbox_bottom.anchor_bottom = 1.0
	_letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_bottom)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 52)
	_title_label.add_theme_color_override("font_color", UIStyle.GOLD)
	_title_label.add_theme_constant_override("outline_size", 10)
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title_label.anchor_left = 0.0
	_title_label.anchor_right = 1.0
	_title_label.anchor_top = 0.34
	_title_label.anchor_bottom = 0.44
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 19)
	_subtitle_label.add_theme_color_override("font_color", UIStyle.PARCHMENT)
	_subtitle_label.anchor_left = 0.0
	_subtitle_label.anchor_right = 1.0
	_subtitle_label.anchor_top = 0.44
	_subtitle_label.anchor_bottom = 0.50
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle_label)

	_skip_label = UIStyle.label("любая клавиша — пропустить", 12, UIStyle.PARCHMENT_DIM)
	_skip_label.anchor_left = 1.0
	_skip_label.anchor_right = 1.0
	_skip_label.anchor_top = 1.0
	_skip_label.anchor_bottom = 1.0
	_skip_label.offset_left = -240.0
	_skip_label.offset_right = -18.0
	_skip_label.offset_top = -34.0
	_skip_label.offset_bottom = -16.0
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skip_label)


func _process(delta: float) -> void:
	if _done or not visible:
		return
	_t += delta
	_update_slides()
	_update_camera()
	_update_letterbox()
	_update_title()
	if _t >= END_AT:
		_finish()


func _update_slides() -> void:
	var slide_count := SLIDES.size()
	var slide_len := 12.5 / float(slide_count)
	var idx := clampi(int(_t / slide_len), 0, slide_count - 1)
	if idx != _slide_idx:
		_slide_idx = idx
		_slide_label.text = str(SLIDES[idx])
	if _t < 12.5:
		# Fade each slide in and out inside its slot.
		var local := fmod(_t, slide_len)
		_slide_label.modulate.a = clampf(minf(local / 0.7, (slide_len - local) / 0.7), 0.0, 1.0)
		_black.color.a = 1.0
	elif _t < 14.5:
		_slide_label.modulate.a = 0.0
		_black.color.a = maxf(1.0 - (_t - 12.5) / 2.0, 0.0)
	else:
		_black.color.a = 0.0


func _update_camera() -> void:
	if _cam == null or player == null:
		return
	_look_target = player.global_position + Vector3(0.0, 0.9, 0.0)
	if _t < CAM_PATH[0][0]:
		_cam.global_position = CAM_PATH[0][1]
	elif _t < CAM_PATH[CAM_PATH.size() - 1][0]:
		for i in range(1, CAM_PATH.size()):
			var t0: float = float(CAM_PATH[i - 1][0])
			var t1: float = float(CAM_PATH[i][0])
			if _t <= t1:
				var k := smoothstep(0.0, 1.0, clampf((_t - t0) / (t1 - t0), 0.0, 1.0))
				var p0: Vector3 = CAM_PATH[i - 1][1]
				var p1: Vector3 = CAM_PATH[i][1]
				_cam.global_position = p0.lerp(p1, k)
				break
	else:
		var last: Vector3 = CAM_PATH[CAM_PATH.size() - 1][1]
		_cam.global_position = last
	_cam.look_at(_look_target, Vector3.UP)


func _update_letterbox() -> void:
	if _t < 12.5:
		_letterbox_top.offset_bottom = 0.0
		_letterbox_bottom.offset_top = 0.0
	else:
		var k := clampf((_t - 12.5) / 1.2, 0.0, 1.0)
		_letterbox_top.offset_bottom = 54.0 * k
		_letterbox_bottom.offset_top = -54.0 * k


func _update_title() -> void:
	if _t < TITLE_AT:
		_title_label.text = ""
		_subtitle_label.text = ""
		return
	var local := _t - TITLE_AT
	_title_label.text = "ПЕПЕЛЬНАЯ КОРОНА"
	_subtitle_label.text = "Глава I · Пепел"
	# Fade in fast, hold, fade out before the end.
	if local < 1.2:
		_title_label.modulate.a = local / 1.2
		_subtitle_label.modulate.a = local / 1.2
	elif local > 3.6:
		var k := clampf(1.0 - (local - 3.6) / 1.4, 0.0, 1.0)
		_title_label.modulate.a = k
		_subtitle_label.modulate.a = k
	else:
		_title_label.modulate.a = 1.0
		_subtitle_label.modulate.a = 1.0


## Jumps to the end state; safe to call twice (idempotent).
func skip() -> void:
	if _done:
		return
	_t = END_AT
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	visible = false
	if _cam != null:
		_cam.queue_free()
		_cam = null
	if player != null:
		player.finish_intro()
		player.camera.make_current()
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _done or not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		skip()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		skip()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		return
	if event.is_action_pressed("ui_accept"):
		skip()
