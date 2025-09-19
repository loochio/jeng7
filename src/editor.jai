// editor.jai - Game F
// Editor v2 - 19 Sept 2025


editor_plugin := EnginePlugin.{
	name = "editor",
	proc_init 	= editor_init,
	proc_deinit = editor_deinit,
	proc_begin 	= editor_begin,
	proc_end 	= editor_end,
	proc_tick 	= editor_tick,
	proc_render = editor_render,
};

start_level :: "level_01";
editor_level : Level;


GRID_SIZE :: 32.;
cursor_size := 1;
cursor_snap_to_grid := true;
cursor_in_deadzone := false;
cursor_position : Vector2;
prev_placement : Vector2;
dirty := false;
deadzone : Vector2;
editor_camera : Camera;
warp_level_name := "b";

// UI v2
subwindow_info_level 	: Subwindow_Info;
subwindow_info_tools 	: Subwindow_Info;
subwindow_info_details 	: Subwindow_Info;

level_to_load := "b";


//@CLEAN
//EditorToolType :: enum u8 {
//	Actor;
//	EraseSpawner; //@TODO remove
//	HeroSpawner;  // player start pos
//	Warps;		  // level transitions
//}

//tool := EditorToolType.Actor;

EditorTool :: struct {
	name : string;
	proc_tick : EditorToolProc_Tick;
	proc_render : EditorToolProc_Render;
	proc_render_in_subwindow : EditorToolProc_RenderSubWindow;
}

EditorToolProc_Tick :: #type (dt : float);
EditorToolProc_Render :: #type (dt : float);
EditorToolProc_RenderSubWindow :: #type (state: *Subwindow_State, r: Rect, data: *void);

active_tool : EditorTool = tool_actor;

//@CLEAN put in actor tool
//actor_to_spawn : ActorType;

editor_init :: () {
	print("~~~ Editor init ~~~\n");

	register_cmd("save", (args: .. Any) { editor_save(); });
	register_cmd("load", (args: .. Any) { 
		if args.count == 1 {
			arg := args[0];
			path := tprint("%", arg);
			editor_load(path); 
		}
	});
	register_cmd("new", (args: .. Any) { 
		if args.count == 1 {
			arg := args[0];
			name := tprint("%", arg);
			editor_new_level(name); 
		}
	});
	register_cmd("reload", (args: .. Any) { editor_reload(); }); 
	register_cmd("edit_clear", (args: .. Any) { editor_erase_spawners(); } );
	register_cmd("load_prev", (args: .. Any) { 
		//editor_load(prev_level_name); //@CLEAN
	} );


	// Init subwindow UI
	{ // level 
        r := get_rect(0, xx (window_height-120), 600, 120);
        subwindow_info_level.rect = r;
        subwindow_info_level.draw = draw_subwindow_level;
        subwindow_info_level.title_text = "Level";
    }
    { // tools
        r := get_rect(0, 0, 300, window_height/2.);
        subwindow_info_tools.rect = r;
        subwindow_info_tools.draw = draw_subwindow_tools;
        subwindow_info_tools.title_text = "Tools";
    }
    { // details 
        r := get_rect(xx (window_width-300), xx (window_height-300), 300, 300);
        subwindow_info_details.rect = r;
        subwindow_info_details.draw = draw_subwindow_details;
        subwindow_info_details.title_text = "Details";
    }

	editor_begin();
}

editor_deinit :: () {
	print("~~~ Editor Deinit ~~~ Level=%\n", editor_level.name);
	level_reset(*editor_level);
}

editor_begin :: () {
	print("~~~ Editor Begin ~~~ start_level=% | editor_level=%\n", start_level, editor_level.name);
	editor_load(start_level);
	editor_camera.position = .{0,0};
}

editor_end :: () { /*@TODO unused currently*/ }

