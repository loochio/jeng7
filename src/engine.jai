// engine.jai - Portable chunk between projects
// v0.6 / 13 Sept 2025

window : Window_Type;
window_width := 0;
window_height := 0;
window_center : Vector2;
window_size : Vector2;
window_aspect := 1.0;
window_quit := false;

mute := false;
music_stream : *Sound_Stream; //@TODO reimplment, disabled for now

exe_path : string;
root_path : string;
asset_path : string;
img_path : string;


EngineConfig :: struct {
	name : string = "Default";
	world_width := 640;
	world_height := 480;
	window_width := 640;
	window_height := 480;
	aspect : float; 
	x := 0;
	y := 0;
	bg_color := WHITE;

	asset_folder : string;
	img_folder := "img";
	font : string;

	fps := 144;
	vsync := true;

	plugins : [..] EnginePlugin;
	startup_plugin : string;
}
config : EngineConfig;

EngineProc :: #type ();
EngineProc_Level :: #type (level_name : string);
EngineProc_Tick :: #type (dt : float);

active_plugin : *EnginePlugin;

EnginePlugin :: struct {
	name : string;
	proc_init 	: EngineProc;
	proc_deinit : EngineProc;
	proc_begin 	: EngineProc;
	proc_end 	: EngineProc;
	proc_tick 	: EngineProc_Tick;
	proc_render : EngineProc_Tick;
}

debug_ui_enabled := true; //@TODO probably clean this up

ENABLE_FRUSTRUM_CULLING :: false;

WINDOW_SCALE_DEFAULT :: 1.;
forced_window_scale_x := WINDOW_SCALE_DEFAULT;
forced_window_scale_y := WINDOW_SCALE_DEFAULT;

engine_dt: float = 0.;
last_time:  float64;
DT_MAX : float : 0.15;
fps : float = 0.;

// ui
hud_font : *Dynamic_Font;
hud_font_factor := 0.025;
hud_font_pixel_height := 0;

hud_current_theme: s32 = xx Default_Themes.Blood_Vampire;
//hud_current_theme: s32 = xx Default_Themes.Default;
//hud_current_theme: s32 = xx Default_Themes.Grayscale;
//hud_current_theme: s32 = xx Default_Themes.Bentonite;
//hud_current_theme: s32 = xx Default_Themes.Nimbus;
//hud_current_theme: s32 = xx Default_Themes.Freddie_Freeloader;
//hud_current_theme: s32 = xx Default_Themes.HIGH_CONTRAST;

hud_theme: Overall_Theme;

// Input
mouse_pos_window : Vector2;
input_mod_ctrl := false;
input_mod_alt := false;
input_mod_shift := false;
ui_hit_this_frame := false;
terminal_enabled := false;

Camera :: struct {
	position : Vector2;
	zoom := 1.0;
}

// Colors
WHITE 		:: Vector4.{1,1,1,1};
GREY 		:: Vector4.{.5,.5,.5,1};
BLACK 		:: Vector4.{0,0,0,1};
RED 		:: Vector4.{1,0,0,1};
ORANGE 		:: Vector4.{1,.5,0,1};
GREEN 		:: Vector4.{0,1,0,1};
BLUE 		:: Vector4.{0,0,1,1};
MAGENTA 	:: Vector4.{1,0,1,1};
YELLOW 		:: Vector4.{1,1,0,1};
CYAN 		:: Vector4.{0,1,1,1};


engine_init :: (cfg : EngineConfig) {
	print("Initializing ENGINE core\n");

	config = cfg;
	exe_path = get_path_of_running_executable();
	root_path = path_strip_filename(exe_path);
	asset_path = join(root_path, cfg.asset_folder);
	img_path = join(asset_path, cfg.img_folder);

	window_width = config.window_width;
	window_height = config.window_height;
	resize_viewport();
	engine_ui_init();

	window = create_window(window_name=cfg.name, 
		width=window_width, height=window_height,
		window_x = cfg.x, window_y = cfg.y);

	set_render_target(window);

	sound_player_init(.{update_from_a_thread = true});

	shader_init();
	assets_init();

	//@TODO put behind a runtime config, not sure what that default value needs to be
	if !config.vsync {
		wglSwapIntervalEXT(0);
	}

	register_commands();
	set_plugin(config.startup_plugin);

	while !window_quit {
		reset_temporary_storage();
	
		update_window_events();
		for event : events_this_frame {
			//@TODO build define out in RELEASE builds
			if event.type == .QUIT || is_input_pressed(.ESCAPE) {
	            window_quit = true;
	            break;
	        }
			getrect_handle_event(event);
	    }

		// window resizing
		for get_window_resizes() {
            update_window(it.window);
            if it.window == window {
                should_reinit := (it.width != window_width) || (it.height != window_height);
                window_width  = it.width;
                window_height = it.height;

                if should_reinit {
                	engine_ui_resize();
                	resize_viewport();
                }
            }
        }
    	update_mouse();
    	Sound.update();

    	// time updates
		now := seconds_since_init();
    	delta : float64 = now - last_time;
    	engine_dt = cast(float) delta;
    	last_time = now;
    	fps = 1 / engine_dt;

    	if engine_dt > DT_MAX engine_dt = DT_MAX;

    	// UI UPDATE - All UI rendering/polling needs to be handled after this point
    	ui_hit_this_frame = false;
		ui_per_frame_update(window, xx window_width, xx window_height, now);

	    // ~~~ Engine Input ~~~ 
	    input_mod_ctrl = is_input_down(.CTRL);
	    input_mod_alt = is_input_down(.ALT);
	    input_mod_shift = is_input_down(.SHIFT);

		if is_input_pressed(96 /*`*/)  	{ 
			terminal_enabled = !terminal_enabled;
			terminal_id += 1;
		}

    	//@TODO feels hacky, we're only doing this to block kb input
    	if !terminal_enabled {
    		active_plugin.proc_tick(engine_dt);
    	}

		// ~~~ rendering ~~~ 
		{
			c := config.bg_color;
			clear_render_target(c.x, c.y, c.z, c.w);
			active_plugin.proc_render(engine_dt);
			debug_rendering();
			swap_buffers(window);
		}

		//@TODO proper fps
		//https://github.com/QuattroMusic/6502-Simulator/blob/main/src/engine/core.jai#L49-L65
		if config.fps != -1 {
			delay : s32 = cast(s32)((1.0 / config.fps) * 1000);
			sleep_milliseconds(delay);
		}
	}

	print("Teardown ENGINE core\n");
	sound_player_shutdown();
	active_plugin.proc_deinit();
	assets_reset();
}

