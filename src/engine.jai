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
	log("Initializing ENGINE core\n");

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

	log("Teardown ENGINE core\n");
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
		log("Plugin exiting from [%]\n", prev);
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
	log("Loading ALL available assets | dir=%\n", asset_path);

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

	tilemaps_init();
}

assets_reset :: () {
	log("Resetting Asset Management\n");

	tilemaps_deinit();

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
	assert(success, "GUID not found: %", guid);
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
	log("Saved %\n", path);

	if !table_contains(*assets.texture_table, tx.guid) {
		log("\tTexture table, initial update, %", tx.guid);
		table_set(*assets.texture_table, tx.guid, tx);
	}
}

texture_load :: (filename : string) -> *TextureAsset{
	path := tprint("%/%", config.asset_folder, filename);
	buffer, success := read_entire_file(path);

	if !success {
		log_error("Failed to load asset: %\n", path);
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

	log("\tLoaded Texture: file=% | GUID=%\n", filename, tx.guid);
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
	VERSION :: 2;

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
	shader_type := ShaderTexture.Default;

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
	append(*builder, cast(*u8)*asset.shader_type, size_of(u32));

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
	log("Saved %\n", path);

	if !table_contains(*assets.sprite_table, asset.guid) {
		log("\tSprite table, initial update, %", asset.guid);
		table_set(*assets.sprite_table, asset.guid, asset);
	}
}

sprite_load :: (filename : string) -> *Sprite {
	path := tprint("%/%", config.asset_folder, filename);
	buffer, success := read_entire_file(path);

	if !success {
		log_error("Failed to load asset: %\n", path);
		return null;
	}

	spr := sprite_alloc();

	// version migration
	VERSION := 0;
	consume_u8_and_length(*buffer, cast(*u8)*VERSION, size_of(s64));
	
	// version mismatch, migrate our sprite
	if VERSION != spr.VERSION {
		if VERSION == 1 {
			sprite_load_migration_v1_to_v2(spr, buffer);
			return spr;
		}
		assert(false, "Failed to migrate version=%", spr.VERSION);
		return null;
	}

	assert(VERSION == spr.VERSION, "ver=%", VERSION);
	consume_u8_and_length(*buffer, cast(*u8)*spr.frame_count, size_of(s64));
	consume_u8_and_length(*buffer, cast(*u8)*spr.frame_size, size_of(Vector2));
	consume_u8_and_length(*buffer, cast(*u8)*spr.play_length, size_of(float));
	consume_u8_and_length(*buffer, cast(*u8)*spr.offset, size_of(Vector2));
	consume_u8_and_length(*buffer, cast(*u8)*spr.tint, size_of(Vector4));
	consume_u8_and_length(*buffer, cast(*u8)*spr.loop, size_of(u8));
	consume_u8_and_length(*buffer, cast(*u8)*spr.default_flip_x, size_of(u8));
	consume_u8_and_length(*buffer, cast(*u8)*spr.default_flip_y, size_of(u8));
	consume_u8_and_length(*buffer, cast(*u8)*spr.shader_type, size_of(u32));
	
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

	log("\tLoaded Sprite: file=% | GUID=%\n", filename, spr.guid);
	return spr;
}

//@TODO generalize this migration code
sprite_load_migration_v1_to_v2 :: (spr : *Sprite, buffer : string) {
	assert(false, "Migration disabled for now");
}

/* 
sprite_load_migration_v1_to_v2 :: (spr : *Sprite, buffer : string) {
	assert(spr.VERSION == 2, "ver=%", spr.VERSION);
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
	//spr.path = sprint("%/%.%", config.asset_folder, spr.guid, SPRITE_EXT);
	
	// texture source
	src_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*src_len, size_of(s64));
	spr.texture_guid = alloc_string(src_len);
	consume_u8_and_length(*buffer, spr.texture_guid.data, src_len);

	sprite_save(spr);

	log("\tMigrated Sprite Ver% : GUID=%\n", spr.VERSION, spr.guid);
}
*/

// set the raw texture pointer, recreate our frame array
sprite_resolve :: (sprite : *Sprite) {
	sprite.texture_asset = get_texture(sprite.texture_guid);

	if sprite.texture_asset == null {
		log_error("\tSprite texture not set yet. GUID=%\n", sprite.guid);
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

	log("\tSprite resolved, GUID=% | Tex.GUID=% frames=%\n", 
		sprite.guid, sprite.texture_asset.guid, sprite.frames.count);
}

sprite_set_guid :: (sprite : *Sprite, guid : string) {
	string_reset(*sprite.guid);
	sprite.guid = sprint(guid);
	string_reset(*sprite.path);
	sprite.path = sprint("%/%.%", config.asset_folder, guid, SPRITE_EXT);
}

sprite_set_texture_guid :: (sprite : *Sprite, guid : string) {
	string_reset(*sprite.texture_guid);
	sprite.texture_guid = sprint(guid);
	sprite_resolve(sprite);
}

sprite_set_frame_count :: (sprite: *Sprite, frame_count : s64) {
	sprite.frame_count = frame_count;
	sprite_resolve(sprite);
}

sprite_set_frame_width :: (sprite: *Sprite, width : float) {
	sprite.frame_size.x = width;
	sprite_resolve(sprite);
}

sprite_set_frame_height :: (sprite: *Sprite, height : float) {
	sprite.frame_size.y = height;
	sprite_resolve(sprite);
}

sprite_set_play_length :: (sprite : *Sprite, length : float) {
	sprite.play_length = length;
	sprite_resolve(sprite);
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
	log("Saved %\n", path);

	if !table_contains(*assets.sounds_table, sfx.guid) {
		log("\tSFX table, initial update, %", sfx.guid);
		table_set(*assets.sounds_table, sfx.guid, sfx);
	}
}

sound_load :: (filename : string) -> *SoundAsset{
	path := tprint("%/%", config.asset_folder, filename);
	buffer, success := read_entire_file(path);

	if !success {
		log_error("Failed to load asset: %\n", path);
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

	log("\tLoaded Sound: file=% | GUID=%\n", filename, sfx.guid);
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
		log("~~~ Sound UNMUTED ~~~\n");
		mute = false;
		set_master_volume(1);
	}
	else {
		log("~~~ Game MUTED ~~~\n");
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
	return layout.root; // root get's modified by ui_line(..)
}

ui_label :: (layout : *VerticalLayout, fmt : string, args : .. Any) {
	r := ui_next(layout);
	txt := tprint(fmt, ..args);
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

ui_grid_deinit :: (using lo : *GridLayout) {
	array_reset(*column_pct);
	array_reset(*column_rects);
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

// ~~~~ Grids ~~~~

// Take from how_to/730_for_expansions
Grid :: struct (count_x: s64, count_y: s64, T: Type) {
    NUM_CELLS :: count_x*count_y;
    occupied : [NUM_CELLS] bool;
    values :   [NUM_CELLS] T;
}

grid_set :: (grid: *Grid, x: s64, y: s64, value: grid.T) {
    assert((x >= 0) && (x < grid.count_x));
    assert((y >= 0) && (y < grid.count_y));

    index := y*grid.count_x + x;
    grid.occupied[index] = true;
    grid.values[index] = value;
}

grid_remove :: (grid: *Grid, x: s64, y: s64) {
	assert((x >= 0) && (x < grid.count_x));
    assert((y >= 0) && (y < grid.count_y));

    index := y*grid.count_x + x;
    grid.occupied[index] = false;
    grid.values[index] = .{};
}

grid_get :: (grid : *Grid, x : s64, y : s64) -> grid.T {
	assert((x >= 0) && (x < grid.count_x));
    assert((y >= 0) && (y < grid.count_y));

    index := y*grid.count_x + x;
    return grid.values[index];
}

grid_occupied :: (grid : *Grid, x : s64, y : s64) -> bool {
	if x < 0 || x >= grid.count_x return false;
	if y < 0 || y >= grid.count_y return false;

    index := y*grid.count_x + x;
    return grid.occupied[index];
}

Coordinates :: struct {
    x, y: s64;
}

for_expansion :: (grid: Grid, body: Code, flags: For_Flags) #expand {
    for y: 0..grid.count_y-1 {
        for x: 0..grid.count_x-1 {
            index := y*grid.count_x + x;
            if !grid.occupied[index] continue;

            `it := grid.values[index];
            
            `it_index: Coordinates;  // Let's make a new type to provide as it_index.
            it_index.x = x;
            it_index.y = y;

            #insert body;
        }
    }
}

GridDirection :: enum_flags u8 {
	None 	:: 0;
	North 	:: 1;
	East 	:: 1<<1;
	South 	:: 1<<2;
	West 	:: 1<<3;
}

has_neighbor :: (grid : *Grid, x : s64, y : s64, direction : GridDirection) -> bool {
	result := true;
	if direction & .North 	{ result &= grid_occupied(grid, x, y+1); }
	if direction & .East 	{ result &= grid_occupied(grid, x+1, y); }
	if direction & .South 	{ result &= grid_occupied(grid, x, y-1); }
	if direction & .West 	{ result &= grid_occupied(grid, x-1, y); }
	return result;
}


// TileGrid layout of indices, represents the object that exists in the world
// id is mapped to a unique Tilemap
// index is looked up in a TileMap, Tilemap translates index to tex slice
TileGrid :: struct () {
	layers : [..] TileGridLayer;
	position : Vector2; // world position origin
	CELL_SIZE :: 32.0;
}

TileGridLayer :: struct {
	grid : Grid(MAX_TILEGRID_CELLS, MAX_TILEGRID_CELLS, TileGridEntry);
	name : string;
	flags : TileGridLayerFlags = 0;
}

TileGridEntry :: struct {
	id := 0; 			// tilemap id
	slice : u8 = 0; 	//[0-15] dependent on neighbors, determines slice of tilemap to draw
}

TileGridLayerFlags :: enum_flags u8 {
	Hidden :: 1;
}

TileMap :: struct {
	texture_guid : string;
	id := 0;
}

MAX_TILEGRID_CELLS :: 128;
MAX_TILEMAPS :: 32;
tilemaps : Table(s64, TileMap);

tilemaps_init :: () {
	init(*tilemaps, MAX_TILEMAPS);

	// hard assign these to IDs for serialization
	tilemaps_add("T_tm_grid", 1);
	tilemaps_add("T_tm_grass", 2);
	tilemaps_add("T_tm_brick", 3);
}

tilemaps_deinit :: () {
	for tilemaps {
		string_reset(*it.texture_guid);
	}
	deinit(*tilemaps);
}

tilemaps_add :: (texture_guid : string, id : s64) -> *TileMap {
	assert(is_valid(texture_guid));
	assert(!table_contains(*tilemaps, id), "id=%", id);
	tm := TileMap.{ 
		sprint(texture_guid), 
		id,
	};
	result := table_add(*tilemaps, id, tm);
	assert(result != null, "Texture GUID=% id=%", texture_guid, id);
	return result;
}

get_tilemap :: (id : s64) -> *TileMap{
	result := table_find_pointer(*tilemaps, id);
	assert(result != null, "Tilemap ID not found: %", id);
	return result;
}

is_valid_tilemap_id :: (id : s64) -> bool {
	return table_contains(*tilemaps, id);
}

is_valid :: (tg : *TileGrid) -> bool{
	return tg.layers.count > 0;
}

tilegrid_reset :: (tg : *TileGrid) {
	for * tg.layers {
		string_reset(*it.name);
	}
	array_reset(*tg.layers);
	tg.position = .{};
}

tilegrid_add_layer :: (tg : *TileGrid, name : string) {
	layer := array_add(*tg.layers);
	layer.name = sprint(name);
}

tilegrid_remove_layer :: (tg : *TileGrid, layer : s64) {
	assert(layer >= 0 && layer < tg.layers.count, "layer=%", layer);
	string_reset(*tg.layers[layer].name);
	array_unordered_remove_by_index(*tg.layers, layer);
}

tilegrid_clear_layer :: (tg : *TileGrid, layer : s64) {
	assert(layer >= 0 && layer < tg.layers.count, "layer=%", layer);
	for tg.layers[layer].grid {
		erase_tilegrid_cell(tg, layer, it_index.x, it_index.y);
	}
}

get_tilegrid_coords_from_pos :: (tg : *TileGrid, pos : Vector2) -> (x : s64, y : s64) {
	assert(is_pos_in_tilegrid(tg, pos));
	p := pos - tg.position;
	x := cast(s64)(p.x / tg.CELL_SIZE);
	y := cast(s64)(p.y / tg.CELL_SIZE);
	return x, y;
}

get_pos_in_tilegrid :: (tg : *TileGrid, x : s64, y : s64) -> Vector2 {
	result := Vector2.{
		(x+0.5) * tg.CELL_SIZE + tg.position.x,
		(y+0.5) * tg.CELL_SIZE + tg.position.y
	};
	assert(is_pos_in_tilegrid(tg, result), "result:% | %,%", result, x, y);
	return result;
}

is_pos_in_tilegrid :: (tg : *TileGrid, pos : Vector2) -> bool {
	assert(is_valid(tg));
	return pos.x >= tg.position.x 
		&& pos.y >= tg.position.y 
		&& pos.x <= tg.position.x+(tg.CELL_SIZE*tg.layers[0].grid.count_x)
		&& pos.y <= tg.position.y+(tg.CELL_SIZE*tg.layers[0].grid.count_y);
}

set_tilegrid_cell :: (tg : *TileGrid, layer : s64, x : s64, y : s64, tm_id : s64) {
	assert(is_valid(tg));
	assert(tm_id >= 0);
	assert(layer >= 0 && layer < tg.layers.count);

	if tm_id != 0 {
		assert(is_valid_tilemap_id(tm_id));

		entry := TileGridEntry.{tm_id, 0};
		grid_set(*tg.layers[layer].grid, x, y, entry);
		assert(grid_occupied(*tg.layers[layer].grid, x, y));
	}
	else {
		grid_remove(*tg.layers[layer].grid, x, y);
	}
	
	// update slice of all surrounding grid cells
	set_tilegrid_slice(tg, layer, x, y);
	set_tilegrid_slice(tg, layer, x+1, y);
	set_tilegrid_slice(tg, layer, x, y+1);
	set_tilegrid_slice(tg, layer, x-1, y);
	set_tilegrid_slice(tg, layer, x, y-1);
}

set_tilegrid_slice :: (tg : *TileGrid, layer : s64, x : s64, y : s64) {
	if !grid_occupied(*tg.layers[layer].grid, x, y) return;

	entry := grid_get(*tg.layers[layer].grid, x, y);
	entry.slice = get_tilegrid_slice(tg, layer, x, y);
	grid_set(*tg.layers[layer].grid, x, y, entry);
}

//@OPTIMIZE not sure if return-by-value is good idea here
get_tilegrid_entry :: (tg : *TileGrid, layer : s64, x : s64, y : s64) -> TileGridEntry {
	return grid_get(*tg.layers[layer].grid, x, y);
}

erase_tilegrid_cell :: (tg : *TileGrid, layer : s64, row : s64, col : s64) {
	set_tilegrid_cell(tg, layer, row, col, 0);
}

get_tilegrid_slice :: (tg : *TileGrid, layer : s64, x : s64, y : s64) -> u8 {
	grid := *tg.layers[layer].grid;
	if(has_neighbor(grid, x, y, .North|.East|.South|.West)) return 9;

	if(has_neighbor(grid, x, y, .North|.West|.South)) return 10;
	if(has_neighbor(grid, x, y, .North|.East|.South)) return 8;
	if(has_neighbor(grid, x, y, .East|.South|.West)) return 13;
	if(has_neighbor(grid, x, y, .North|.East|.West)) return 5;

	if(has_neighbor(grid, x, y, .West|.South)) return 14;
	if(has_neighbor(grid, x, y, .East|.South)) return 12;
	if(has_neighbor(grid, x, y, .North|.South)) return 11;
	if(has_neighbor(grid, x, y, .North|.West)) return 6;
	if(has_neighbor(grid, x, y, .North|.East)) return 4;
	if(has_neighbor(grid, x, y, .East|.West)) return 1;

	if (has_neighbor(grid, x, y, .North)) return 7;
	if (has_neighbor(grid, x, y, .East)) return 0;
	if (has_neighbor(grid, x, y, .South)) return 15;
	if (has_neighbor(grid, x, y, .West)) return 2;
	return 3;
}

tilegrid_shift_layer_up :: (tg : *TileGrid, layer : s64) -> (changed:bool, new_layer_index:s64){
	if layer == tg.layers.count-1 return false, layer;

	assert(layer >= 0 && layer < tg.layers.count-1, "%", layer);
	temp := tg.layers[layer];
	tg.layers[layer] = tg.layers[layer+1];
	tg.layers[layer+1] = temp;
	return true, layer+1;
}

tilegrid_shift_layer_down :: (tg : *TileGrid, layer : s64) -> (changed:bool, new_layer_index:s64){
	if layer == 0 return false, layer;

	assert(layer > 0 && layer <= tg.layers.count-1, "%", layer);
	temp := tg.layers[layer];
	tg.layers[layer] = tg.layers[layer-1];
	tg.layers[layer-1] = temp;
	return true, layer-1;
}

draw_tilemap :: (tilemap_id : s64, slice : u8, window_pos : Vector2, scale := Vector2.{1,1}, shader := ShaderTexture.PalletTint, tint := WHITE, use_window_scale := true) {
	tm := get_tilemap(tilemap_id);
	assert(is_valid(tm.texture_guid));
	texture_asset := get_texture(tm.texture_guid);
	texture := texture_asset.texture;
	
	// uv calculation based on slice
	assert(slice >= 0 && slice <= 15, "slice=%", slice);
	slice_x := slice % 4;
	slice_y := slice / 4;
	CELL_SIZE :: 32.;
	subX : float = slice_x*CELL_SIZE;
    subY : float = slice_y*CELL_SIZE;
    subW : float = CELL_SIZE;
    subH : float = CELL_SIZE;

	texW := texture.width;
	texH := texture.height;
	uv0x := Vector2.{subX / texW, subY / texH};
    uv1x := Vector2.{(subX+subW) / texW, subY / texH };
    uv2x := Vector2.{(subX+subW) / texW, (subY+subH) / texH};
    uv3x := Vector2.{subX / texW, (subY+subH) / texH};

    ws := ifx use_window_scale then get_window_aspect_scale() else 1.;
	h := Vector2.{CELL_SIZE*scale.x*ws*0.5, 0};
    v := Vector2.{0, CELL_SIZE*scale.y*ws*0.5};
	p0 := window_pos - h - v;
    p1 := window_pos + h - v;
    p2 := window_pos + h + v;
    p3 := window_pos - h + v;
	set_shader(*texture, shader);
    immediate_quad(p0, p1, p2, p3, tint, uv0=uv0x, uv1=uv1x, uv2=uv2x, uv3=uv3x);
}


// ~~~~~ Termianl ~~~~~

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
			log("\t%\n", it.text);
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
