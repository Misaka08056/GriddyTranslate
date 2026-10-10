extends VBoxContainer

const SETTING = preload("res://Scenes/setting.tscn")
var sliders_interactive := true
var dragging_sliders: Array[HSlider] = []
var stable_controls: Dictionary = {}
var resting_poses: Dictionary = {}
var return_tweens: Dictionary = {}
var _settings_dirty := true


# Called when the node enters the scene tree for the first time.
func _ready():
	process_priority = 100
	RenderingServer.frame_pre_draw.connect(_stabilize_dragged_controls)
	await LuaSingleton.on_theme_load;

	setup_settings()
	LuaSingleton.on_theme_load.connect(_refresh_theme_colors)
	visibility_changed.connect(_visibility_refresh)
	LuaSingleton.on_settings_change.connect(setup_settings);

func setup_settings() -> void:
	if not is_visible_in_tree():
		_settings_dirty = true
		return
	_settings_dirty = false
	release_slider_interactions()
	for child in get_children():
		child.queue_free()

	for setting in LuaSingleton.settings:
		var unit = setting.unit if setting.has("unit") else "";
		var _min = setting.min if setting.has("min") else 0;
		var _max = setting.max if setting.has("max") else 0;
		var precision = setting.precision if setting.has("precision") else false;

		create_setting(setting.display, setting.icon, setting.value, setting.options, setting.property, unit, _min, _max, precision, setting.get("action", false))

func _visibility_refresh() -> void:
	if not is_visible_in_tree(): return
	if _settings_dirty: setup_settings()
	else: _refresh_theme_colors()



func create_setting(text: String, icon: String, value: Variant, options: Array, property: String, unit: String, _min: float, _max: float, precision: bool, action: bool = false) -> void:
	var node = SETTING.instantiate()
	node.set_meta("setting_style", {"display": text, "icon": icon, "unit": unit, "icon_color": LuaSingleton.keywords.keys().pick_random()})

	add_child(node)

	var slider: HSlider = node.get_node("Control2/HSlider")
	slider.set_meta("setting_property", property)
	slider.mouse_filter = Control.MOUSE_FILTER_STOP if sliders_interactive else Control.MOUSE_FILTER_IGNORE
	var checkbutton: CheckButton = node.get_node("Control2/CheckButton");
	var value_label: RichTextLabel = node.get_node("Control4/Value");
	var dropdown: OptionButton = node.get_node("Control5/OptionButton");

	if !precision:
		slider.step = 1

	slider.max_value = _max
	slider.min_value = _min

	checkbutton.hide()
	slider.hide()
	dropdown.hide()
	value_label.hide()

	if action:
		var button := Button.new()
		button.name = "SettingAction"
		button.position = Vector2(351, 0)
		button.size = Vector2(240, 24)
		button.text = str(value)
		button.tooltip_text = str(value)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.theme = LuaSingleton.editor_theme
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_color_override("font_color", LuaSingleton.gui.font_color)
		node.get_node("Control5").add_child(button)
		button.pressed.connect(_action_pressed.bind(property))
	elif typeof(value) == Variant.Type.TYPE_BOOL:
		checkbutton.show()

		checkbutton.button_pressed = value;
	elif options.size() != 0:
		dropdown.show()

		for option in options:
			dropdown.add_item(option.display)

		dropdown.selected = value;
	else:
		value_label.show()

		set_label(value_label, unit, value)

		slider.show()
		slider.value = value

	slider.value_changed.connect(_slider_value_change.bind(property, value_label, unit))
	slider.gui_input.connect(_slider_input.bind(slider))
	slider.drag_started.connect(_begin_slider_interaction.bind(slider))
	slider.drag_ended.connect(_end_slider_drag.bind(slider))
	slider.tree_exiting.connect(_end_slider_interaction.bind(slider, false))
	checkbutton.toggled.connect(_check_button_change.bind(property))
	dropdown.item_selected.connect(_dropdown_change.bind(property))
	_style_setting(node)

func _refresh_theme_colors() -> void:
	# A theme changes the palette, not the controls or their option catalogs.
	if not is_visible_in_tree(): return
	for row in get_children():
		if not row.is_queued_for_deletion(): _style_setting(row)

func _style_setting(row: Control) -> void:
	var style: Dictionary = row.get_meta("setting_style")
	var label: RichTextLabel = row.get_node("Control/RichTextLabel")
	label.add_theme_color_override("default_color", LuaSingleton.gui.font_color)
	label.clear()
	label.push_color(LuaSingleton.keywords[style.icon_color])
	label.push_font(LuaSingleton.SYMBOLS_NERD_FONT)
	label.add_text(style.icon)
	label.pop()
	label.pop()
	label.add_text("  %s" % style.display)
	var value_label: RichTextLabel = row.get_node("Control4/Value")
	value_label.add_theme_color_override("default_color", LuaSingleton.gui.font_color)
	if value_label.visible:
		set_label(value_label, style.unit, row.get_node("Control2/HSlider").value)
	var action := row.get_node_or_null("Control5/SettingAction")
	if action != null: action.add_theme_color_override("font_color", LuaSingleton.gui.font_color)