editor_tick :: (dt : float) {
	//@TODO remove deadzone concept
	deadzone.x = window_width*0.15;
	deadzone.y = xx window_height;
	cursor_in_deadzone = is_cursor_deadzone(mouse_pos_window);

	if !cursor_in_deadzone {
		mv := vec_window_to_editor(mouse_pos_window);
		if cursor_snap_to_grid {
			gx := cast(s64)(mv.x / GRID_SIZE);
			gx2 : float = ifx mv.x >= 0 then gx + 0.5 else gx - 0.5;
			cursor_position.x = gx2 * GRID_SIZE;

			gy := cast(s64)(mv.y / GRID_SIZE);
			gy2 : float = ifx mv.y >= 0 then gy + 0.5 else gy - 0.5;
			cursor_position.y = gy2 * GRID_SIZE;
		}
		else {
			cursor_position = mv;
		}

		active_tool.proc_tick(dt);

		//@CLEAN
		//if is_input_pressed(.MOUSE_BUTTON_LEFT) active_tool.proc();

		/*
		if is_input_pressed(.MOUSE_BUTTON_LEFT) 
			|| (is_input_down(.MOUSE_BUTTON_LEFT) && is_input_down(.SHIFT))
		{
			if tool== {
				case .Actor; {
					if prev_placement != cursor_position {
						prev_placement = cursor_position;
						spawner := ActorSpawner.{actor_to_spawn, cursor_position};
						array_add(*editor_level.spawners, spawner);
						dirty = true;
					}
				}
				case .EraseSpawner; {
					// find last actor around cursor, delete
					//@TODO this will miss if our actor isn't snapped to grid
					for i: 0..editor_level.spawners.count-1 {
						sp := *editor_level.spawners[i];
						if is_in_circle(cursor_position, sp.position, GRID_SIZE) {
							array_unordered_remove_by_index(*editor_level.spawners, i);
							dirty = true;
							break;
						}
					}
				}
				case .HeroSpawner;{
					if prev_placement != cursor_position {
						prev_placement = cursor_position;
						array_add(*editor_level.hero_spawn_points, cursor_position);
						dirty = true;
					}
				}
				case .Warps;{
					//@TODO check .level file exists
					warp := WarpSpawner.{ cursor_position, warp_level_name };
					array_add(*editor_level.warps, warp);
					dirty = true;
				}
			}
		}
		else if is_input_released(.MOUSE_BUTTON_LEFT) {
			prev_placement = .{99999,99999}; //random big number that we'll never collide with
		}
		*/
		if is_input_released(.MOUSE_BUTTON_LEFT) {
			prev_placement = .{99999,99999}; //random big number that we'll never collide with
		}
	}

	// tool selects, @CLEAN
	//if is_input_pressed(49) tool = .PlaceSpawner;
	//else if is_input_pressed(50) tool = .EraseSpawner;
	//else if is_input_pressed(51) tool = .HeroSpawner;
	//else if is_input_pressed(52) tool = .Warps;

	EDITOR_CAM_SPEED :: 5.;
	if is_input_down(.ARROW_UP) 		editor_camera.position.y += EDITOR_CAM_SPEED;
	if is_input_down(.ARROW_DOWN) 		editor_camera.position.y -= EDITOR_CAM_SPEED;
	if is_input_down(.ARROW_RIGHT) 		editor_camera.position.x += EDITOR_CAM_SPEED; 
	if is_input_down(.ARROW_LEFT) 		editor_camera.position.x -= EDITOR_CAM_SPEED;

	//@CLEAN actor type
	//@TODO need to pull from a valid list of spawnable actors
	//low, high := enum_range(ActorType);
	//if is_input_pressed(.PAGE_UP) {
	//	actor_to_spawn = ifx actor_to_spawn == xx high then xx low else actor_to_spawn+1;
	//}
	//if is_input_pressed(.PAGE_DOWN) {
	//	actor_to_spawn = ifx actor_to_spawn == xx low then xx high else actor_to_spawn-1;
	//}

	// save
	if is_input_pressed(83 /*s*/) && is_input_down(.CTRL) {
		editor_save();
	}

	if is_input_pressed(.F5) {
		set_plugin("game");
		return;
	}
}

