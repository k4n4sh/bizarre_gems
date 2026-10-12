extends Control
## Static menu illustration, using the same presentation assets as the game.
## No BoardLogic instance, gameplay RNG, input, score or save access.
var visual_profile := "classic":
	set(value):
		visual_profile = value
		queue_redraw()
var number_font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	var run := visual_profile == "classic_run"
	var columns := 8 if run else 10
	var rows := 4 if run else 5
	var cell := minf((size.x - 20) / columns, (size.y - 16) / rows)
	var start := (size - Vector2(columns, rows) * cell) / 2
	draw_texture_rect(preload("res://assets/ui/velvet.png"), Rect2(Vector2.ZERO, size), true)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.02, 0.08, 0.08, .3)
	frame.border_color = Color("#71633c")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(10)
	draw_style_box(frame, Rect2(Vector2.ONE, size - Vector2.ONE * 2))
	for y in rows:
		for x in columns:
			var i := y * columns + x
			var p := start + (Vector2(x,y) + Vector2.ONE * .5) * cell
			if (i % 7 == 3 or i % 11 == 0) and not (run and i in [6,13,17,21,24,28,30]):
				draw_circle(p, cell * .35, Color("#0a191d"))
				draw_arc(p,cell*.35,0,TAU,20,Color("#635936"),1,true)
				continue
			var kind := (x + y * 3) % 6 if run else (x * 3 + y * 7) % 10
			var texture: Texture2D = BoardView.GEM_TEX[BoardView.RUN_GEM_INDICES[kind] if run else kind]
			var gem_size := cell * .91
			if run and i == 13:
				BoardView.SpecialGemArt.joker(self,p,gem_size)
			else:
				draw_texture_rect(texture,Rect2(p-Vector2.ONE*gem_size/2,Vector2.ONE*gem_size),false)
			if run:
				BoardView.SpecialGemArt.overlays(self,p,gem_size,i==6,i==17 or i==30,i==21,8 if i==24 else 0,i==28,number_font)