set_plugin :: (plugin : string) {
	prev := active_plugin;
	for config.plugins {
		if plugin == it.name {
			active_plugin = *it;
			break;
		}
	}

	if prev != null {
		print("Plugin exiting from [%]\n", prev);
		prev.proc_deinit();
	}

	active_plugin.proc_init();
}

is_input_pressed :: (key : Key_Code, consume_input := false) -> bool {
	result := input_button_states[key] & .START != 0;

	if result && consume_input {
		input_button_states[key] &= ~.START;
	}

	return result;
}

is_input_down :: (key : Key_Code) -> bool {
	return input_button_states[key] & .DOWN != 0;
}

is_input_released :: (key : Key_Code) -> bool {
	return input_button_states[key] & .END != 0;
}

resize_viewport :: () {
	if !window_height return;

	window_aspect = window_width / cast(float)window_height;
	window_center = Vector2.{window_width/2., window_height/2.};
	window_size = Vector2.{xx window_width, xx window_height};
}

draw_square :: (pos_window : Vector2, size : Vector2, color : Vector4) {
	set_shader_for_color(true);
    h := Vector2.{size.x * .5, 0};
    v := Vector2.{0, size.y * .5};
	p0 := pos_window - h - v;
    p1 := pos_window + h - v;
    p2 := pos_window + h + v;
    p3 := pos_window - h + v;
    immediate_quad(p0, p1, p2, p3, color);
}

draw_square_custom :: (pos_window : Vector2, size : Vector2, color : Vector4, type := ShaderType.Custom) {
	set_shader(type);
    h := Vector2.{size.x * .5, 0};
    v := Vector2.{0, size.y * .5};
	p0 := pos_window - h - v;
    p1 := pos_window + h - v;
    p2 := pos_window + h + v;
    p3 := pos_window - h + v;
    immediate_quad(p0, p1, p2, p3, color);
}

draw_box :: (box : Box, color : Vector4, thickness := 2.) {
	t := thickness;
	draw_square(.{box.x + box.w/2, box.y}, .{t, box.h}, color);
	draw_square(.{box.x - box.w/2, box.y}, .{t, box.h}, color);
	draw_square(.{box.x, box.y+box.h/2}, .{box.w, t}, color);
	draw_square(.{box.x, box.y-box.h/2}, .{box.w, t}, color);
}

draw_rect :: (r : Rect, color : Vector4)
{
	draw_square(.{r.x+r.w/2.,r.y+r.h/2.}, .{r.w, r.h}, color);
}

// mostly copied from GetRect/color_picker.jai, draw_hsv_circle()
draw_circle :: (center_window : Vector2, radius_outer : float, radius_inner : float = 0, color : Vector4,
		percent_begin := 0.) 
{
	set_shader_for_color(true);
	NUM_SEGMENTS :: 16;
	last_p0, last_p1: Vector2 = ---;

	for i: 0..NUM_SEGMENTS - 1 {
        t := i / cast(float)(NUM_SEGMENTS - 1);

        // start from 12 oclock
        radians := TAU * (t+.25);
        dir := Vector2.{cos(radians), sin(radians)};

        p0 := center_window + dir * radius_outer;
        p1 := center_window + dir * radius_inner;

        // omit percentage of the circle
        if (i != 0 && t > percent_begin) {
        	immediate_triangle(to_vec3(last_p0), to_vec3(last_p1), to_vec3(p1), color, color, color);
            immediate_triangle(to_vec3(last_p0), to_vec3(p1), to_vec3(p0), color, color, color);
        }

        last_p0 = p0;
        last_p1 = p1;
    }
}

draw_collider :: (collider : *Collider, window_pos : Vector2, win_size : Vector2) {
	c := BLUE;
	if collider.type == {
		case .Dynamic; c = MAGENTA;
		case .Trigger; c = YELLOW;
		case .Inactive; c= WHITE;
	}
	if !collider.enabled c = RED;

	p := window_pos;
	if collider.shape== {
		case .Circle; {
			r := win_size.x;
			draw_circle(p, radius_outer=r, radius_inner=r-2, color=c);
		}
		case .Box; {
			box := Box.{p.x, p.y, win_size.x, win_size.y};
			draw_box(box, c);
		}
	}
}

draw_texture :: (texture : *Texture, window_pos : Vector2, scale := Vector2.{1,1}, outline := false) {
	width := texture.width * scale.x;
	height := texture.height * scale.y;

	if outline {
		draw_box(.{window_pos.x, window_pos.y, width, height}, RED);
	}

	h := Vector2.{width*.5, 0};
    v := Vector2.{0, height*.5};
	p0 := window_pos - h - v;
    p1 := window_pos + h - v;
    p2 := window_pos + h + v;
    p3 := window_pos - h + v;
	set_shader_for_images(texture);

	//@TODO move this down to gfx.jai
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    immediate_quad(p0, p1, p2, p3, WHITE);
}



