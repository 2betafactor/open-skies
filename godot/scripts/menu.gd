extends CanvasLayer
## One-screen arcade menu: pick a city, pick a plane, PLAY. Plus pause and
## the time-up summary with score posting.

var main: Node
var _root: Control
var _menu: Control
var _loading: Control
var _loading_bar: ProgressBar
var _loading_label: Label
var _pause: Control
var _summary: Control
var _summary_label: RichTextLabel
var _summary_name: LineEdit
var _post_button: Button
var _status: Label
var _search: LineEdit
var _results: ItemList
var _place_label: Label
var _city_buttons: Dictionary = {}
var _plane_buttons: Dictionary = {}
var _board: RichTextLabel
var _results_data: Array = []
var _geo_cb: JavaScriptObject
var _panels: Array = []
var _play_button: Button
var _again_button: Button
var _city_grid: GridContainer
var _panel_widths: Array = []

const PANEL := Color(0.02, 0.04, 0.08, 0.78)
const ACCENT := Color(1.0, 0.8, 0.25)
const ACCENT2 := Color(0.45, 0.85, 1.0)
const TEXT := Color(0.97, 0.97, 0.97)
const DIM := Color(0.75, 0.8, 0.85)


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


func _style(col: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if border.a > 0.0:
		sb.border_width_bottom = 2
		sb.border_width_top = 2
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_color = border
	return sb


func _panel(parent: Control, w: float = 0.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(PANEL, 14, Color(1, 1, 1, 0.08)))
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
	b.add_theme_font_size_override("font_size", 24 if big else 15)
	if big:
		b.custom_minimum_size = Vector2(260, 60)
	parent.add_child(b)
	return b


func _choice_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.06), 10))
	b.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, 0.12), 10))
	b.add_theme_stylebox_override("pressed", _style(Color(ACCENT, 0.18), 10, ACCENT))
	b.add_theme_stylebox_override("hover_pressed", _style(Color(ACCENT, 0.22), 10, ACCENT))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), 10))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.1, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu.add_child(scroll)
	var outer := MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("margin_left", 24)
	outer.add_theme_constant_override("margin_right", 24)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(outer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	outer.add_child(col)

	var title := _label(col, "OPEN SKIES", 46, ACCENT)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_label(col, "Dogfight over the real world. Shoot down waves of alien ships, chain kills for combos, loop and roll for bonus points.", 15, DIM)

	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var where := _panel(row, 340)
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(where)
	_panel_widths.append(340.0)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 6)
	where.add_child(wv)
	_label(wv, "CITY", 12, ACCENT2)
	_place_label = _label(wv, "San Francisco", 22)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	wv.add_child(grid)
	_city_grid = grid
	for p in main.PRESETS:
		var b := _choice_button(grid, p.name, func(): _set_place(p))
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_city_buttons[p.name] = b
	_city_buttons["San Francisco"].button_pressed = true
	var srow := HBoxContainer.new()
	wv.add_child(srow)
	_search = LineEdit.new()
	_search.placeholder_text = "…or search any place"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t): _do_search())
	srow.add_child(_search)
	_button(srow, "Go", _do_search)
	_results = ItemList.new()
	_results.visible = false
	_results.item_selected.connect(_on_result_selected)
	wv.add_child(_results)
	if OS.has_feature("web"):
		_button(wv, "Use my location", _use_my_location)

	var what := _panel(row, 320)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(what)
	_panel_widths.append(320.0)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 6)
	what.add_child(av)
	_label(av, "PLANE", 12, ACCENT2)
	for id in Vehicles.ORDER:
		var spec := Vehicles.get_spec(id)
		var b := _choice_button(av, "%s\n%s" % [spec.name, spec.blurb], func(): _set_vehicle(id))
		_plane_buttons[id] = b
	_set_vehicle("typhoon")

	var lb := _panel(row, 250)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(lb)
	_panel_widths.append(250.0)
	var lv := VBoxContainer.new()
	lb.add_child(lv)
	_label(lv, "TOP SCORES", 12, ACCENT2)
	_board = RichTextLabel.new()
	_board.bbcode_enabled = true
	_board.fit_content = true
	_board.custom_minimum_size = Vector2(0, 160)
	_board.add_theme_font_size_override("normal_font_size", 14)
	lv.add_child(_board)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	var play := _button(bottom, "PLAY", _on_play, true)
	_play_button = play
	play.add_theme_color_override("font_color", Color(0.1, 0.07, 0.0))
	play.add_theme_color_override("font_hover_color", Color(0.1, 0.07, 0.0))
	play.add_theme_color_override("font_pressed_color", Color(0.1, 0.07, 0.0))
	play.add_theme_stylebox_override("normal", _style(ACCENT, 14))
	play.add_theme_stylebox_override("hover", _style(ACCENT.lightened(0.15), 14))
	play.add_theme_stylebox_override("pressed", _style(ACCENT.darkened(0.1), 14))
	play.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), 14))
	_status = _label(bottom, "", 13, DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A PLAY button pinned to the screen corner: the menu scrolls on phones
	# and the in-flow button can sit below the fold.
	var pinned := Button.new()
	pinned.text = "PLAY"
	pinned.add_theme_font_size_override("font_size", 22)
	pinned.custom_minimum_size = Vector2(150, 54)
	pinned.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pinned.offset_left = -170.0
	pinned.offset_top = -72.0
	pinned.offset_right = -20.0
	pinned.offset_bottom = -18.0
	pinned.add_theme_color_override("font_color", Color(0.1, 0.07, 0.0))
	pinned.add_theme_color_override("font_hover_color", Color(0.1, 0.07, 0.0))
	pinned.add_theme_color_override("font_pressed_color", Color(0.1, 0.07, 0.0))
	pinned.add_theme_stylebox_override("normal", _style(ACCENT, 14))
	pinned.add_theme_stylebox_override("hover", _style(ACCENT.lightened(0.15), 14))
	pinned.add_theme_stylebox_override("pressed", _style(ACCENT.darkened(0.1), 14))
	pinned.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), 14))
	pinned.pressed.connect(_on_play)
	_menu.add_child(pinned)
	_play_button = pinned
	_label(col, "Arrows / WASD steer · Space or click fires · E rocket · Tab target · Shift boost · R loop · T barrel roll · Esc pause", 12, DIM)


