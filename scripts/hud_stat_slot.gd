extends Control
## A stable layout slot. Content minimum-size changes never reach the HUD containers.
## Fit and centre the entire visual block, including captions and progress bars.

var content: Control
var vertical_padding := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_fit)
	content = get_child(0) as Control
	content.minimum_size_changed.connect(_fit)
	_fit.call_deferred()

func _fit() -> void:
	if not is_instance_valid(content):
		return
	var minimum := content.get_combined_minimum_size()
	var extent := Vector2(maxf(size.x, minimum.x), minimum.y)
	var fit := minf(1.0, minf(size.x / maxf(extent.x, 1.0), maxf(1.0, size.y - vertical_padding) / maxf(extent.y, 1.0)))
	content.size = extent
	content.scale = Vector2.ONE * fit
	content.position = (size - extent * fit) * 0.5