// ~~~~~~~ Collision / Util ~~~~~~~ 

Box :: struct {
	x : float = 0;
	y : float = 0;
	w : float = 0;
	h : float = 0;
}

AABB :: struct {
	lower : Vector2;
	upper : Vector2;
}

Collider :: struct {
	type := ColliderType.Inactive;
	shape := ColliderShape.Circle;
	size : Vector2;
	flags : ColliderFlags;
	enabled := true;
	asleep := false;

	//@TODO maybe store in global map so we don't need to set this for every collider
	is_a : ColliderMask;
	collides_with : ColliderMask;
}

ColliderType :: enum u8 {
	Inactive;
	Static;
	Dynamic;
	Kinematic;
	Trigger;
}

ColliderShape :: enum u8 {
	Circle;
	Box; //@TODO
}

ColliderMask :: enum_flags u8 {
	Pawn;
	Wall;
	Hero;
}

ColliderFlags :: enum_flags u8 {
	//Enabled; @TODO add these eventually
	//Asleep;
	Overlapping;
}

collider_reset :: (c : *Collider) {
	c.type = ColliderType.Inactive;
	c.shape = ColliderShape.Circle;
	c.size = Vector2.{0,0};
	c.enabled = true;
	c.asleep = false;
	c.is_a = 0;
	c.collides_with = 0;
}

is_overlap :: (apos : Vector2, a : *Collider, bpos : Vector2, b : *Collider) -> bool{
	if !b.enabled return false;
	if b.type == .Inactive return false;
	if a.is_a & b.collides_with == 0 return false;

	if a.shape == .Circle && b.shape == .Circle {
		return is_overlap_circle(apos, a.size.x, bpos, b.size.x);
	}

	if a.shape == .Box && b.shape == .Box {
		//@TODO
		//return is_overlap_aabb();
	}

	if a.shape == .Circle && b.shape == .Box {
		return is_overlap_circle_box(apos, a.size.x, bpos, b.size);
	}
	if b.shape == .Circle && a.shape == .Box {
		return is_overlap_circle_box(bpos, b.size.x, apos, a.size);
	}

	assert(false, "Unsupported combo, a=% b=%", a.shape, b.shape);
	return false;
}

is_in_circle :: (pos : Vector2, circle_center : Vector2, radius : float) -> bool {
	dist2 := distance_squared(pos, circle_center);
	return dist2 < (radius*radius);
}

is_overlap_circle :: (c0 : Vector2, r0 : float, c1 : Vector2, r1 : float) -> bool {
	dist := distance(c0, c1);
	return dist < (r0 + r1);
}

//@TODO
is_overlap_aabb :: (box0 : AABB, box1 : AABB) -> bool {
	return false;
}

is_overlap_circle_box :: (p0 : Vector2, r0 : float, p1 : Vector2, size1 : Vector2) -> bool{
	edge_x := clamp(p0.x, p1.x-size1.x/2., p1.x+size1.x/2.);
	edge_y := clamp(p0.y, p1.y-size1.y/2., p1.y+size1.y/2.);
	dx := p0.x - edge_x;
	dy := p0.y - edge_y;
	dist2 := dx*dx + dy*dy;
	return dist2 <= (r0*r0);
}

is_in_box :: (pos : Vector2, box : Box) -> bool {
	return pos.x > box.x-box.w/2. && pos.x < box.x+box.w/2.
		&& pos.y > box.y-box.h/2. && pos.y < box.y+box.h/2.;
}

get_box_intersection :: (a : Box, b : Box) -> bool, Box {
	xmin := max(a.x-a.w/2., b.x-b.w/2.);
	xmax := min(a.x+a.w/2., b.x+b.w/2.);
	ymin := max(a.y-a.h/2., b.y-b.h/2.);
	ymax := min(a.y+a.h/2., b.y+b.h/2.);

	if xmin < xmax && ymin < ymax {
		w := xmax-xmin;
		h := ymax-ymin;
		return true, Box.{xmin+w/2., ymin+h/2., w, h};
	}
	return false, Box.{};
}

string_reset :: (str : *string) {
	if str.count free(str.data);
	str.count = 0;
}

is_valid :: (str : string) -> bool{
	return str.count > 0;
}

linear_move :: (position : *Vector2, velocity : *Vector2, dt : float) {
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
}

is_nearly_zero :: (value : float) -> bool {
	return value < EPSILON && value > -EPSILON;
}

//@TODO, replace that scuffed check in subworld_render()
is_nearly_equal :: (a : float, b : float) -> bool {
	assert(false);
	return true;
}

get_window_aspect_scale :: () -> float {
	if window_aspect > config.aspect {
		return window_height / cast(float)config.world_height;
	}
	else {
		return window_width / cast(float)config.world_width;
	}
}

scalar_to_window :: (value : float) -> float {
	return value * get_window_aspect_scale() * forced_window_scale_x;
}

vec_to_window :: (window_pos : Vector2) -> Vector2 {
	result := window_pos;
	scale := get_window_aspect_scale();
	result.x *= scale * forced_window_scale_x;
	result.y *= scale * forced_window_scale_y;
	result.x += window_width/2.;
	result.y += window_height/2.;
	return result;
}

update_mouse :: (){
	x, y, success := get_mouse_pointer_position();
	if success {
		mouse_pos_window.x = cast(float)x;
		mouse_pos_window.y = cast(float)(window_height - y); // invery mouse y to start at bottom
	}
}

// ~~~~~~~ Asset Management ~~~~~~~ 

MAX_ASSETS_TEXTURES :: 4096;
MAX_ASSETS_SPRITES :: 4096;
MAX_ASSETS_SOUNDS :: 4096;

assets : AssetManager;