editor_render :: (dt : float) {
	origin := vec_editor_to_window(.{0,0});

	//grid
	size := scalar_to_window(GRID_SIZE);
	g :: 20;
	for i: -g*2..g*2 {
		for j: -g..g {
			draw_box(.{origin.x+ size*i+size/2, origin.y + size*j+size/2, size, size}, G_BLACK);
		}
	}

	// draw spawners
	for editor_level.spawners {
		sprite := get_actor_sprite(it.type);
		pos := vec_editor_to_window(it.position);
		render_sprite(sprite, pos);
	}
	// hero spawn points, RED = index 0
	for editor_level.hero_spawn_points {
		pos := vec_editor_to_window(it);
		r := GRID_SIZE;
		c := lerp(RED, GREEN, it_index/cast(float)editor_level.hero_spawn_points.count);
		draw_circle(pos, r, r-8, color=c);
		sprite := get_actor_sprite(.Hero);
		render_sprite(sprite, pos);
	}

	// warps
	for editor_level.warps {
		pos := vec_editor_to_window(it.position);
		r := 12.;
		draw_circle(pos, r, r-8, color=GREEN);
	}

	//cursor
	cp := vec_editor_to_window(cursor_position);
	draw_box(.{cp.x, cp.y, size, size}, ifx cursor_in_deadzone then BLACK else YELLOW, 8);



	//~~~~ UI (old) ~~~~~

	/*
	//deadzone
	draw_square(.{deadzone.x/2, deadzone.y/2}, .{deadzone.x, deadzone.y}, G_PURPLE);

	draw_text :: (line : s64, format_string: string, args: .. Any) {
		text := tprint(format_string, ..args);
		text_width := prepare_text(hud_font, text);
	    text_y := window_height - hud_font.character_height * line;
	    draw_prepared_text(hud_font, 0, text_y, G_WHITE);
	}
	draw_text(1, "Level: % %", editor_level.name, ifx dirty then "[DIRTY]" else "");
	draw_text(2, "Cursor=%", cursor_position);
	draw_text(4, "Tool=%", tool);
	draw_text(5, "ActorType=%", actor_to_spawn);
	draw_text(6, "Spawners=%", editor_level.spawners.count);
	draw_text(7, "Hero Spawn Points=%", editor_level.hero_spawn_points.count);
	draw_text(8, "warps=%", editor_level.warps);

	draw_text(9, "cam=%", editor_camera.position);
	draw_text(10, "origin=%", origin);

	// UI buttons
    x := 10.;
    y := 10.;
    k := hud_font_pixel_height;
    w := k*8.;
    h : float = xx k;
    r := get_rect(x, y, w, h);
    if button(r, "Save", *hud_theme.button_theme) { editor_save(); }
    r = get_rect(x, y+k, w, h);
    if button(r, "Reload", *hud_theme.button_theme) { editor_reload(); }
    r = get_rect(x, y+k*2, w, h);
    if button(r, "Clear All", *hud_theme.button_theme) { 
    	editor_erase_spawners(); 
    	editor_erase_hero_spawns();
    }
    r = get_rect(x, y+k*3, w, h);
    if button(r, "Clear Hero Spawns", *hud_theme.button_theme) { editor_erase_hero_spawns(); }

    r = get_rect(x, y+k*4, w, h);
    if button(r, "Clear warps", *hud_theme.button_theme) { 
    	if editor_level.warps.data != null {
			array_reset(*editor_level.warps);
			dirty = true;
		}	
    }
	
	{ // warp name
		k := window_height * .1;
		w := deadzone.x;
		r := get_rect(0, xx window_height/2., w, hud_font.character_height*1.35);
		text_theme := hud_theme.text_input_theme;
		text_theme.alignment = .Left;
		text_theme.font = hud_font;
		action, new_value := text_input(r, warp_level_name, *text_theme);
		if action & .ENTERED  {
			warp_level_name = new_value;
			print("new warp: %\n", warp_level_name);
		}
	}

*/


	//@CLEAN debug orgin
	draw_circle(origin, 5, color=GREEN);


	//~~~~ UI v2 ~~~~~

    if subwindow_info_level.open {  // The Subwindow starts open, but pressing the Close button can close it.
        hud_theme.subwindow_theme.resize_controls |= .SNAP;
        subwindow_state := add_subwindow(*subwindow_info_level, *hud_theme.subwindow_theme);
        hud_theme.subwindow_theme.resize_controls &= ~.SNAP;
    }

    if subwindow_info_tools.open {  // The Subwindow starts open, but pressing the Close button can close it.
        hud_theme.subwindow_theme.resize_controls |= .SNAP;
        subwindow_state := add_subwindow(*subwindow_info_tools, *hud_theme.subwindow_theme);
        hud_theme.subwindow_theme.resize_controls &= ~.SNAP;
    }

    if subwindow_info_details.open {  // The Subwindow starts open, but pressing the Close button can close it.
        hud_theme.subwindow_theme.resize_controls |= .SNAP;
        subwindow_state := add_subwindow(*subwindow_info_details, *hud_theme.subwindow_theme);
        hud_theme.subwindow_theme.resize_controls &= ~.SNAP;
    }

    draw_popups();
}

