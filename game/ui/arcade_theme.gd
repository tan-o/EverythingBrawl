class_name ArcadeTheme
extends RefCounted
## Shared arcade cabinet palette and hard-edged control states.

const FONT = preload("res://ui/fonts/NotoSansSC.ttf")

const INK := Color("101522")
const PANEL := Color("1c263b")
const RAISED := Color("263550")
const EDGE := Color("435774")
const PAPER := Color("f5eedc")
const MUTED := Color("a3b5cd")
const GOLD := Color("ffcc66")
const MINT := Color("75dfbe")
const RED := Color("f47778")

static func plate(fill: Color, edge: Color = EDGE, width := 2, pad := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0.025, 0.04, 0.08, 0.65)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 4)
	return s

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	t.default_font = FONT
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "PopupMenu", "TabContainer", "TabBar"]:
		t.set_color("font_color", type, PAPER)
		t.set_color("font_disabled_color", type, MUTED.darkened(0.3))
		t.set_color("font_hover_color", type, GOLD)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_focus_color", type, GOLD)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, plate(PANEL))
		t.set_stylebox("hover", type, plate(RAISED, GOLD))
		t.set_stylebox("pressed", type, plate(GOLD, GOLD.lightened(0.2)))
		t.set_stylebox("hover_pressed", type, plate(GOLD.lightened(0.1), PAPER))
		t.set_stylebox("disabled", type, plate(INK.lightened(0.04), PANEL))
		var focus := plate(Color.TRANSPARENT, MINT, 3, 0)
		focus.draw_center = false
		t.set_stylebox("focus", type, focus)
		t.set_constant("h_separation", type, 14)
	for type in ["Panel", "PanelContainer", "PopupPanel", "PopupMenu", "Window", "AcceptDialog"]:
		t.set_stylebox("panel", type, plate(PANEL, EDGE, 2, 24))
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, plate(INK, EDGE))
		t.set_stylebox("read_only", type, plate(INK, EDGE))
		t.set_stylebox("focus", type, plate(INK, MINT))
		t.set_color("caret_color", type, GOLD)
		t.set_color("selection_color", type, Color("456285"))
		t.set_color("font_placeholder_color", type, MUTED)
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, plate(RAISED, GOLD, 2, 16))
		t.set_stylebox("tab_unselected", type, plate(INK, EDGE, 1, 16))
		t.set_stylebox("tab_hovered", type, plate(PANEL, MINT, 2, 16))
		t.set_stylebox("panel", type, plate(PANEL, EDGE, 2, 22))
		t.set_color("font_selected_color", type, GOLD)
		t.set_color("font_unselected_color", type, MUTED)
	for type in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", type, plate(INK, INK, 0, 5))
		t.set_stylebox("grabber", type, plate(EDGE, EDGE, 0, 5))
		t.set_stylebox("grabber_highlight", type, plate(MINT, MINT, 0, 5))
		t.set_stylebox("grabber_pressed", type, plate(GOLD, GOLD, 0, 5))
	t.set_stylebox("normal", "ProgressBar", plate(INK, EDGE, 1, 4))
	t.set_stylebox("fill", "ProgressBar", plate(MINT, MINT, 0, 4))
	t.set_stylebox("separator", "HSeparator", plate(EDGE, EDGE, 0, 1))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	return t

static func primary(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", plate(GOLD, Color("ffe6a3")))
	b.add_theme_stylebox_override("hover", plate(GOLD.lightened(0.18), PAPER))
	b.add_theme_stylebox_override("pressed", plate(Color("dfa94b"), GOLD))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, INK)
	return b