AssetManager :: struct {
	//@TODO do we get rid of the Pool since we have this Table now?
	textures : Pool(TextureAsset, MAX_ASSETS_TEXTURES); 
	texture_table : Table(string, *TextureAsset);

	sprites : Pool(Sprite, MAX_ASSETS_SPRITES);
	sprite_table : Table(string, *Sprite);

	sounds : Pool(SoundAsset, MAX_ASSETS_SOUNDS);
	sounds_table : Table(string, *SoundAsset);
}


assets_init :: () {
	print("Loading ALL available assets | dir=%\n", asset_path);

	init(*assets.texture_table, MAX_ASSETS_TEXTURES);
	init(*assets.sprite_table, MAX_ASSETS_SPRITES);
	init(*assets.sounds_table, MAX_ASSETS_SOUNDS);

	files := file_list(asset_path);
	for files {
		path := parse_path(it);
		assert(path.words.count > 0);
		filename := path.words[path.words.count-1];

		if contains(filename, TEXTURE_EXT) 	texture_load(filename);
		if contains(filename, SPRITE_EXT) 	sprite_load(filename);
		if contains(filename, SOUNDS_EXT) 	sound_load(filename);
	}

	// assets loaded, time to resolve intra-asset dependencies
	for assets.sprites {
		sprite_resolve(it);
	}
}

assets_reset :: () {
	print("Resetting Asset Management\n");
	pool_reset(*assets.textures);
	table_reset(*assets.texture_table);

	pool_reset(*assets.sprites);
	table_reset(*assets.sprite_table);

	pool_reset(*assets.sounds);
	table_reset(*assets.sounds_table);
}


// ~~~~~~~ Texture Assets ~~~~~~~ 

TextureAsset :: struct {
	VERSION :: 1;
	guid : string;
	path : string; //relative path of this asset
	source_path : string; //path to source image this asset wraps
	texture : Texture;
}

TEXTURE_EXT :: "tasset";

is_valid :: (tx : *TextureAsset) -> bool {
	return is_valid(tx.guid);
}

get_texture :: (guid : string) -> *TextureAsset {
	success, result := table_find_new(*assets.texture_table, guid);
	assert(success, "%", guid);
	return result;
}

texture_alloc :: () -> *TextureAsset {
	return pool_alloc(*assets.textures);
}

texture_save :: (tx : *TextureAsset) {
	builder: String_Builder;
	init_string_builder(*builder);

	ver := tx.VERSION;
	append(*builder, cast(*u8)*ver, size_of(s64));

	guid_len := cast(*u8)*tx.guid.count;
	append(*builder, guid_len, size_of(s64));
	append(*builder, tx.guid);

	src_len := cast(*u8)*tx.source_path.count;
	append(*builder, src_len, size_of(s64));
	append(*builder, tx.source_path);

	path := tprint("%/%.%", config.asset_folder, tx.guid, TEXTURE_EXT);
	write_entire_file(path, *builder);
	reset(*builder);
	print("Saved %\n", path);
}

texture_load :: (filename : string) -> *TextureAsset{
	path := tprint("%/%", config.asset_folder, filename);
	buffer, success := read_entire_file(path);

	if !success {
		print("Failed to load asset: %\n", path);
		return null;
	}

	tx := texture_alloc();

	// version
	VERSION := 0;
	consume_u8_and_length(*buffer, cast(*u8)*VERSION, size_of(s64));
	assert(VERSION == tx.VERSION, "ver=%", VERSION);

	// guid
	guid_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*guid_len, size_of(s64));
	tx.guid = alloc_string(guid_len);
	consume_u8_and_length(*buffer, tx.guid.data, guid_len);

	tx.path = sprint("%/%.%", config.asset_folder, tx.guid, TEXTURE_EXT);
	
	// texture source
	src_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*src_len, size_of(s64));
	tx.source_path = alloc_string(src_len);
	consume_u8_and_length(*buffer, tx.source_path.data, src_len);

	texture_load_from_src(tx);
	
	assert(!table_contains(*assets.texture_table, tx.guid), "%", tx.guid);
	table_set(*assets.texture_table, tx.guid, tx);

	print("\tLoaded Texture: file=% | GUID=%\n", filename, tx.guid);
	return tx;
}

texture_load_from_src :: (tx : *TextureAsset) {
	load_raw_texture(tx.source_path, *tx.texture);
}

load_raw_texture :: (name : string, out : *Texture) -> bool{
	path := tprint("%/%", img_path, name);
	return texture_load_from_file(out, path);
}

texture_rename :: (tx : *TextureAsset, guid : string) {
	string_reset(*tx.guid);
	tx.guid = sprint(guid);
	string_reset(*tx.path);
	tx.path = sprint("%/%.%", config.asset_folder, guid, TEXTURE_EXT);
}


// ~~~~~~~ Sprites ~~~~~~~ 

Sprite :: struct {
	VERSION :: 1;

	//@TODO duplicate, can be moved to Asset struct
	guid : string;
	path : string;

	texture_guid : string; 	// serialized, should be a T_* string
	frame_count := 1;
	frame_size : Vector2;
	play_length : float = 1.;
	loop := true;
	default_flip_x := false;
	default_flip_y := false;
	offset : Vector2; // window_space
	tint := WHITE;

	// runtime values
	initialized := false; //@TODO convert these bools to enum_flags
	resolved := false;
	texture_asset : *TextureAsset;	// pointer to our texture pool
	texture : *Texture; //@TODO remove for above asset ref

	frames : [..] SpriteFrame;
	frame_current := 0;
	play_position : float = 0.;
	play_rate : float = 1.;
	playing := true;
	visible := true;
	flip_x := false;
	flip_y := false;
	tint_mult := WHITE; //@TODO come back to this to make sure we're setting the right value
}