func relayout() -> void:
	var avail: float = get_viewport().get_visible_rect().size.x / get_tree().root.content_scale_factor
	for i in range(_panels.size()):
		var pnl: PanelContainer = _panels[i]
		pnl.custom_minimum_size.x = min(float(_panel_widths[i]), avail - 52.0)
	if _city_grid != null:
		_city_grid.columns = 1 if avail < 560.0 else 2


func _set_place(p: Dictionary) -> void:
	main.place = {"name": p.name, "lat": float(p.lat), "lon": float(p.lon)}
	_place_label.text = p.name
	for k in _city_buttons:
		_city_buttons[k].button_pressed = (k == p.name)


func _set_vehicle(id: String) -> void:
	main.vehicle_id = id
	for k in _plane_buttons:
		_plane_buttons[k].button_pressed = (k == id)


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
	var n := str(r.name)
	_set_place({"name": n.split(",")[0] if n.length() > 28 else n, "lat": r.lat, "lon": r.lon})


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
		set_status("Location unavailable — pick a city instead.", true)
		return
	_set_place({"name": "Your location", "lat": float(args[0]), "lon": float(args[1])})
	set_status("")


func _on_play() -> void:
	main.start_flight()


func set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if is_error else DIM)


func refresh_scores() -> void:
	var scores: Array = await Api.top_scores()
	_fill_board(scores)


func _fill_board(scores: Array) -> void:
	if scores.is_empty():
		_board.text = "[color=#aab]No scores yet — be the first.[/color]"
		return
	var t := ""
	var i := 1
	for s in scores.slice(0, 8):
		var col: String = {1: "#ffd76a", 2: "#d9dde0", 3: "#e0a46a"}.get(i, "#eef5f0")
		var sc: int = int(s.get("score", 0))
		var val: String = ("%d" % sc) if sc > 0 else ("%.1f km" % float(s.get("distanceKm", 0)))
		t += "[color=%s]%d.  %s[/color]   %s\n" % [col, i, str(s.get("name", "PILOT")), val]
		i += 1
	_board.text = t


func show_menu() -> void:
	_menu.visible = true


func hide_menu() -> void:
	_menu.visible = false


func _build_loading() -> void:
	_loading = CenterContainer.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	_root.add_child(_loading)
	var p := _panel(_loading, 400)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	_loading_label = _label(v, "Streaming the city…", 18)
	_loading_bar = ProgressBar.new()
	_loading_bar.max_value = 1.0
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(360, 12)
	v.add_child(_loading_bar)
	_label(v, "Shoot the ships, dodge the pink bolts. Kills in quick succession multiply your score.", 12, DIM)


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
	var p := _panel(_pause, 300)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	_label(v, "PAUSED", 24, ACCENT)
	_button(v, "Resume", func(): main.resume())
	_button(v, "Restart run", func(): main.restart_run())
	_button(v, "Music on/off (M)", func(): main.radio.toggle())
	_button(v, "Quit to menu", func(): main.back_to_menu())


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
	_label(v, "GAME OVER", 28, ACCENT)
	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.custom_minimum_size = Vector2(380, 90)
	_summary_label.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(_summary_label)
	var nrow := HBoxContainer.new()
	v.add_child(nrow)
	_summary_name = LineEdit.new()
	_summary_name.placeholder_text = "Your name"
	_summary_name.max_length = 10
	_summary_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(_summary_name)
	_post_button = _button(nrow, "Post score", func(): main.post_score())
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	v.add_child(brow)
	var again := _button(brow, "PLAY AGAIN", func(): main.restart_run(), true)
	_again_button = again
	again.add_theme_stylebox_override("normal", _style(ACCENT, 12))
	again.add_theme_stylebox_override("hover", _style(ACCENT.lightened(0.15), 12))
	again.add_theme_color_override("font_color", Color(0.1, 0.07, 0.0))
	again.custom_minimum_size = Vector2(180, 50)
	_button(brow, "Menu", func(): main.back_to_menu())


func show_summary(result: Dictionary) -> void:
	_summary.visible = true
	_post_button.disabled = false
	_post_button.text = "Post score"
	_summary_name.text = main.pilot_name
	_summary_label.text = "[b]%s[/b]\nScore [color=#ffd76a]%d[/color]\n%d ships down · reached wave %d · best combo x%d\n" % [
		result.place, int(result.score), int(result.kills), int(result.wave), int(result.best_combo)]


## Button rectangles in window pixels (for automated tests).
func button_rects_window() -> Dictionary:
	var f: float = get_tree().root.content_scale_factor
	var out := {}
	for pair in [["play", _play_button], ["play_again", _again_button]]:
		var b: Button = pair[1]
		if b != null and b.is_visible_in_tree():
			var r := b.get_global_rect()
			out[pair[0]] = [r.position.x * f, r.position.y * f, r.size.x * f, r.size.y * f]
	return out


func summary_name() -> String:
	var n := _summary_name.text.strip_edges()
	return n if n != "" else "PILOT"


func mark_posted(ok: bool) -> void:
	_post_button.disabled = true
	_post_button.text = "Posted!" if ok else "Offline"


func hide_summary() -> void:
	_summary.visible = false