draw_subwindow_level :: (state: *Subwindow_State, r: Rect, data: *void) {
	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	{// level name 
		r0 := Rect.{r.x, r.y+r.h-lh, r.w/2., lh};
		level_name := tprint("% %", editor_level.name, ifx dirty then "[*]" else "");
    	label(r0, level_name, *hud_theme.label_theme);
	}
	bw := r.w*.25;
	{ // save 
		r0 := Rect.{r.x+r.w/2., r.y+r.h-(lh*line), bw, lh};
		if button(r0, "Save", *hud_theme.button_theme) { editor_save(); }
	}
	if dirty { // clear/ reload 
		r0 := Rect.{r.x+r.w/2.+bw, r.y+r.h-(lh*line), bw, lh};
		if button(r0, "Clear", *hud_theme.button_theme) { editor_reload(); }
	}

    line += 1;
	{ // load 
		r0 := Rect.{r.x, r.y+r.h-(lh*line)-p, bw, lh};
		if button(r0, "Load", *hud_theme.button_theme) { 
			editor_load(level_to_load);
			level_to_load = ""; //@TODO this doesn't clear our input text, why?
		}

		r1 := Rect.{r0.x+r0.w, r0.y, bw, r0.h};
		if button(r1, "New", *hud_theme.button_theme) { 
			editor_new_level(level_to_load); 
			level_to_load = "";
		}

		text_theme := hud_theme.text_input_theme;
		text_theme.alignment = .Left;
		text_theme.font = hud_font;

		r2 := Rect.{r1.x+r1.w, r1.y, bw*2, r1.h};
		action, text, state := text_input(r2, level_to_load, *text_theme);
		level_to_load = state.text;
		line += 1;
	}
}


draw_subwindow_details :: (state: *Subwindow_State, r: Rect, data: *void) {
}

editor_save :: () {
	print("attempting to save...\n");
	level_save(*editor_level);
	dirty = false;
}

editor_load :: (name : string) {
	if !is_valid_level_name(name) {
		print("Failed to load, level name [%] did not exist\n", name);
		return;
	}

	//@TODO do we bake is_valid into the level_reset?
	if is_valid(*editor_level)
		level_reset(*editor_level);

	success := level_load(name, *editor_level);

	if !success  return;

	assert(name == editor_level.name, "name=% editor=%", name, editor_level.name);
	dirty = false;
}