SpriteFrame :: struct {
	index := 0;
	coords : Box;
	play_length : float = 0;
	play_start : float = 0;
}

SPRITE_EXT :: "sasset";

sprite_alloc :: () -> *Sprite {
	sprite := pool_alloc(*assets.sprites);
	sprite.initialized = true;
	return sprite;
}

sprite_free :: (sprite : *Sprite) {
	sprite.initialized = false;
	pool_remove(*assets.sprites, sprite);
}

is_valid :: (sprite : *Sprite) -> bool {
	return sprite.initialized;
}

get_sprite :: (guid : string) -> *Sprite {
	success, result := table_find_new(*assets.sprite_table, guid);
	assert(success, "%", guid);
	return result;
}

sprite_save :: (asset : *Sprite) {
	builder: String_Builder;
	init_string_builder(*builder);

	ver := asset.VERSION;
	append(*builder, cast(*u8)*ver, size_of(s64));
	append(*builder, cast(*u8)*asset.frame_count, size_of(s64));
	append(*builder, cast(*u8)*asset.frame_size, size_of(Vector2));
	append(*builder, cast(*u8)*asset.play_length, size_of(float));
	append(*builder, cast(*u8)*asset.offset, size_of(Vector2));
	append(*builder, cast(*u8)*asset.tint, size_of(Vector4));
	append(*builder, cast(*u8)*asset.loop, size_of(u8));
	append(*builder, cast(*u8)*asset.default_flip_x, size_of(u8));
	append(*builder, cast(*u8)*asset.default_flip_y, size_of(u8));

	name_len := cast(*u8)*asset.guid.count;
	append(*builder, name_len, size_of(s64));
	append(*builder, asset.guid);

	src_len := cast(*u8)*asset.texture_guid.count;
	append(*builder, src_len, size_of(s64));
	append(*builder, asset.texture_guid);

	// write the final file
	path := tprint("%/%.%", config.asset_folder, asset.guid, SPRITE_EXT);
	write_entire_file(path, *builder);
	reset(*builder);
	print("Saved %\n", path);
}

sprite_load :: (filename : string) -> *Sprite {
	path := tprint("%/%", config.asset_folder, filename);
	buffer, success := read_entire_file(path);

	if !success {
		print("Failed to load asset: %\n", path);
		return null;
	}

	spr := sprite_alloc();

	// version
	VERSION := 0;
	consume_u8_and_length(*buffer, cast(*u8)*VERSION, size_of(s64));
	assert(VERSION == spr.VERSION, "ver=%", VERSION);

	consume_u8_and_length(*buffer, cast(*u8)*spr.frame_count, size_of(s64));
	consume_u8_and_length(*buffer, cast(*u8)*spr.frame_size, size_of(Vector2));
	consume_u8_and_length(*buffer, cast(*u8)*spr.play_length, size_of(float));
	consume_u8_and_length(*buffer, cast(*u8)*spr.offset, size_of(Vector2));
	consume_u8_and_length(*buffer, cast(*u8)*spr.tint, size_of(Vector4));
	consume_u8_and_length(*buffer, cast(*u8)*spr.loop, size_of(u8));
	consume_u8_and_length(*buffer, cast(*u8)*spr.default_flip_x, size_of(u8));
	consume_u8_and_length(*buffer, cast(*u8)*spr.default_flip_y, size_of(u8));
	
	// guid
	guid_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*guid_len, size_of(s64));
	spr.guid = alloc_string(guid_len);
	consume_u8_and_length(*buffer, spr.guid.data, guid_len);

	//@TODO we aren't using this, we just define the path up there in sprite_save(..)
	spr.path = sprint("%/%.%", config.asset_folder, spr.guid, SPRITE_EXT);
	
	// texture source
	src_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*src_len, size_of(s64));
	spr.texture_guid = alloc_string(src_len);
	consume_u8_and_length(*buffer, spr.texture_guid.data, src_len);

	assert(!table_contains(*assets.sprite_table, spr.guid), "%", spr.guid);
	table_set(*assets.sprite_table, spr.guid, spr);

	print("\tLoaded Sprite: file=% | GUID=%\n", filename, spr.guid);
	return spr;
}

// set the raw texture pointer, recreate our frame array
sprite_resolve :: (sprite : *Sprite) {
	sprite.texture_asset = get_texture(sprite.texture_guid);

	if sprite.texture_asset == null {
		print("\tSprite texture not set yet. GUID=%\n", sprite.guid);
		return;
	}
	
	sprite.texture = *sprite.texture_asset.texture;
	assert(sprite.texture != null);

	// initialize frames once we have a valid texture
	if sprite.frames.count > 0 
		array_reset(*sprite.frames);

	fsize := sprite.frame_size;
	flength := sprite.play_length / sprite.frame_count;
	fstart := 0.;
	for 0..sprite.frame_count-1 {
		frame := array_add(*sprite.frames);
		frame.index = it;
		frame.coords = Box.{x=fsize.x*it, y=0, w=fsize.x, h=fsize.y};
		frame.play_length = flength;
		frame.play_start = fstart;
		fstart += frame.play_length;
	}

	sprite.resolved = true;

	print("\tSprite resolved, GUID=% | Tex.GUID=% frames=%\n", 
		sprite.guid, sprite.texture_asset.guid, sprite.frames.count);
}

sprite_set_guid :: (sprite : *Sprite, guid : string) {
	string_reset(*sprite.guid);
	sprite.guid = sprint(guid);
	string_reset(*sprite.path);
	sprite.path = sprint("%/%.%", config.asset_folder, guid, SPRITE_EXT);
}

