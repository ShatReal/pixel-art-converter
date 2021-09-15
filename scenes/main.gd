extends Control


const _PaletteColor := preload("res://scenes/palette_color.tscn")
const _LOAD_FILTERS := PoolStringArray(["*.bmp", "*.dds", "*.exr", "*.hdr", "*.jpg", "*.jpeg", "*.png", "*.tga", "*.svg", "*.svgz", "*.webp"])
const _IMPORT_FILTERS := PoolStringArray(["*.bmp", "*.dds", "*.exr", "*.hdr", "*.jpg", "*.jpeg", "*.png", "*.tga", "*.svg", "*.svgz", "*.webp", "*.gpl", "*.pal"])
const _SAVE_FILTERS := PoolStringArray(["*.png"])

var _selected_color: ColorRect
var _importing := false
var counter := 0
var _mutex: Mutex
var _semaphore: Semaphore
var _thread: Thread
var _exit_thread := false

onready var _palette_options := $HBox/Colors/Scroll/VBox/Palettes
onready var _use_palette := $HBox/Colors/Scroll/VBox/UsePalette/CheckButton
onready var _outline := $HBox/Colors/Scroll/VBox/Outline/CheckButton
onready var _outline_color := $HBox/Colors/Scroll/VBox/OutlineColor/ColorRect
onready var _resize := $HBox/Colors/Scroll/VBox/Resize/CheckButton
onready var _pixel_size := $HBox/Colors/Scroll/VBox/PixelSize/SpinBox
onready var _blur := $HBox/Colors/Scroll/VBox/Blur/SpinBox
onready var _grid := $HBox/Colors/Scroll/VBox/Marg/Grid
onready var _select := $HBox/Colors/Scroll/VBox/Select
onready var _gen := $HBox/Colors/Scroll/VBox/Gen
onready var _save := $HBox/Colors/Scroll/VBox/Save
onready var _before := $HBox/Images/VBox/Before
onready var _after := $HBox/Images/VBox/After
onready var _file_dialog := $FileDialog
onready var _error := $Error
onready var _color_picker := $ColorPop/ColorPicker


func _ready() -> void:
	_mutex = Mutex.new()
	_semaphore = Semaphore.new()
	_exit_thread = false
	_thread = Thread.new()
	_thread.start(self, "_thread_work")
	
	# Set up palettes
	_palette_options.add_item("Custom Palette")
	for palette in Palettes.PALETTES:
		_palette_options.add_item(palette)
	_palette_options.selected = 1
	_on_palettes_item_selected(1)
	
	# Set up file dialog
	_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	
	_on_gen_pressed()
	

func _exit_tree() -> void:
	_mutex.lock()
	_exit_thread = true
	_mutex.unlock()
	_semaphore.post()
	_thread.wait_to_finish()


func _on_palettes_item_selected(i: int) -> void:
	_selected_color = null
	for c in _grid.get_children():
		c.free()
	if not i == 0:
		var b := ButtonGroup.new()
		var p = _palette_options.get_item_text(i)
		for color in Palettes.PALETTES[p]:
			var c := _PaletteColor.instance()
			c.color = color
			c.get_node("Button").group = b
			_grid.add_child(c)
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
		if _importing:
			_import_palette(path)
		else:
			var i := Image.new()
			if not i.load(path) == OK:
				_error.dialog_text = "Error loading image."
				_error.popup_centered()
				return
			var t := ImageTexture.new()
			t.create_from_image(i, 0)
			_before.texture = t
			_after.texture = null
			_gen.disabled = false
			_save.disabled = true
	else:
		var i: Image = _after.texture.get_data()
		if not i.save_png(path) == OK:
			_error.dialog_text = "Error saving image."
			_error.popup_centered()
			
			
func _import_palette(path: String):
	_palette_options.selected = 0
	_on_palettes_item_selected(0)
	var colors: Array
	match path.get_extension():
		"png":
			colors = _import_palette_from_png(path)
		"gpl":
			colors = _import_palette_from_gpl(path)
		"pal":
			colors = _import_palette_from_pal(path)
	for color in colors:
		var c := _PaletteColor.instance()
		c.color = color
		_grid.add_child(c)
		c.get_node("Button").connect("pressed", self, "_on_color_button_pressed", [c])


func _import_palette_from_png(path: String) -> Array:
	var image := Image.new()
	if not image.load(path) == OK:
		_error.dialog_text = "Error loading image."
		_error.popup_centered()
		return []
	var colors := []
	image.lock()
	for x in image.get_width():
		for y in image.get_height():
			var color := image.get_pixel(x, y)
			if not color in colors:
				colors.append(color)
	image.unlock()
	return colors


func _import_palette_from_gpl(path: String) -> Array:
	var f = File.new()
	f.open(path, File.READ)
	var colors := []
	for i in 3:
		f.get_line()
	var total := int(f.get_line())
	for i in total:
		colors.append(Color(f.get_line().split("\t")[-1]))
	f.close()
	return colors
	
	