func _action_pressed(property: String) -> void:
	var controller = get_node("/root/Editor").wordbook
	match property:
		"obsidian_vault": controller.choose_vault()
		"obsidian_folder": controller.choose_folder()
		"obsidian_sync_now": controller.sync_now()

func set_sliders_interactive(enabled: bool) -> void:
	sliders_interactive = enabled
	for row in get_children():
		row.get_node("Control2/HSlider").mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

func _slider_input(event: InputEvent, slider: HSlider) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _begin_slider_interaction(slider)
		else: _end_slider_interaction(slider)

func _begin_slider_interaction(slider: HSlider) -> void:
	if not sliders_interactive or dragging_sliders.has(slider): return
	dragging_sliders.append(slider)
	var value_label: Control = slider.get_parent().get_parent().get_node("Control4/Value")
	var snapshots: Array = []
	for control: Control in [slider, value_label]:
		if return_tweens.has(control):
			return_tweens[control].kill()
			return_tweens.erase(control)
		if not resting_poses.has(control):
			resting_poses[control] = {"position": control.position, "scale": control.scale, "rotation": control.rotation, "z_index": control.z_index}
		snapshots.append({"control": control, "screen": control.get_global_transform_with_canvas()})
		control.z_index = 20
	stable_controls[slider] = snapshots

func _end_slider_drag(_value_changed: bool, slider: HSlider) -> void:
	_end_slider_interaction(slider)

func _end_slider_interaction(slider: HSlider, animate: bool = true) -> void:
	if not stable_controls.has(slider): return
	dragging_sliders.erase(slider)
	for snapshot in stable_controls[slider]:
		var control: Control = snapshot.control
		if not is_instance_valid(control): continue
		var pose: Dictionary = resting_poses[control]
		control.z_index = pose.z_index
		if animate and control.is_visible_in_tree() and not control.is_queued_for_deletion():
			var tween := create_tween().set_parallel(true)
			tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_property(control, "position", pose.position, 0.12)
			tween.tween_property(control, "scale", pose.scale, 0.12)
			tween.tween_property(control, "rotation", pose.rotation, 0.12)
			return_tweens[control] = tween
			tween.chain().tween_callback(_finish_slider_return.bind(control))
		else:
			control.position = pose.position
			control.scale = pose.scale
			control.rotation = pose.rotation
			resting_poses.erase(control)
	stable_controls.erase(slider)

func _finish_slider_return(control: Control) -> void:
	return_tweens.erase(control)
	resting_poses.erase(control)

func _process(_delta: float) -> void:
	_stabilize_dragged_controls()

func _stabilize_dragged_controls() -> void:
	if stable_controls.is_empty() or not is_inside_tree(): return
	# Use the final camera transform, including this frame's focus tween.
	%Cam.force_update_scroll()
	for snapshots in stable_controls.values():
		for snapshot in snapshots:
			var control: Control = snapshot.control
			if not is_instance_valid(control): continue
			var world: Transform2D = control.get_canvas_transform().affine_inverse() * snapshot.screen
			var local: Transform2D = control.get_parent().get_global_transform().affine_inverse() * world
			control.position = local.origin
			control.rotation = local.get_rotation()
			control.scale = local.get_scale()

func release_slider_interactions() -> void:
	for slider in dragging_sliders.duplicate():
		_end_slider_interaction(slider, false)
	for control in return_tweens.keys():
		return_tweens[control].kill()
		if is_instance_valid(control) and resting_poses.has(control):
			var pose: Dictionary = resting_poses[control]
			control.position = pose.position
			control.scale = pose.scale
			control.rotation = pose.rotation
			control.z_index = pose.z_index
	return_tweens.clear()
	resting_poses.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_slider_interactions()

func set_label(value_label: RichTextLabel, unit: String, value: float) -> void:
	value_label.clear()

	value_label.add_text(str(value) + " ")

	value_label.push_color(LuaSingleton.gui.selection_color)
	value_label.add_text(unit)
	value_label.pop()

func _slider_value_change(value: float, property: String, value_label: RichTextLabel, unit: String) -> void:
	LuaSingleton.change_setting(property, value)

	set_label(value_label, unit, value)

func _check_button_change(toggled_on: bool, property: String) -> void:
	LuaSingleton.change_setting(property, toggled_on)

func _dropdown_change(index: int, property: String):
	LuaSingleton.change_setting(property, index)