draw_sprite :: (sprite : *Sprite, window_pos : Vector2, scale := Vector2.{1,1}, use_window_scale := true) {
	if !sprite.initialized return;
	if !sprite.visible return;

	set_shader_for_images(sprite.texture);
    
    frame := sprite.frames[sprite.frame_current];

    texW := sprite.texture.width;
    texH := sprite.texture.height;

    subX : float = frame.coords.x;
    subY : float = frame.coords.y;
    subW : float = frame.coords.w;
    subH : float = frame.coords.h;

    uv0x := Vector2.{subX / texW, subY / texH};
    uv1x := Vector2.{(subX+subW) / texW, subY / texH };
    uv2x := Vector2.{(subX+subW) / texW, (subY+subH) / texH};
    uv3x := Vector2.{subX / texW, (subY+subH) / texH};

    ws := ifx use_window_scale then get_window_aspect_scale() else 1.;
    h := Vector2.{frame.coords.w * .5 * ws * scale.x * forced_window_scale_x, 0};
    v := Vector2.{0, frame.coords.h * .5 * ws * scale.y * forced_window_scale_y};

    if sprite.default_flip_x	h *= -1;
    if sprite.flip_x			h *= -1;
    if sprite.default_flip_y	v *= -1;
    if sprite.flip_y			v *= -1;

	p0 := window_pos - h - v + sprite.offset;
    p1 := window_pos + h - v + sprite.offset;
    p2 := window_pos + h + v + sprite.offset;
    p3 := window_pos - h + v + sprite.offset;

    color := sprite.tint * sprite.tint_mult;
    immediate_quad(p0, p1, p2, p3, color, uv0=uv0x, uv1=uv1x, uv2=uv2x, uv3=uv3x);
}

sprite_step :: (sprite : *Sprite) {
	if !sprite.initialized return;

	if sprite.frame_current+1 >= sprite.frames.count {
		if sprite.loop {
			sprite_reset(sprite);
		}
		else {
			sprite.playing = false;
		}
		return;
	}
	sprite.frame_current += 1;
}

sprite_tick :: (sprite : *Sprite, dt : float) {
	if !sprite.initialized return;
	if !sprite.resolved return;
	if !sprite.playing return;

	sprite.play_position += (dt * sprite.play_rate);
	fc := sprite.frame_current;
	frame := sprite.frames[fc];
	if sprite.play_position > (frame.play_start + frame.play_length) {
		sprite_step(sprite);
	}
} 

sprite_reset :: (sprite : *Sprite) {
	sprite.frame_current = 0;
	sprite.play_position = 0;
}

sprite_play :: (sprite : *Sprite, play_rate := 1.) {
	sprite.playing = true;
	sprite.play_rate = play_rate;
}

sprite_pause :: (sprite : *Sprite) {
	sprite.playing = false;
}

sprite_resume :: (sprite : *Sprite) {
	sprite.playing = true;
}


// ~~ Sound ~~

//@CLEAN
//_OLD_SfxAsset :: struct {
//	id : s64;
//	name : string;
//	data : Sound_Data;
//}

SoundAsset :: struct {
	VERSION :: 1;
	guid : string;
	path : string; //relative path of this asset
	source_path : string; //path to source .wav this asset wraps
	sound : Sound_Data;
}

SOUNDS_EXT :: "sfxasset";

is_valid :: (sfx : *SoundAsset) -> bool {
	return is_valid(sfx.guid);
}

sound_alloc :: () -> *SoundAsset {
	return pool_alloc(*assets.sounds);
}

sound_save :: (sfx : *SoundAsset) {
	builder: String_Builder;
	init_string_builder(*builder);

	ver := sfx.VERSION;
	append(*builder, cast(*u8)*ver, size_of(s64));

	guid_len := cast(*u8)*sfx.guid.count;
	append(*builder, guid_len, size_of(s64));
	append(*builder, sfx.guid);

	src_len := cast(*u8)*sfx.source_path.count;
	append(*builder, src_len, size_of(s64));
	append(*builder, sfx.source_path);

	path := tprint("%/%.%", config.asset_folder, sfx.guid, SOUNDS_EXT);
	write_entire_file(path, *builder);
	reset(*builder);
	print("Saved %\n", path);

	if !table_contains(*assets.sounds_table, sfx.guid) {
		print("\tSFX table, initial update, %", sfx.guid);
		table_set(*assets.sounds_table, sfx.guid, sfx);
	}
}

sound_load :: (filename : string) -> *SoundAsset{
	path := tprint("%/%", config.asset_folder, filename);
	buffer, success := read_entire_file(path);

	if !success {
		print("Failed to load asset: %\n", path);
		return null;
	}

	sfx := sound_alloc();

	// version
	VERSION := 0;
	consume_u8_and_length(*buffer, cast(*u8)*VERSION, size_of(s64));
	assert(VERSION == sfx.VERSION, "ver=%", VERSION);

	// guid
	guid_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*guid_len, size_of(s64));
	sfx.guid = alloc_string(guid_len);
	consume_u8_and_length(*buffer, sfx.guid.data, guid_len);
	
	// texture source
	src_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*src_len, size_of(s64));
	sfx.source_path = alloc_string(src_len);
	consume_u8_and_length(*buffer, sfx.source_path.data, src_len);

	sound_resolve(sfx);

	//@TODO leak?
	sfx.path = sprint("%/%.%", config.asset_folder, sfx.guid, TEXTURE_EXT);

	assert(!table_contains(*assets.sounds_table, sfx.guid), "%", sfx.guid);
	table_set(*assets.sounds_table, sfx.guid, sfx);

	print("\tLoaded Sound: file=% | GUID=%\n", filename, sfx.guid);
	return sfx;
}

load_raw_sound :: (name: string) -> Sound_Data {
    path := tprint("%/sound/%", asset_path, name);
    return load_audio_file(path);
}