func _import_palette_from_pal(path: String) -> Array:
	var f = File.new()
	f.open(path, File.READ)
	var colors := []
	for i in 2:
		f.get_line()
	var total := int(f.get_line())
	for i in total:
		var a: Array = f.get_line().split(" ")
		var b := []
		for j in a.size():
			b.append(float(a[j]) / 255)
		colors.append(Color(b[0], b[1], b[2]))
	f.close()
	return colors


func _on_gen_pressed() -> void:
	$Working.popup_centered()
	_increment_counter()


func _thread_work(_dummy) -> void:
	while true:
		_semaphore.wait()
		_mutex.lock()
		var should_exit := _exit_thread
		_mutex.unlock()
		if should_exit:
			break
		_mutex.lock()
		counter += 1
		_mutex.unlock()
		
		_modify_image()
	

func _increment_counter():
	_semaphore.post()
	

func _get_counter():
	_mutex.lock()
	var counter_value := counter
	_mutex.unlock()
	return counter_value
	

func _modify_image() -> void:
	var image: Image = _before.texture.get_data()
	var og_x := image.get_width()
	var og_y = image.get_height()
	var resize_x:int = image.get_width()/_pixel_size.value if image.get_width()/_pixel_size.value > 1 else 1
	var resize_y:int = image.get_height()/_pixel_size.value if image.get_height()/_pixel_size.value > 1 else 1
	image.resize(resize_x, resize_y, 0)
	if not _blur.value == 0:
		image = _blur_image(image)
	if _use_palette.pressed and not _grid.get_child_count() == 0:
		_recolor_image(image)
	if _outline.pressed:
		_outline_image(image)
	if not _resize.pressed:
		image.resize(og_x, og_y, 0)
	var image_texture := ImageTexture.new()
	image_texture.create_from_image(image, 0)
	_after.texture = image_texture
	_save.disabled = false
	$Working.hide()
	
	
# Uses Gaussian blur
func _blur_image(image: Image) -> Image:
	image.lock()
	var result_image := Image.new()
	result_image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	result_image.lock()
	for x in image.get_width():
		for y in image.get_height():
			var i_min := max(x-_blur.value, 0)
			var i_max := min(x+_blur.value+1, image.get_width())
			var j_min := max(y-_blur.value, 0)
			var j_max := min(y+_blur.value+1, image.get_height())
			var weights := []
			var total_weights := Color(0.0, 0.0, 0.0, 0.0)
			for i in range(i_min, i_max):
				var column := []
				for j in range(j_min, j_max):
					var weight := Color(
						_gauss(i-x, j-y, 1.5),
						_gauss(i-x, j-y, 1.5),
						_gauss(i-x, j-y, 1.5),
						_gauss(i-x, j-y, 1.5)
					)
					column.append(weight)
					total_weights += weight
				weights.append(column)
			for k in weights.size():
				for l in weights[k].size():
					weights[k][l] /= total_weights
			var total_gauss := Color(0.0, 0.0, 0.0, 0.0)
			for i in range(i_min, i_max):
				for j in range(j_min, j_max):
					total_gauss += image.get_pixel(i, j) * weights[i-i_min][j-j_min]
			result_image.set_pixel(x, y, total_gauss)
	result_image.unlock()
	image.unlock()
	return result_image
	

func _gauss(x:int, y:int, std:float):
	return pow(exp(1), -(pow(x, 2)+pow(y, 2))/(2*pow(std,2)))/(2*PI*pow(std,2))


func _recolor_image(image: Image) -> void:
	image.lock()
	var palette := []
	for c in _grid.get_children():
		palette.append(c.color)
	for x in image.get_width():
		for y in image.get_height():
			var image_color := image.get_pixel(x, y)
			if not image_color.a == 0.0:
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


func _outline_image(image: Image) -> void:
	image.lock()
	var outline_pixels := []
	for x in image.get_width():
		for y in image.get_height():
			if image.get_pixel(x, y).a == 0 and (
				(x != 0 and image.get_pixel(x-1, y).a != 0) or
				(x != image.get_width()-1 and image.get_pixel(x+1, y).a != 0) or
				(y != 0 and image.get_pixel(x, y-1).a != 0) or
				(y != image.get_height()-1 and image.get_pixel(x, y+1).a != 0)
			):
				outline_pixels.append(Vector2(x, y))
	for pixel in outline_pixels:
		image.set_pixelv(pixel, _outline_color.color)
	image.unlock()


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
	_file_dialog.filters = _IMPORT_FILTERS
	_file_dialog.popup_centered()


func _on_meta_clicked(meta) -> void:
# warning-ignore:return_value_discarded
	OS.shell_open(meta)


func _on_credits_pressed() -> void:
	$Credits.popup_centered()


func _on_outline_color_pressed() -> void:
	_selected_color = _outline_color
	_color_picker.color = _selected_color.color
	$ColorPop.popup_centered()
