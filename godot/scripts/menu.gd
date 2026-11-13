extends CanvasLayer
## Menus: launch screen (place, aircraft, assist, quality, leaderboard),
## loading overlay, pause overlay and the post-flight summary. Built in code.

var main: Node
var _root: Control
var _menu: Control
var _loading: Control
var _loading_bar: ProgressBar
var _loading_label: Label
var _pause: Control
var _summary: Control
var _summary_label: RichTextLabel
var _status: Label
var _search: LineEdit
var _results: ItemList
var _place_label: Label
var _vehicle_buttons: Dictionary = {}
var _assist: OptionButton
var _quality: OptionButton
var _radio_check: CheckBox
var _rings_check: CheckBox
var _name: LineEdit
var _board: RichTextLabel
var _results_data: Array = []
var _panels: Array = []
var _panel_widths: Array = []
var _geo_cb: JavaScriptObject

const PANEL := Color(0.03, 0.07, 0.06, 0.86)
const ACCENT := Color(0.55, 0.95, 0.72)
const TEXT := Color(0.92, 0.97, 0.94)
const DIM := Color(0.7, 0.8, 0.75)


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_menu()
	_build_loading()
	_build_pause()
	_build_summary()
	show_menu()


func _panel(parent: Control, w: float = 0.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.border_width_bottom = 1
	sb.border_width_top = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_color = Color(ACCENT, 0.25)
	p.add_theme_stylebox_override("panel", sb)
	if w > 0.0:
		p.custom_minimum_size.x = w
	parent.add_child(p)
	return p


func _label(parent: Control, text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	if big:
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(240, 54)
	parent.add_child(b)
	return b


# ------------------------------------------------------------- launch menu

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.05, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu.add_child(scroll)
	var outer := MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("margin_left", 28)
	outer.add_theme_constant_override("margin_right", 28)
	outer.add_theme_constant_override("margin_top", 20)
	outer.add_theme_constant_override("margin_bottom", 20)
	scroll.add_child(outer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	outer.add_child(col)

	var title := _label(col, "OPEN SKIES", 40, ACCENT)
	title.add_theme_constant_override("outline_size", 0)
	_label(col, "Fly the real world. Google Photorealistic 3D Tiles, a proper flight model, and Nightride FM.", 15, DIM)

	# Panels wrap onto new lines on narrow (phone) screens.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	# --- Where
	var where := _panel(row, 360)
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(where)
	_panel_widths.append(360.0)
	var wv := VBoxContainer.new()
	where.add_child(wv)
	_label(wv, "WHERE", 13, ACCENT)
	_place_label = _label(wv, "San Francisco", 20)
	var srow := HBoxContainer.new()
	wv.add_child(srow)
	_search = LineEdit.new()
	_search.placeholder_text = "Search any place…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t): _do_search())
	srow.add_child(_search)
	_button(srow, "Search", _do_search)
	_results = ItemList.new()
	_results.custom_minimum_size = Vector2(0, 0)
	_results.visible = false
	_results.item_selected.connect(_on_result_selected)
	wv.add_child(_results)
	var grid := GridContainer.new()
	grid.columns = 3
	wv.add_child(grid)
	for p in main.PRESETS:
		_button(grid, p.name, func(): _set_place(p))
	if OS.has_feature("web"):
		_button(wv, "Use my location", _use_my_location)

	# --- What
	var what := _panel(row, 330)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(what)
	_panel_widths.append(330.0)
	var av := VBoxContainer.new()
	what.add_child(av)
	_label(av, "AIRCRAFT", 13, ACCENT)
	for id in Vehicles.ORDER:
		var spec := Vehicles.get_spec(id)
		var b := Button.new()
		b.text = "%s\n%s" % [spec.name, spec.blurb]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(func(): _set_vehicle(id))
		av.add_child(b)
		_vehicle_buttons[id] = b
	_set_vehicle("typhoon")
	_label(av, "ASSIST", 13, ACCENT)
	_assist = OptionButton.new()
	for n in Aircraft.ASSIST_NAMES:
		_assist.add_item(n)
	_assist.selected = 0
	av.add_child(_assist)
	_label(av, "Arcade: point and go — auto-level, auto-throttle with boost, no stalls. Pro: fly-by-wire with real limits. Sim: raw surfaces.", 12, DIM)
	_label(av, "GRAPHICS", 13, ACCENT)
	_quality = OptionButton.new()
	for q in main.QUALITY.keys():
		_quality.add_item(q)
	_quality.selected = 1
	av.add_child(_quality)
	_rings_check = CheckBox.new()
	_rings_check.text = "Ring run (score & combos)"
	_rings_check.button_pressed = true
	av.add_child(_rings_check)
	_radio_check = CheckBox.new()
	_radio_check.text = "Nightride FM on takeoff"
	_radio_check.button_pressed = true
	av.add_child(_radio_check)
	var nrow := HBoxContainer.new()
	av.add_child(nrow)
	var pl := _label(nrow, "Pilot name", 13, DIM)
	pl.autowrap_mode = TextServer.AUTOWRAP_OFF
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name = LineEdit.new()
	_name.placeholder_text = "PILOT"
	_name.max_length = 10
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(_name)

	# --- Leaderboard
	var lb := _panel(row, 280)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(lb)
	_panel_widths.append(280.0)
	var lv := VBoxContainer.new()
	lb.add_child(lv)
	_label(lv, "LEADERBOARD · distance flown", 13, ACCENT)
	_board = RichTextLabel.new()
	_board.bbcode_enabled = true
	_board.fit_content = true
	_board.custom_minimum_size = Vector2(0, 200)
	_board.add_theme_font_size_override("normal_font_size", 13)
	lv.add_child(_board)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	var take := _button(bottom, "TAKE OFF", _on_take_off, true)
	take.add_theme_color_override("font_color", Color(0.02, 0.08, 0.05))
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = ACCENT
	tsb.corner_radius_top_left = 8
	tsb.corner_radius_top_right = 8
	tsb.corner_radius_bottom_left = 8
	tsb.corner_radius_bottom_right = 8
	take.add_theme_stylebox_override("normal", tsb)
	var hsb := tsb.duplicate()
	hsb.bg_color = ACCENT.lightened(0.15)
	take.add_theme_stylebox_override("hover", hsb)
	take.add_theme_stylebox_override("pressed", hsb)
	_status = _label(bottom, "", 13, DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(col, "W/S pitch · A/D roll · Q/E rudder · Shift/Ctrl throttle · Space brake · L level · R loop · T barrel roll · C camera · B assist · H hide HUD · M radio · drag the mouse to look around · Esc menu", 12, DIM)
	_label(col, "Classic (CesiumJS) version: /classic", 11, Color(DIM, 0.6))


## Keep the panels narrower than the (scaled) screen so phones get a single
## column that wraps instead of overflowing.
func relayout() -> void:
	var avail: float = get_viewport().get_visible_rect().size.x / get_tree().root.content_scale_factor
	for i in range(_panels.size()):
		var pnl: PanelContainer = _panels[i]
		pnl.custom_minimum_size.x = min(float(_panel_widths[i]), avail - 60.0)


func _set_place(p: Dictionary) -> void:
	main.place = {"name": p.name, "lat": float(p.lat), "lon": float(p.lon)}
	_place_label.text = p.name


func _set_vehicle(id: String) -> void:
	main.vehicle_id = id
	for k in _vehicle_buttons:
		_vehicle_buttons[k].button_pressed = (k == id)


func _do_search() -> void:
	var q := _search.text.strip_edges()
	if q == "":
		return
	set_status("Searching…")
	var res: Array = await Api.search(q)
	_results_data = res
	_results.clear()
	for r in res:
		_results.add_item(str(r.name))
	_results.visible = res.size() > 0
	_results.custom_minimum_size = Vector2(0, min(res.size(), 5) * 26.0 + 8.0)
	set_status("" if res.size() > 0 else "No results for “%s”." % q)
	if res.size() == 1:
		_on_result_selected(0)


func _on_result_selected(i: int) -> void:
	if i < 0 or i >= _results_data.size():
		return
	var r = _results_data[i]
	_set_place({"name": _short_name(str(r.name)), "lat": r.lat, "lon": r.lon})


func _short_name(n: String) -> String:
	return n.split(",")[0] if n.length() > 32 else n


func _use_my_location() -> void:
	set_status("Requesting your location…")
	_geo_cb = JavaScriptBridge.create_callback(_on_geo)
	JavaScriptBridge.get_interface("window").openskies_geo = _geo_cb
	JavaScriptBridge.eval("""
		navigator.geolocation.getCurrentPosition(
			function(p){ window.openskies_geo(p.coords.latitude, p.coords.longitude); },
			function(e){ window.openskies_geo(NaN, NaN); },
			{enableHighAccuracy:false, timeout:9000, maximumAge:300000});
	""", true)


func _on_geo(args: Array) -> void:
	if args.size() < 2 or is_nan(float(args[0])):
		set_status("Location unavailable — pick a place instead.", true)
		return
	_set_place({"name": "Your location", "lat": float(args[0]), "lon": float(args[1])})
	set_status("")


func _on_take_off() -> void:
	main.quality = _quality.get_item_text(_quality.selected)
	var q: String = main._url_param("quality")
	if q != "" and main.QUALITY.has(q):
		main.quality = q
	main.radio_wanted = _radio_check.button_pressed
	main.rings_wanted = _rings_check.button_pressed
	main.start_flight()
	main.aircraft.assist = _assist.selected as Aircraft.Assist


func set_mobile_defaults() -> void:
	_quality.selected = 0
	_assist.selected = 0


func pilot_name() -> String:
	return _name.text.strip_edges() if _name.text.strip_edges() != "" else "PILOT"


func set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if is_error else DIM)


func refresh_scores() -> void:
	var scores: Array = await Api.top_scores()
	_fill_board(scores)


func _fill_board(scores: Array) -> void:
	if scores.is_empty():
		_board.text = "[color=#aabbb0]No flights yet — be the first.[/color]"
		return
	var t := ""
	var i := 1
	for s in scores.slice(0, 10):
		var col: String = {1: "#ffd76a", 2: "#d9dde0", 3: "#e0a46a"}.get(i, "#eef5f0")
		t += "[color=%s]%2d.  %s[/color]   %.1f km   [color=#aabbb0]%s[/color]\n" % [col, i, str(s.get("name", "PILOT")), float(s.get("distanceKm", 0)), str(s.get("vehicle", ""))]
		i += 1
	_board.text = t


func show_menu() -> void:
	_menu.visible = true


func hide_menu() -> void:
	_menu.visible = false


# ---------------------------------------------------------------- overlays

func _build_loading() -> void:
	_loading = CenterContainer.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	_root.add_child(_loading)
	var p := _panel(_loading, 420)
	var v := VBoxContainer.new()
	p.add_child(v)
	_loading_label = _label(v, "Streaming the world…", 16)
	_loading_bar = ProgressBar.new()
	_loading_bar.max_value = 1.0
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(380, 14)
	v.add_child(_loading_bar)
	_label(v, "Tiles are streamed from Google as you fly; the first seconds over a new city are the heaviest.", 12, DIM)


func show_loading(on: bool) -> void:
	_loading.visible = on


func set_loading(progress: float, text: String) -> void:
	_loading_bar.value = progress
	_loading_label.text = text


func _build_pause() -> void:
	_pause = CenterContainer.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)
	var p := _panel(_pause, 320)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	_label(v, "PAUSED", 22, ACCENT)
	_button(v, "Resume (Esc)", func(): main.resume())
	_button(v, "Finish flight & post score", func(): main.finish_flight())
	_button(v, "Toggle radio (M)", func(): main.radio.toggle())
	_button(v, "Back to menu", func(): main.back_to_menu())


func show_pause(on: bool) -> void:
	_pause.visible = on


func _build_summary() -> void:
	_summary = CenterContainer.new()
	_summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summary.visible = false
	_root.add_child(_summary)
	var p := _panel(_summary, 420)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	_label(v, "FLIGHT COMPLETE", 22, ACCENT)
	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.custom_minimum_size = Vector2(380, 120)
	v.add_child(_summary_label)
	_button(v, "Back to menu", func():
		_summary.visible = false
		main.back_to_menu()
		refresh_scores())


func show_summary(result: Dictionary, board) -> void:
	_summary.visible = true
	var t := "[b]%s[/b]\nScore: %d  (%d rings, best combo x%d)\nDistance: %.1f km\nTime: %d:%02d\nTop speed: %d km/h · Max %.1f G\n" % [
		result.place, int(result.get("score", 0)), int(result.get("rings", 0)), int(result.get("best_combo", 0)), result.distance / 1000.0, int(result.time) / 60, int(result.time) % 60, int(result.top_speed * 3.6), result.max_g]
	if board == null:
		t += "[color=#aabbb0]Posting score…[/color]"
	elif board is Array and board.size() > 0:
		t += "[color=#aabbb0]Posted to the leaderboard.[/color]"
	else:
		t += "[color=#aabbb0]Leaderboard unavailable.[/color]"
	_summary_label.text = t