sound_resolve :: (sfx : *SoundAsset) {
	sfx.sound = load_raw_sound(sfx.source_path);
	assert(sfx.sound.loaded, "Sound data was not loaded, path=%", sfx.path);
}

sound_set_guid :: (sfx : *SoundAsset, guid : string) {
	string_reset(*sfx.guid);
	sfx.guid = sprint(guid);
	string_reset(*sfx.path);
	sfx.path = sprint("%/%.%", config.asset_folder, guid, SOUNDS_EXT);
}

get_sound :: (guid : string) -> *SoundAsset {
	success, result := table_find_new(*assets.sounds_table, guid);
	assert(success, "%", guid);
	assert(result != null);
	return result;
}

play_sound :: (guid : string) -> *Sound_Stream {
	sfx := get_sound(guid);
	return play_sound(sfx);
}

play_sound :: (sfx : *SoundAsset) -> *Sound_Stream {
	return play_sound(*sfx.sound);
}

//@TODO need play_sound_random(pitch_min, pitch_max, vol_min, vol_max)
play_sound :: (data: *Sound_Data, category := Sound_Category.GENERAL_SFX) -> *Sound_Stream 
{
	assert(data.loaded, "Sound data was not loaded");
    stream := Sound.make_stream(data, category);
    start_playing(stream);
    return stream;
}

//@TODO probably merge this API with engine.play_sound()
/*
play_sound :: (id : Sfx_ID, vol_min := 1., vol_max := 1., pitch_min := 1., pitch_max := 1.) -> *Sound_Stream {
	sfx := play_sound(*sfx_assets[id].data);
    if sfx {
    	sfx.user_volume_scale = random_get_within_range(vol_min, vol_max);
		sfx.rate_scale = random_get_within_range(pitch_min, pitch_max); 
    }
    return sfx;
}
*/

play_music :: (data: *Sound_Data) {
	assert(music_stream == null);
	music_stream = Sound.make_stream(data, .MUSIC);
	set_repeating(music_stream, true);
    music_stream.user_volume_scale *= 0.15;
    start_playing(music_stream);
}

toggle_mute :: () {
	if mute {
		print("~~~ Sound UNMUTED ~~~\n");
		mute = false;
		set_master_volume(1);
	}
	else {
		print("~~~ Game MUTED ~~~\n");
		mute = true;
		set_master_volume(0);
	}
}


// ~~~ Pooling ~~~

Pool :: struct (T : Type, size : s64) {
	values : [size] T;
	occupied : [size] bool;
	head := 0; //@TODO prob remove, always keep this head at 0
	tail := 0;
}

pool_reset :: (using pool : *Pool) {
	tail = 0;
	for occupied occupied[it_index] = false;
	for values values[it_index] = .{};
}

// fast alloc, O(1) (best case) well sort of, we still do a (probably) unnecessary loop
pool_alloc :: (using pool : *Pool) -> *pool.T {
	first_pass := true;
	while tail < occupied.count {
		if occupied[tail] {
			tail += 1;

			// try scanning from the beginning once before failing
			if tail == occupied.count {
				if first_pass{
					first_pass = false;
					tail = head;
				}
				else {
					break;
				}
			}

			continue;
		}
		assert(tail < occupied.count); //ran out of memory, not sure how we want to handle this
		occupied[tail] = true;
		return *values[tail];
	}
	assert(false); // failed to alloc mem
	return null;
}

// Slow, linear lookup O(n)
pool_remove :: (pool : *Pool, value : *pool.T) {
	for pool {
		if it == value {
			pool.values[it_index] = .{};
			pool.occupied[it_index] = false;
			return;
		}
	}
}

for_expansion :: (pool : *Pool, body : Code, flags : For_Flags) #expand {
	for idx : 0..pool.values.count-1 {
		if !pool.occupied[idx] continue;

		value := *pool.values[idx];
		if !is_valid(value) continue;

		`it := value;
		`it_index := idx;

		#insert body;
	}
}

// ~~~ UI ~~~

engine_ui_init :: () {
	// Necessary for GetRect
	ui_init();
	engine_ui_set_theme();
    engine_ui_resize();
}

engine_ui_set_theme :: () {
	proc := default_theme_procs[hud_current_theme];
    hud_theme = proc();
    set_default_theme(hud_theme);
}

engine_ui_resize :: () {
	hud_font_pixel_height = cast(s64)(window_height * hud_font_factor);
	hud_font = get_font_at_size(asset_path, config.font, hud_font_pixel_height);
    assert(hud_font != null);
}

update_ui_hit :: (r : *Rect) {
	ui_hit_this_frame |= is_inside(mouse_pos_window.x, mouse_pos_window.y, r);
}


//~~~ UI Layouts ~~~

// assumes r.h is our line height
ui_line :: (r : *Rect, line : s64, direction := 1) -> s64 {
	r.y += r.h * direction;
	return line+1;
}

Layout :: struct {
	root : Rect;
}

//@TODO
//HorizontalLayout :: struct {}
//GridLayout :: struct {}

VerticalLayout :: struct {
	#as using layout : Layout;
	line := 0;
	direction := VerticalGrowDirection.Up;
}

VerticalGrowDirection :: enum {
	Down; //@TODO need to get this working, based on pivot values
	Up;
}

ui_line :: (layout : *VerticalLayout) {
	dir := ifx layout.direction == .Up then 1 else -1;
	layout.line = ui_line(*layout.root, layout.line, dir);
}

ui_next :: (layout : *VerticalLayout) -> Rect {
	ui_line(layout);
	return layout.root;
}

ui_label :: (layout : *VerticalLayout, fmt : string, args : .. Any) {
	r := ui_next(layout);
	txt := tprint(fmt, args);
	label(r, txt, *hud_theme.label_theme);
}

