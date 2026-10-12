extends RefCounted
## Vector ornaments, only for classic_run. Never modifies game state.
const METAL := Color("#c6a35c")
const LIGHT := Color("#f2deb0")
const INK := Color("#112b30")
const FROST := Color("#bfe8ef")

static func outline(c: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	c.draw_polyline(closed, color, width, true)

static func octagon(p: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(p + Vector2.from_angle(-PI / 2 + i * TAU / 8) * r)
	return pts

static func joker(c: CanvasItem, p: Vector2, s: float) -> void:
	var pts := octagon(p, s * .4)
	var hues := [Color("#f1effa"),Color("#94bfc9"),Color("#e6d7a8"),Color("#fcfbff"),
		Color("#91a1b9"),Color("#d5e6e9"),Color("#bbadd5"),Color("#ffffff")]
	for i in 8:
		c.draw_colored_polygon(PackedVector2Array([p+Vector2(-.05,-.08)*s,pts[i],pts[(i+1)%8]]),hues[i])
	outline(c,pts,LIGHT,maxf(1,s*.025))
	var star := PackedVector2Array([p+Vector2(0,-.23)*s,p+Vector2(.05,-.05)*s,p+Vector2(.2,0)*s,
		p+Vector2(.05,.05)*s,p+Vector2(0,.23)*s,p+Vector2(-.05,.05)*s,p+Vector2(-.2,0)*s,p+Vector2(-.05,-.05)*s])
	c.draw_colored_polygon(star,INK)
	outline(c,star,Color.WHITE,maxf(1,s*.018))

static func overlays(c: CanvasItem, p: Vector2, s: float, boxed: bool, linked: bool, iced: bool, bomb: int, cham: bool, font: Font) -> void:
	var line := maxf(1.1,s*.027)
	if boxed:
		var rect := Rect2(p-Vector2.ONE*s*.43,Vector2.ONE*s*.86)
		c.draw_rect(rect,Color("#634c31"),false,maxf(3,s*.09))
		c.draw_rect(rect,METAL,false,line)
		for x in [-1,1]:
			for y in [-1,1]:
				var q := p+Vector2(x,y)*s*.37
				c.draw_line(q,p+Vector2(x,y)*s*.19,Color("#8e7042"),line*2,true)
				c.draw_circle(q,s*.025,LIGHT)
	if iced:
		var edge := octagon(p,s*.46)
		c.draw_colored_polygon(edge,Color(.62,.85,.91,.13))
		outline(c,edge,FROST,line)
		for i in [0,2,4,6]:
			var tip := edge[i]
			var inward := p+(tip-p)*.65
			c.draw_line(tip,inward,Color(FROST,.9),line,true)
			c.draw_line(inward,inward+Vector2(s*.07,-s*.06),Color(FROST,.75),line*.7,true)
	if cham:
		for i in 2:
			var col := METAL if i==0 else Color("#8ed6c9")
			var a := .12*PI+i*PI
			c.draw_arc(p,s*.43,a,a+PI*.64,14,col,line*1.25,true)
			var tip := p+Vector2.from_angle(a+PI*.64)*s*.43
			var tangent := Vector2.from_angle(a+PI*.64+PI/2)
			c.draw_colored_polygon(PackedVector2Array([tip,tip-tangent*s*.12+Vector2.from_angle(a+PI*.64)*s*.055,
				tip-tangent*s*.12-Vector2.from_angle(a+PI*.64)*s*.055]),col)
	if linked:
		var q := p+Vector2(-.27,.29)*s
		c.draw_circle(q,s*.19,INK)
		for dx in [-.065,.065]:
			var pts := PackedVector2Array()
			for j in 17:
				var a := j*TAU/16
				pts.append(q+Vector2(dx+cos(a)*.09,sin(a)*.065)*s)
			c.draw_polyline(pts,LIGHT,line,true)
	if bomb>0:
		var q := p+Vector2(.25,-.27)*s
		var r := s*.245
		c.draw_circle(q,r,INK)
		c.draw_arc(q,r,0,TAU,24,METAL,line,true)
		var fuse := PackedVector2Array([q+Vector2(0,-r),q+Vector2(.04,-.33)*s,q+Vector2(.12,-.34)*s])
		c.draw_polyline(fuse,METAL,line,true)
		c.draw_circle(fuse[-1],maxf(1.5,s*.03),Color("#f3ae64"))
		if font:
			var fs := maxi(10,int(s*.29))
			var text := str(bomb)
			var w := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
			c.draw_string(font,q+Vector2(-w/2,fs*.34),text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color("#ff8069") if bomb<=2 else Color("#fff3d5"))
