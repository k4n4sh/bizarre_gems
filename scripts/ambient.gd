class_name Ambient
extends Control
## Living background: slow drifting pools of coloured light (one shader pass) and dust motes
## rising through them. pulse() brightens it briefly when something big happens on the board.

const SPARKLE_TEX := preload("res://assets/fx/sparkle.png")
## Recolour only the velvet texture, retaining its per-pixel luminance and alpha.
## Gems, slot ornaments, vignette and HUD are separate CanvasItems.
const VELVET_SHADER := """
shader_type canvas_item;
uniform vec4 fabric_color : source_color = vec4(0.05, 0.13, 0.14, 1.0);
uniform float fabric_strength = 0.0;
uniform vec2 fabric_shift = vec2(0.0);
void vertex() {
	VERTEX += fabric_shift;
}
void fragment() {
	vec3 weights = vec3(0.2126, 0.7152, 0.0722);
	float detail = dot(COLOR.rgb, weights);
	vec3 dyed = detail * fabric_color.rgb / max(dot(fabric_color.rgb, weights), 0.001);
	COLOR.rgb = mix(COLOR.rgb, dyed, fabric_strength);
}
"""
const SHADER := """
shader_type canvas_item;
uniform vec4 top : source_color = vec4(0.23, 0.36, 0.86, 1.0);
uniform vec4 bottom : source_color = vec4(0.11, 0.18, 0.56, 1.0);
uniform float pulse = 0.0;
uniform vec4 pulse_color : source_color = vec4(1.0);
uniform float aspect = 1.0;

void fragment() {
	vec3 c = mix(top.rgb, bottom.rgb, smoothstep(0.0, 1.0, UV.y));
	// soft diagonal bands of light drifting slowly
	float band = sin((UV.x * aspect + UV.y) * 7.0 - TIME * 0.35) * 0.5 + 0.5;
	c += vec3(1.0) * pow(band, 6.0) * 0.045;
	// glow at the top centre, brighter on a pulse
	float d = distance(vec2(UV.x * aspect, UV.y), vec2(0.5 * aspect, 0.18));
	c += mix(vec3(1.0), pulse_color.rgb, pulse) * exp(-d * d * 3.0) * (0.10 + pulse * 0.25);
	COLOR = vec4(c, 1.0);
}
"""
## classic skin: soft drifting pools of light added on top of the velvet
const POOLS_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform float aspect = 1.0;
uniform float pulse = 0.0;
uniform vec4 pulse_color : source_color = vec4(1.0);
uniform vec4 pool_a : source_color = vec4(0.18, 0.71, 0.66, 1.0);
uniform vec4 pool_b : source_color = vec4(0.48, 0.31, 0.84, 1.0);
uniform vec4 pool_c : source_color = vec4(0.82, 0.67, 0.33, 1.0);
uniform vec4 tint_top : source_color = vec4(0.0);
uniform vec4 tint_bottom : source_color = vec4(0.0);

vec3 pool(vec2 p, vec2 c, float r, vec3 col) {
	vec2 d = p - c;
	return col * exp(-dot(d, d) / (r * r));
}