ui_label :: (r : Rect, fmt : string, args : .. Any) {
	txt := tprint(fmt, args);
	label(r, txt, *hud_theme.label_theme);
}

GridLayout :: struct {
	#as using vert_layout : VerticalLayout;

	// represent some normalized % of width 
	// Ex. [ 0.5, 0.5, 1 ] -> 25% | 25% | 50%
	columns : []float;
	column_pct : [..]float; 
	column_rects : [..] Rect;
}

ui_grid_init :: (using lo : *GridLayout) {
	// calc normalized col percents
	total := 0.;
	for columns { total += it; }
	for columns { array_add(*column_pct, it / total); }

	// calc column rects
	xoffset := 0.;
	for column_pct {
		r : = Rect.{root.x+xoffset, root.y, root.w*it, root.h};
		array_add(*column_rects, r);
		xoffset += r.w;
	}
}

ui_col :: (layout : *GridLayout, col := 0) -> Rect {
	assert(col >= 0 && col < layout.column_rects.count);
	r := layout.column_rects[col];
	r.y = r.h + r.h*layout.line;
	return r;
}


// Moving this out of the main loop for readability
debug_rendering :: () {
	#if DEVELOPER {
		if debug_ui_enabled {
			draw_text :: (line : s64, format_string: string, args: .. Any) {
				text := tprint(format_string, ..args);
				text_width := prepare_text(hud_font, text);
				text_x := window_width - text_width;
			    text_y := window_height - hud_font.character_height * line;
			    draw_prepared_text(hud_font, text_x, text_y, RED);
			}
			draw_text(1, "fps=%", formatFloat(fps, trailing_width=2));
		}
	}

	if terminal_enabled {
		k := window_height * .1;
		w := cast(float)window_width;
		r := get_rect(0, 0, w, hud_font.character_height*1.35);
		text_theme := hud_theme.text_input_theme;
		text_theme.alignment = .Left;
		text_theme.font = hud_font;
		action, input := text_input(r, terminal_prompt, *text_theme, identifier=terminal_id, input_action=.ACTIVATE, auto_complete=terminal_auto_complete);

		// process console cheats
		if action & .ENTERED  {
			terminal_id += 1;
			terminal_prompt = "";
			found, cmd, args := split_from_left(input, " ");

			//@TODO clean up the ugly duplicated code
			//@OPTIMIZE faster lookup with a hash map
			if found {
				for terminal_cmds { 
					if cmd == it.text {
						it.proc(args); 
						terminal_enabled = false;
						break;
					}
				}
			}
			else {
				for terminal_cmds { 
					if input == it.text {
						 it.proc(); 
						 terminal_enabled = false;
						 break;
					}
				}
			}
		}
	}
}

terminal_prompt : string;
terminal_id : s64;
terminal_auto_complete := Auto_Complete.{terminal_cmds_auto_complete, null};

TerminalCommand :: struct {
	text : string;
	proc : TerminalCmdProc;
}

terminal_cmds : [..] TerminalCommand;

TerminalCmdProc :: #type (args: .. Any);

register_cmd :: (text : string, proc : TerminalCmdProc) {
	// skip duplicates, @TODO not sure if we should log anything?
	for terminal_cmds { if it.text == text return; }

	cmd := TerminalCommand.{ text, proc };
	array_add(*terminal_cmds, cmd);
}

terminal_cmds_auto_complete :: (input: string, data: *void) -> (results: [] string, longest_match_length: int) {
    results: [..] string;
    longest_match_length := 0;
    #if DEVELOPER {
    	for terminal_cmds {
	        count := begins_with_count(it.text, input);
	        if count == input.count {
	            array_add(*results, it.text);
	            longest_match_length = max(longest_match_length, input.count);
	        }
	        longest_match_length = max(longest_match_length, count);
	    }
    }
    return results, longest_match_length;
}

// copied from GetRect/example.jai
begins_with_count :: (str: string, prefix: string) -> int {
    for 0..prefix.count-1 {
        if it >= str.count return it;

        ca := to_lower(str[it]);
        cb := to_lower(prefix[it]);
        if ca != cb return it;
    }
    return prefix.count;
}

//@TODO these terminal commands have entered game design territory
// we'll have to build define these out. maybe? maybe we leave some of these enabled?
register_commands :: () {
	#if !DEVELOPER return;

	register_cmd("toggle_ui", (args: .. Any) { debug_ui_enabled = !debug_ui_enabled; });
	register_cmd("toggle_mute", (args: .. Any) { toggle_mute(); });
	register_cmd("fps", (args: .. Any) {  config.fps = ifx config.fps == -1 then 144 else -1; });

	register_cmd("help", (args: .. Any) {
		print("Registered Commands\n");
		for terminal_cmds {
			print("\t%\n", it.text);
		}
	});

	register_cmd("plugin", (args: .. Any) { 
		if args.count == 1 {
			arg := args[0];
			name := tprint("%", arg);
			set_plugin(name); 
		}
	});

	register_cmd("game", (args: .. Any) { set_plugin("game"); } );
	register_cmd("edit", (args: .. Any) { set_plugin("editor"); } );
	register_cmd("assets", (args: .. Any) { set_plugin("assets"); } );

	register_cmd("assets_reload", (args: .. Any) { 
		assets_reset();
		assets_init();
	});

	register_cmd("shader_init", (args: .. Any) { shader_init(); } );
}


#import "Basic";
#import "System";
#import "File";
#import "File_Utilities";
#import "String";
#import "Window_Creation";
#import "Input";
#import "Math";
#import "Random";
#import "Simp";
#import "GL";
#import "GetRect";
using Sound :: #import "Sound_Player";
#import "Hash_Table";
#import "Hash";

#load "gfx.jai";
