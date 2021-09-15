extends Control


const _PaletteColor := preload("res://scenes/palette_color.tscn")
const _LOAD_FILTERS := PoolStringArray(["*.bmp", "*.dds", "*.exr", "*.hdr", "*.jpg", "*.jpeg", "*.png", "*.tga", "*.svg", "*.svgz", "*.webp"])
const _SAVE_FILTERS := PoolStringArray(["*.png"])

var _selected_color: ColorRect
var _importing := false
var _thread: Thread

onready var _palette_options := $HBox/Colors/VBox/Palettes
onready var _spin_box := $HBox/Colors/VBox/HBoxContainer2/SpinBox
onready var _grid := $HBox/Colors/VBox/Scroll/Marg/Grid
onready var _select := $HBox/Colors/VBox/Select
onready var _gen := $HBox/Colors/VBox/Gen
onready var _save := $HBox/Colors/VBox/Save
onready var _before := $HBox/Images/VBox/Before
onready var _after := $HBox/Images/VBox/After
onready var _file_dialog := $FileDialog
onready var _error := $Error
onready var _color_picker := $ColorPop/ColorPicker


func _ready() -> void:
	# Set up palettes
	_palette_options.add_item("Do Not Recolor")
	_palette_options.add_item("Custom Palette")
	for palette in Palettes.PALETTES:
		_palette_options.add_item(palette)
	
	# Set up file dialog
	_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)


# Must be called deferred!
func _on_palettes_item_selected(i: int) -> void:
	_selected_color = null
	for c in _grid.get_children():
		c.free()
	if i == 0 or i == 1:
		pass
	else:
		var b := ButtonGroup.new()
		var p = _palette_options.get_item_text(i)
		for color in Palettes.PALETTES[p]:
			var c := _PaletteColor.instance()
			c.color = color
			c.get_node("Button").group = b
			_grid.add_child(c)
# warning-ignore:return_value_discarded
			c.get_node("Button").connect("pressed", self, "_on_color_button_pressed", [c])


func _on_select_pressed() -> void:
	_importing = false
	_file_dialog.mode = FileDialog.MODE_OPEN_FILE
	_file_dialog.filters = _LOAD_FILTERS
	_file_dialog.popup_centered()


func _on_save_pressed() -> void:
	_file_dialog.mode = FileDialog.MODE_SAVE_FILE
	_file_dialog.filters = _SAVE_FILTERS
	_file_dialog.popup_centered()


func _on_file_dialog_file_selected(path: String) -> void:
	if _file_dialog.mode == FileDialog.MODE_OPEN_FILE:
		var i := Image.new()
		if not i.load(path) == OK:
			_error.text = "Error loading image."
			_error.popup_centered()
			return
		if _importing:
			_palette_options.selected = 0
			_on_palettes_item_selected(0)
			var colors := []
			i.lock()
			for x in i.get_width():
				for y in i.get_height():
					var color := i.get_pixel(x, y)
					if not color in colors:
						colors.append(color)
			i.unlock()
			for color in colors:
				var c := _PaletteColor.instance()
				c.color = color
				_grid.add_child(c)
# warning-ignore:return_value_discarded
				c.get_node("Button").connect("pressed", self, "_on_color_button_pressed", [c])
		else:
			var t := ImageTexture.new()
			t.create_from_image(i, 0)
			_before.texture = t
			_after.texture = null
			_gen.disabled = false
			_save.disabled = true
	else:
		var i: Image = _after.texture.get_data()
		if not i.save_png(path) == OK:
			_error.text = "Error saving image."
			_error.popup_centered()


func _on_gen_pressed() -> void:
	_thread = Thread.new()
# warning-ignore:return_value_discarded
	_thread.start(self, "_recolor_image")
	

func _recolor_image(_dummy) -> void:
	$Working.popup_centered()
	_gen.disabled = true
	var image: Image = _before.texture.get_data()
	var resize_x:int = image.get_width()/_spin_box.value if image.get_width()/_spin_box.value > 1 else 1
	var resize_y:int = image.get_height()/_spin_box.value if image.get_height()/_spin_box.value > 1 else 1
	image.resize(resize_x, resize_y, 0)
	if not (_palette_options.selected == 0 or _grid.get_child_count() == 0):
		var palette := []
		for c in _grid.get_children():
			palette.append(c.color)
		image.lock()
		for x in image.get_width():
			for y in image.get_height():
				var image_color := image.get_pixel(x, y)
				var closest_dist := 4.0
				var closest_color: Color
				for color in palette:
					var dist := abs(color.r-image_color.r) +\
						abs(color.g-image_color.g) +\
						abs(color.b-image_color.b)
					if dist <= closest_dist:
						closest_dist = dist
						closest_color = color
				closest_color.a = image_color.a
				image.set_pixel(x, y, closest_color)
		image.unlock()
	var image_texture := ImageTexture.new()
	image_texture.create_from_image(image, 0)
	_after.texture = image_texture
	_save.disabled = false
	_gen.disabled = false
	$Working.hide()
	call_deferred("_close_thread")
	

func _close_thread() -> void:
	_thread.wait_to_finish()


func _on_color_picker_color_changed(color: Color) -> void:
	if _selected_color:
		_selected_color.color = color


func _on_color_button_pressed(color_rect: ColorRect) -> void:
	_selected_color = color_rect
	_color_picker.color = color_rect.color
	$ColorPop.popup_centered()


func _on_add_pressed() -> void:
	var c := _PaletteColor.instance()
	c.color = _color_picker.color
	if _grid.get_child_count() == 0:
		c.get_node("Button").group = ButtonGroup.new()
	else:
		c.get_node("Button").group = _grid.get_child(0).get_node("Button").group
	_grid.add_child(c)
# warning-ignore:return_value_discarded
	c.get_node("Button").connect("pressed", self, "_on_color_button_pressed", [c])
	c.get_node("Button").pressed = true
	c.get_node("Button").grab_focus()
	yield(get_tree(), "idle_frame")
	$HBox/Colors/VBox/Scroll.get_v_scrollbar().ratio = 1.0


func _on_delete_pressed() -> void:
	if _selected_color:
		_selected_color.queue_free()
		_selected_color = null


func _on_import_pressed() -> void:
	_importing = true
	_file_dialog.mode = FileDialog.MODE_OPEN_FILE
	_file_dialog.filters = _LOAD_FILTERS
	_file_dialog.popup_centered()


func _on_meta_clicked(meta) -> void:
# warning-ignore:return_value_discarded
	OS.shell_open(meta)


func _on_credits_pressed() -> void:
	$Credits.popup_centered()