editor_reload :: () {
	name := tprint("%", editor_level.name);
	editor_load(name);
}

editor_erase_spawners :: () {
	if editor_level.spawners.data != null {
		array_reset(*editor_level.spawners);
		dirty = true;
	}
}

editor_erase_hero_spawns :: () {
	if editor_level.hero_spawn_points.data != null {
		array_reset(*editor_level.hero_spawn_points);
		dirty = true;
	}
}

editor_new_level :: (name : string) {
	if is_valid_level_name(name) {
		print("Level name already exists [%]\n", name);
		return;
	}

	level_reset(*editor_level);
	editor_level.name = sprint(name);
	print("Editting new level: %\n", editor_level.name);
}

is_cursor_deadzone :: (pos : Vector2) -> bool {
	return pos.x < deadzone.x;
}

vec_editor_to_window :: (v : Vector2) -> Vector2 {
	result := v - editor_camera.position;
	scale := get_window_aspect_scale();
	scale *= editor_camera.zoom;
	result.x *= scale;
	result.y *= scale;
	result.x += window_width/2.;
	result.y += window_height/2.;
	return result;
}

vec_window_to_editor :: (v : Vector2) -> Vector2 {
	result := v;
	result.x -= window_width/2.;
	result.y -= window_height/2.;
	scale := get_window_aspect_scale();
	scale /= editor_camera.zoom;
	result.x /= scale;
	result.y /= scale;
	result = result + editor_camera.position;
	return result;
}

draw_subwindow_tools :: (state: *Subwindow_State, r: Rect, data: *void) {
	// active tool info
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	r0 := Rect.{r.x, r.y+r.h-lh, r.w, lh};
	name := tprint("Active Tool: %", active_tool.name);
    label(r0, name, *hud_theme.label_theme);

    r1 := Rect.{r.x,r.y, r.w, r.h-r0.h};
	active_tool.proc_render_in_subwindow(state, r1, data);
}

tool_actor :: EditorTool.{
	name = "Actors",
	proc_tick = tool_actor_tick,
	proc_render = tool_actor_render,
	proc_render_in_subwindow = tool_actor_render_in_subwindow,
};

tool_actor_selection : ActorType;

tool_actor_tick :: (dt : float) {
	if is_input_pressed(.MOUSE_BUTTON_LEFT) { 
		if prev_placement != cursor_position {
			prev_placement = cursor_position;
			spawner := ActorSpawner.{tool_actor_selection, cursor_position};
			array_add(*editor_level.spawners, spawner);
			dirty = true;
		}
	}
}

tool_actor_render :: (dt : float) {}

tool_actor_render_in_subwindow :: (state: *Subwindow_State, r: Rect, data: *void) {
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	r0 := Rect.{r.x, r.y+r.h-lh, r.w, lh};
	actor := tprint("Actor Type: %", tool_actor_selection);
	theme : = hud_theme.label_theme;
	theme.alignment = .Left;
    label(r0, actor, *theme);

    //@TODO loop through actor pallet, draw button
    COLUMNS :: 4;
    AB :: 64.;
    br := Rect.{r.y, r.y, AB, AB};
    root := Vector2.{r.x, r.y};
    index := 0;

	for enum_values_as_s64(ActorType) {
		type := cast(ActorType)it;

		if !is_valid_actor_spawner(type) continue;

		//@TODO render this button with the sprite
    	//sprite := get_actor_sprite(it.type);
    	textureid := get_actor_tid(type);
    	tex := *get_texture(textureid).texture;
    	assert(tex != null);
    	col := (index % COLUMNS) * AB;
    	br.x = root.x + col;
    	row := (index / COLUMNS) * AB;
    	br.y = root.y + row;
    	if button(br, "", *hud_theme.button_theme, texture=tex) {
    		tool_actor_selection = type;
	    }
	    index +=1 ;
    }
}

