@tool
extends VBoxContainer
## Round icon button with a caption under it (home screen). Set the icon and caption key in the
## inspector; `badge` puts a red dot with that text ("3", "!") on the button's corner.

signal pressed

const BADGE := Color("#ff3b4e")

@export var icon: Texture2D:
	set(v):
		icon = v
		if is_node_ready():
			%Button.icon = v
@export var caption := "":
	set(v):
		caption = v
		if is_node_ready():
			_update_caption()
var badge := "":
	set(v):
		badge = v
		if _dot:
			_dot.visible = v != ""
			_dot.get_child(0).text = v
var _dot: PanelContainer


func _ready() -> void:
	%Button.icon = icon
	%Button.pressed.connect(func(): pressed.emit())
	_update_caption()
	_dot = PanelContainer.new()
	var st := UiKit.box(BADGE, Color.WHITE, 2, 99, Vector4(6, 0, 6, 0))
	_dot.add_theme_stylebox_override("panel", st)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.theme_type_variation = &"Bold"
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dot.add_child(l)
	%Button.add_child(_dot)
	_dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_dot.position += Vector2(4, -4)
	_dot.custom_minimum_size = Vector2(22, 22)
	badge = badge

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_caption()


func _update_caption() -> void:
	if is_node_ready():
		%Caption.text = tr(caption)
