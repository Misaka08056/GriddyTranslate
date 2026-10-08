# Info:
# "Caret" refers to the "cursor" of where text is being inserted/deleted in the CodeEdit node.
# "11" refers to the number of characters able to fit on the screen without zooming out.
class_name Camera
extends Camera2D

@export var transition_speed: float = 1.0
@onready var code = %Code

var max_zoom = Vector2(10.0, 10.0);
var min_zoom = Vector2(1.0, 1.0);

# Ignore mouse movement? \/
var busy = false;
var boundaries_exceeded = null;

var shake_strength: float = 15.0;

var d := 0.0;
var radius := 4.0
var speed := 2.0
var motion_enabled := true
var user_zoom := 1.0
var focus_tween: Tween
var pulse_tween: Tween
var pulse := 0.0
var returning_from_panel := false

func _ready() -> void:
	limit_right = code.size.x


func get_font_metrics() -> Vector2:
	var font: Font = code.get_theme_font("font")
	var font_size: int = code.get_theme_font_size("font_size")
	# NOTE: imo this is a good approximation of the average character size for a non
	# monospaced font.
	return font.get_char_size(0x30, font_size)


const SCALE = 7.0;


func _process(delta: float) -> void:
	d += delta;

	offset = Vector2(
		sin(d * speed) * radius,
		cos(d * speed) * radius
	) if motion_enabled else Vector2.ZERO

	if busy or returning_from_panel: return;

	var final_zoom := Vector2.ONE * (content_base_zoom() * user_zoom + pulse)
	var char_size: Vector2 = get_font_metrics();
	var gp = code.get_caret_draw_pos();

	gp.x -= 2*char_size.x;

	# One continuous focus response avoids hundreds of overlapping camera tweens.
	var response := 1.0 - exp(-delta * 6.0)
	zoom = zoom.lerp(final_zoom, response)
	global_position = global_position.lerp(gp, response)

func content_base_zoom() -> float:
	return clampf(max_zoom.x - (code.get_longest_line().length() + 1) / SCALE, min_zoom.x, max_zoom.x)

func set_motion_enabled(value: bool) -> void:
	motion_enabled = value
	if not value:
		offset = Vector2.ZERO
		pulse = 0.0
		if pulse_tween != null: pulse_tween.kill()

func focus_on(pos: Vector2, _zoom: Vector2) -> void:
	busy = true;
	returning_from_panel = false
	if focus_tween != null: focus_tween.kill()
	focus_tween = create_tween()

	focus_tween.parallel().tween_property(self, "global_position", pos, transition_speed)
	focus_tween.parallel().tween_property(self, "zoom", _zoom, transition_speed)

func focus_die() -> void:
	var was_busy: bool = busy
	busy = false
	if focus_tween != null: focus_tween.kill()
	returning_from_panel = false
	if was_busy:
		returning_from_panel = true
		var target_position: Vector2 = code.get_caret_draw_pos()
		target_position.x -= 2 * get_font_metrics().x
		focus_tween = create_tween()
		focus_tween.parallel().tween_property(self, "global_position", target_position, transition_speed)
		focus_tween.parallel().tween_property(self, "zoom", Vector2.ONE * content_base_zoom() * user_zoom, transition_speed)
		focus_tween.tween_callback(func(): returning_from_panel = false)

func focus_temp(intensity: float) -> void:
	if busy or returning_from_panel or not motion_enabled: return
	if pulse_tween != null: pulse_tween.kill()
	pulse = intensity
	pulse_tween = create_tween()
	pulse_tween.tween_property(self, "pulse", 0.0, 0.5)

func shake_camera(_shake_strength):
	return Vector2(randf_range(-_shake_strength, _shake_strength), randf_range(-_shake_strength, _shake_strength))

func to_zoom(num: float) -> Vector2:
	if num > 40:
		num += 120;

	num /= 100 # 44 -> 0.44

	num = 4 - num;

	return Vector2(num, num)
