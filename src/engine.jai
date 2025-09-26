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

//hud_current_theme: s32 = xx Default_Themes.Default;
//hud_current_theme: s32 = xx Default_Themes.Grayscale;
//hud_current_theme: s32 = xx Default_Themes.Bentonite;
//hud_current_theme: s32 = xx Default_Themes.Nimbus;
hud_current_theme: s32 = xx Default_Themes.Blood_Vampire;
//hud_current_theme: s32 = xx Default_Themes.Freddie_Freeloader;
//hud_current_theme: s32 = xx Default_Themes.HIGH_CONTRAST;

hud_theme: Overall_Theme;
terminal_enabled := false;

// Input
mouse_pos_window : Vector2;
input_mod_ctrl := false;
input_mod_alt := false;
input_mod_shift := false;
ui_hit_this_frame := false;

Camera :: struct {
	position : Vector2;
	zoom := 1.0;
}

// Colors
WHITE 		:: Vector4.{1,1,1,1};
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

	init_textures();
	init_sprites();
	init_sound();
	init_particles();

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
	            return;
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

is_input_pressed :: (key : Key_Code) -> bool {
	return input_button_states[key] & .START != 0;
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

draw_box :: (box : Box, color : Vector4, thickness := 2.) {
	t := thickness;
	draw_square(.{box.x + box.w/2, box.y}, .{t, box.h}, color);
	draw_square(.{box.x - box.w/2, box.y}, .{t, box.h}, color);
	draw_square(.{box.x, box.y+box.h/2}, .{box.w, t}, color);
	draw_square(.{box.x, box.y-box.h/2}, .{box.w, t}, color);
}

// mostly copied from GetRect/color_picker.jai, draw_hsv_circle()
draw_circle :: (center_window : Vector2, radius_outer : float, radius_inner : float = 0, color : Vector4,
		percent_begin := 0.) 
{
	set_shader_for_color(true);
	//NUM_SEGMENTS :: 16; @CLEAN temp while we debug
	NUM_SEGMENTS :: 80;
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

draw_collider :: (collider : *Collider, window_pos : Vector2, win_radius : float) {
	//if collider.type == .Inactive return; @CLEAN

	r := win_radius;
	//r := collider.size.x*2.; @CLEAN
	c := BLUE;
	if collider.type == {
		case .Dynamic; c = MAGENTA;
		case .Trigger; c = YELLOW;
		case .Inactive; c= WHITE;
	}
	if !collider.enabled c = RED;
	draw_circle(window_pos, radius_outer=r, radius_inner=r-2, color=c);
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
	AABB; //@TODO
}

ColliderMask :: enum_flags u8 {
	Pawn;
	Wall;
	Hero;
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

	if a.shape == .AABB && b.shape == .AABB {
		//@TODO
		//return is_overlap_aabb();
	}

	if a.shape == .Circle && b.shape == .AABB || a.shape == .AABB && b.shape == .Circle{
		//@TODO
		//return is_overlap_circle_aabb();
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

//@TODO
is_overlap_circle_aabb :: (c0 : Vector2, r0 : float, box1 : AABB) -> bool {
	return false;
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

//@TODO
/*to_box :: (aabb : *AABB) -> Box {
	result := Box.{};
	dx:= distance(aabb.upper.x, aabb.lower.x);
	result.x = aabb.upper.x - aabb.lower.x
	return .{
		.x = 
	};
}*/

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

// ~~~~~~~ Textures ~~~~~~~ 

TextureAsset :: struct {
	id : s64;
	name : string;
	texture : Texture;
	loaded := false;
}

load_texture :: (name : string, out : *Texture) -> bool{
	path := tprint("%/%", img_path, name);
	return texture_load_from_file(out, path);
}

// ~~~~~~~ sprites ~~~~~~~ 

Sprite :: struct {
	initialized := false; //@TODO convert these bools to enum_flags
	layer := 0;
	size : Vector2;
	offset : Vector2; // window_space
	tint := WHITE;
	tint_mult := WHITE;
	texture : *Texture;
	texture_size : Vector2;
	frames : [..] SpriteFrame;
	frame_current := 0;
	play_length : float = 0;
	play_position : float = 0;
	play_rate : float = 1.0;
	playing := true;
	loop := true;
	visible := true;
	flipped := false;
}

SpriteFrame :: struct {
	index := 0;
	coords : Box;
	play_length : float = 0;
	play_start : float = 0;
}

//@TODO define sprite data in a SpriteAsset
init_sprite :: (tid : TextureID, frame_size := Vector2.{32,32}, 
	in_tint := Vector4.{1,1,1,1}, frames := 1, play_length : float = 0, layer := 0) -> Sprite 
{
	sprite := Sprite.{
		initialized = true,
		tint = in_tint,
		size = frame_size,

		//@TODO we're assuming a horizontal packing of frames, will be improved with atlas parsing
		texture_size = Vector2.{frame_size.x*frames, frame_size.y},
		layer = layer,
	};
	sprite.texture = *get_texture(tid).texture;
	assert(sprite.texture != null);

	for 0..frames-1 {
		frame := SpriteFrame.{
			index = it,
			coords = Box.{x=frame_size.x*it, y=0, w=frame_size.x, h=frame_size.y},
			play_length = play_length / frames,
			play_start = sprite.play_length,
		};
		sprite.play_length += frame.play_length;
		array_add(*sprite.frames, frame);
	}
	return sprite;
}

//@TODO not sure yet where/when we're calling this
deinit_sprite :: (sprite : *Sprite) {
	array_reset(*sprite.frames);
}

render_sprite :: (sprite : *Sprite, window_pos : Vector2, scale := Vector2.{1,1}) {
	if !sprite.initialized return;
	if !sprite.visible return;

	set_shader_for_images(sprite.texture);
    
    frame := sprite.frames[sprite.frame_current];
    texW := sprite.texture_size.x;
    texH := sprite.texture_size.y;

    subX : float = frame.coords.x;
    subY : float = frame.coords.y;
    subW : float = frame.coords.w;
    subH : float = frame.coords.h;

    uv0x := Vector2.{subX / texW, subY / texH};
    uv1x := Vector2.{(subX+subW) / texW, subY / texH };
    uv2x := Vector2.{(subX+subW) / texW, (subY+subH) / texH};
    uv3x := Vector2.{subX / texW, (subY+subH) / texH};

    ws := get_window_aspect_scale();
    h := Vector2.{frame.coords.w * .5 * ws * scale.x * forced_window_scale_x, 0};
    v := Vector2.{0, frame.coords.h * .5 * ws * scale.y * forced_window_scale_y};

    if sprite.flipped {
    	h *= -1;
    }

	p0 := window_pos - h - v + sprite.offset;
    p1 := window_pos + h - v + sprite.offset;
    p2 := window_pos + h + v + sprite.offset;
    p3 := window_pos - h + v + sprite.offset;

    color := sprite.tint * sprite.tint_mult;
    immediate_quad(p0, p1, p2, p3, color, uv0=uv0x, uv1=uv1x, uv2=uv2x, uv3=uv3x);
}

sprite_step :: (sprite : *Sprite) {
	if !sprite.initialized return;

	fc := sprite.frame_current;
	if fc+1 >= sprite.frames.count {
		if sprite.loop {
			sprite.frame_current = 0;
		}
		return;
	}
	sprite.frame_current = fc+1;
}

sprite_tick :: (sprite : *Sprite, dt : float) {
	if !sprite.initialized return;
	if !sprite.playing return;

	sprite.play_position += (dt * sprite.play_rate);
	fc := sprite.frame_current;
	frame := sprite.frames[fc];
	if sprite.play_position > (frame.play_start + frame.play_length) {
		if sprite.loop {
			sprite.play_position = 0;
		}
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

SfxAsset :: struct {
	id : s64;
	name : string;
	data : Sound_Data;
}

load_sound :: (name: string) -> Sound_Data {
    path := tprint("%/sound/%", asset_path, name);
    return load_audio_file(path);
}

//@TODO need play_sound_random(pitch_min, pitch_max, vol_min, vol_max)
play_sound :: (data: *Sound_Data, category := Sound_Category.GENERAL_SFX) -> *Sound_Stream 
{
    stream := Sound.make_stream(data, category);
    start_playing(stream);
    return stream;
}

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


// ~~ Particle System ~~
// mostly copied from Invaders Jai example

Particle_Emitter :: struct {
    position : Vector2;
    velocity : Vector2;

    particles: [..] Particle;
    fadeout_period : float = 0.1;
    particles_per_second : float = 150;

    speed0 : float = 0;
    speed1 : float = 0.1;

    size0 : float = 0.001;
    size1 : float = 0.005;

    drag0 : float = 0.9999;
    drag1: float = 0.9;

    lifetime0: float = 0.4;
    lifetime1: float = 1.0;

    emitter_lifetime := -1.0;

    theta0: float = 0;
    theta1: float = TAU;

    color0: Vector4;
    color1: Vector4;

    elapsed : float = 0;
    remainder : float = 0;

    enabled := true;
    producing := true;
}

Particle :: struct {
    position: Vector2;
    velocity: Vector2;

    size     := 0.0;
    lifetime := 2.0;
    drag     := 1.0;

    elapsed  := 0.0;

    color:   Vector4;
}

particle_texture : Texture;

//@TODO needs to be moved to game world
live_emitters : [..] *Particle_Emitter;

init_particles :: () {
	load_texture("particles/particle.png", *particle_texture);
}

deinit :: (emitter: *Particle_Emitter) {
    array_free(emitter.particles);
}

destroy :: (emitter: *Particle_Emitter) {
	array_ordered_remove_by_value(*live_emitters, emitter);  // Ordered remove, because we spawn some emitters in specific orders.
    deinit(emitter);
    free(emitter);
}

tick_emitter :: (emitter: *Particle_Emitter, dt: float) {
    sim_particle :: (p: *Particle, dt: float) {
        linear_move(*p.position, *p.velocity, dt);

        // @Incomplete: Apply correct drag over time.
        p.velocity *= p.drag;
        p.elapsed  += dt;
    }

    for * p: emitter.particles {
        sim_particle(p, dt);

        if p.elapsed > p.lifetime {
            remove p;
        }
    }

    dt_per_particle := 1.0 / emitter.particles_per_second;

    emitter.elapsed += dt;
    emitter.remainder += dt;

    if emitter.emitter_lifetime >= 0 then {
        emitter.emitter_lifetime -= dt;
        if emitter.emitter_lifetime < 0 then emitter.producing = false;
    }

    spawn_particle :: (emitter: *Particle_Emitter) -> *Particle {
        p := array_add(*emitter.particles);

        p.position = emitter.position;
        p.velocity = emitter.velocity;

        p.size = random_get_within_range(emitter.size0, emitter.size1);
        p.drag = random_get_within_range(emitter.drag0, emitter.drag1);
        p.lifetime = random_get_within_range(emitter.lifetime0, emitter.lifetime1);

        color_t := random_get_within_range(0, 1);
        p.color = lerp(emitter.color0, emitter.color1, color_t);

        speed := random_get_within_range(emitter.speed0, emitter.speed1);
        theta := random_get_within_range(emitter.theta0, emitter.theta1);

        ct := cos(theta);
        st := sin(theta);

        v_rel: Vector2 = ---;
        v_rel.x = speed * ct;
        v_rel.y = speed * st;

        p.velocity += v_rel;

        return p;
    }

    if emitter.producing then {
    	if emitter.enabled {
    		while emitter.remainder > dt_per_particle {
	            emitter.remainder -= dt_per_particle;
	            p := spawn_particle(emitter);
	            sim_particle(p, emitter.remainder);
	        }
    	}
    } else {
        if emitter.particles.count == 0 then {
            destroy(emitter);
        }
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
    for terminal_cmds {
        count := begins_with_count(it.text, input);
        if count == input.count {
            array_add(*results, it.text);
            longest_match_length = max(longest_match_length, input.count);
        }
        longest_match_length = max(longest_match_length, count);
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

	//register_cmd("test", (args: .. Any) { print("CMD test args=%\n", args); });
	register_cmd("toggle_ui", (args: .. Any) { debug_ui_enabled = !debug_ui_enabled; });
	register_cmd("toggle_mute", (args: .. Any) { toggle_mute(); });
	register_cmd("fps", (args: .. Any) {  config.fps = ifx config.fps == -1 then 144 else -1; });

	register_cmd("help", (args: .. Any) {
		print("Registered Commands\n");
		for terminal_cmds {
			print("\t%\n", it.text);
		}
	});

	register_cmd("set_plugin", (args: .. Any) { 
		if args.count == 1 {
			arg := args[0];
			name := tprint("%", arg);
			set_plugin(name); 
		}
	});
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

#load "assets.jai";