void fragment() {
	float t = TIME;
	vec2 p = vec2(UV.x * aspect, UV.y);
	vec2 span = vec2(aspect, 1.0);
	vec3 c = vec3(0.0);
	c += pool(p, span * vec2(0.5 + 0.38 * sin(t * 0.031), 0.5 + 0.38 * cos(t * 0.023)), 0.55, pool_a.rgb);
	c += pool(p, span * vec2(0.5 + 0.38 * sin(t * 0.019 + 2.1), 0.5 + 0.38 * cos(t * 0.027 + 2.7)), 0.5, pool_b.rgb);
	c += pool(p, span * vec2(0.5 + 0.38 * sin(t * 0.026 + 4.2), 0.5 + 0.38 * cos(t * 0.018 + 5.4)), 0.38, pool_c.rgb);
	c = c * (0.10 + pulse * 0.10) + pulse_color.rgb * pulse * 0.10 * exp(-dot(UV - 0.5, UV - 0.5) * 3.0);
	c += mix(tint_top.rgb, tint_bottom.rgb, smoothstep(0.0, 1.0, UV.y)) * 0.07;
	COLOR = vec4(c, 1.0);
}
"""
const MOTES := 22

var _t := 0.0
var _pulse := 0.0
var _mat := ShaderMaterial.new()
var _pools: ColorRect  ## bright skin: gradient
var _velvet: TextureRect
var _vignette: TextureRect
var _classic_pools: ColorRect
var _classic_mat := ShaderMaterial.new()
var _palette_tween: Tween
var _velvet_tinted := false
var _fabric_mat := ShaderMaterial.new()
var skin := "classic"
var _layer: Control
var _motes: Array[Dictionary] = []
var _palette_sparks: Array[Dictionary] = []
var _palette_shake := 0.0
var _burst_rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst_rng.randomize()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_pools = ColorRect.new()
	_pools.material = _mat
	_pools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pools.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pools)
	_velvet = TextureRect.new()
	_velvet.texture = preload("res://assets/ui/velvet.png")
	_velvet.stretch_mode = TextureRect.STRETCH_TILE
	var fabric_shader := Shader.new()
	fabric_shader.code = VELVET_SHADER
	_fabric_mat.shader = fabric_shader
	_vignette = TextureRect.new()
	_vignette.texture = preload("res://assets/ui/vignette.png")
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var csh := Shader.new()
	csh.code = POOLS_SHADER
	_classic_mat.shader = csh
	_classic_pools = ColorRect.new()
	_classic_pools.material = _classic_mat
	for n in [_velvet, _vignette, _classic_pools]:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(n)
	set_skin(skin)
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.draw.connect(_draw_motes)
	add_child(_layer)
	resized.connect(func():
		_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
		_classic_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0)))
	for i in MOTES:
		_motes.append(_new_mote(true))


func _new_mote(anywhere: bool) -> Dictionary:
	return {
		"x": randf(), "y": randf() if anywhere else 1.05,
		"v": randf_range(0.008, 0.025), "s": randf_range(4.0, 11.0),
		"w": randf_range(0.5, 1.5), "a": randf_range(0.15, 0.45),
	}


## "classic": velvet with drifting light; "bright": colour gradient that fades between palettes.
func set_skin(name: String) -> void:
	skin = name
	var classic := name != "bright"
	_pools.visible = not classic
	for n in [_velvet, _vignette, _classic_pools]:
		n.visible = classic


## Fade the legacy gradient and optionally Bright Run's fabric, surface and lighting together.
func fade_palette(top: Color, bottom: Color, seconds := 0.8, velvet := false,
		surface_profile: Dictionary = {}, surface_changed: Callable = Callable()) -> void:
	if _palette_tween and _palette_tween.is_valid():
		_palette_tween.kill()
	var from_top: Color = _mat.get_shader_parameter("top") if _mat.get_shader_parameter("top") != null else top
	var from_bottom: Color = _mat.get_shader_parameter("bottom") if _mat.get_shader_parameter("bottom") != null else bottom
	var targets := {"pool_a":top.lightened(0.12), "pool_b":bottom.lightened(0.25),
		"pool_c":top.lerp(bottom,0.5).lightened(0.18), "tint_top":top, "tint_bottom":bottom}
	var fabric_from: Color = _fabric_mat.get_shader_parameter("fabric_color") if _fabric_mat.get_shader_parameter("fabric_color") != null else Color(0.05,0.13,0.14)
	var strength_from: float = _fabric_mat.get_shader_parameter("fabric_strength") if _fabric_mat.get_shader_parameter("fabric_strength") != null else 0.0
	if not surface_profile.is_empty():
		targets = surface_profile.lights
		_velvet.material = _fabric_mat
	var starts := {}
	if velvet:
		_velvet_tinted = true
		for key in targets:
			starts[key] = _classic_mat.get_shader_parameter(key)
			if starts[key] == null:
				starts[key] = {"pool_a":Color(0.18,0.71,0.66),"pool_b":Color(0.48,0.31,0.84),
					"pool_c":Color(0.82,0.67,0.33)}.get(key,Color(0,0,0,0))
	var apply := func(t: float):
		_mat.set_shader_parameter("top", from_top.lerp(top, t))
		_mat.set_shader_parameter("bottom", from_bottom.lerp(bottom, t))
		if velvet:
			for key in targets:
				_classic_mat.set_shader_parameter(key,(starts[key] as Color).lerp(targets[key],t))
		if not surface_profile.is_empty():
			_fabric_mat.set_shader_parameter("fabric_color",fabric_from.lerp(surface_profile.fabric,t))
			_fabric_mat.set_shader_parameter("fabric_strength",lerpf(strength_from,surface_profile.strength,t))
			if surface_changed.is_valid():
				surface_changed.call(t)
	if seconds <= 0.0:
		apply.call(1.0)
	else:
		_palette_tween = create_tween()
		var step := _palette_tween.tween_method(apply,0.0,1.0,seconds)
		if velvet:
			step.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Restore the original Classic/menu light colours without touching textures or cosmetics.
func reset_velvet_palette() -> void:
	_palette_sparks.clear()
	_palette_shake = 0.0
	_fabric_mat.set_shader_parameter("fabric_shift",Vector2.ZERO)
	_layer.queue_redraw()
	if not _velvet_tinted:
		return
	if _palette_tween and _palette_tween.is_valid():
		_palette_tween.kill()
	for key in ["pool_a","pool_b","pool_c","tint_top","tint_bottom"]:
		_classic_mat.set_shader_parameter(key,null)
	_velvet.material = null
	_fabric_mat.set_shader_parameter("fabric_color",null)
	_fabric_mat.set_shader_parameter("fabric_strength",null)
	_velvet_tinted = false


func pulse(color: Color, strength := 1.0) -> void:
	_pulse = maxf(_pulse, strength)
	_mat.set_shader_parameter("pulse_color", color)
	_classic_mat.set_shader_parameter("pulse_color", color)


## A bounded background celebration: reuse the existing sparkle texture, behind the gems/HUD.
func palette_burst(color: Color) -> void:
	_palette_sparks.clear()  # Repeated events replace the burst rather than stacking particles.
	_palette_shake = 0.16
	for i in 36:
		var p := Vector2(_burst_rng.randf_range(0.04,0.96),_burst_rng.randf_range(0.16,0.96))
		_palette_sparks.append({"p":p,"v":(p-Vector2(0.5,0.55)).normalized()*_burst_rng.randf_range(0.035,0.08),
			"t":0.0,"life":_burst_rng.randf_range(0.55,0.85),"s":_burst_rng.randf_range(16.0,28.0),"c":color})
	_layer.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _palette_shake > 0.0:
		_palette_shake = maxf(0.0,_palette_shake-delta)
		var amplitude := 2.0*_palette_shake/0.16
		var shift := Vector2(sin(_palette_shake*180.0),cos(_palette_shake*145.0))*amplitude
		_fabric_mat.set_shader_parameter("fabric_shift",shift)
	if not _palette_sparks.is_empty():
		for sp in _palette_sparks:
			sp.t += delta
			sp.p += sp.v*delta
		_palette_sparks = _palette_sparks.filter(func(sp): return sp.t < sp.life)
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 1.2)
		_mat.set_shader_parameter("pulse", _pulse)
		_classic_mat.set_shader_parameter("pulse", _pulse)
	for m in _motes:
		m.y -= m.v * delta
		if m.y < -0.05:
			m.merge(_new_mote(false), true)
	_layer.queue_redraw()


func _draw_motes() -> void:
	var s := size
	for sp in _palette_sparks:
		var age: float = sp.t/sp.life
		var alpha := sin(age*PI)*0.75
		var sz: float = sp.s*clampf(minf(s.x,s.y)/480.0,0.75,1.5)*lerpf(0.7,1.3,age)
		_layer.draw_texture_rect(SPARKLE_TEX,Rect2(sp.p*s-Vector2.ONE*sz/2,Vector2.ONE*sz),false,Color(sp.c,alpha))
	for m in _motes:
		var x: float = (m.x + 0.02 * sin(_t * m.w + m.y * 9.0)) * s.x
		var sz: float = m.s * (1.0 + _pulse * 0.5)
		var tw: float = 0.6 + 0.4 * sin(_t * 3.0 * m.w + m.x * 20.0)
		_layer.draw_texture_rect(SPARKLE_TEX, Rect2(Vector2(x, m.y * s.y) - Vector2.ONE * sz / 2, Vector2.ONE * sz), false, Color(1, 0.93, 0.78, m.a * tw))
