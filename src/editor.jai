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

start_level :: "hub";
editor_level : Level;
editor_camera : Camera;
dirty := false;
level_to_load := "b";

GRID_SIZE :: 32.;
grid_cell_size := GRID_SIZE;
cursor_size := 1;
cursor_snap_to_grid := true;
cursor_box := Box.{0,0, GRID_SIZE/2., GRID_SIZE/2.};

// UI 
subwindow_info_level 	: Subwindow_Info;
subwindow_info_tools 	: Subwindow_Info;
subwindow_info_details 	: Subwindow_Info;


editor_init :: () {
	print("~~~ Editor init ~~~\n");

	register_tool(*tool_selection);
	register_tool(*tool_actor);
	register_tool(*tool_tilemap);
	tool = *tool_selection; //default

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
        r := get_rect(0, window_height/2., 300, 400);
        subwindow_info_details.rect = r;
        subwindow_info_details.draw = draw_subwindow_details;
        subwindow_info_details.title_text = "Details";
    }

	editor_begin();
}

editor_deinit :: () {
	print("~~~ Editor Deinit ~~~ Level=%\n", editor_level.name);
	level_reset(*editor_level);

	clear_selection();
	for tool_options {
		string_reset(*it);
	}
	array_reset(*tool_options);
	array_reset_keeping_memory(*tools);
	tool_index = 0;
}

editor_begin :: () {
	print("~~~ Editor Begin ~~~ start_level=% | editor_level=%\n", start_level, editor_level.name);

	if is_valid_level_name(start_level) {
		editor_load(start_level);
	}
	else {
		editor_new_level(start_level);
	}

	editor_camera.position = .{0,0};
	editor_camera.zoom = 1;
}

editor_end :: () { /*@TODO unused currently*/ }

editor_tick :: (dt : float) {
	// update ui hit tests
	//@TODO there's probably a better global way to check for UI hits
	update_ui_hit(*subwindow_info_tools.rect);
	update_ui_hit(*subwindow_info_level.rect);
	update_ui_hit(*subwindow_info_details.rect);

	// cursor updates
	mv := vec_window_to_editor(mouse_pos_window);
	cp := to_editor_grid(mv);
	cursor_box.x = cp.x;
	cursor_box.y = cp.y;

	// tool keybind/init mapping
	//@HACK we're skipping these keybinds when ui_hit. It's just so we don't
	// do tool keybinds when we're typing in text input fields. 
	if !ui_hit_this_frame {
		for t : tools {
			if is_input_pressed(t.key){
				set_tool(xx it_index);
			}
		}
	}

	if tool.proc_tick tool.proc_tick(tool, dt);

	// camera panning, @TODO smooth this translation out
	if is_input_released(.MOUSE_BUTTON_RIGHT) {
		editor_camera.position = vec_window_to_editor(mouse_pos_window);
	}

	//@OPTIMIZE mouse wheel, grabbing the raw input event, not sure how else to get this mouse wheel
	for event : events_this_frame {
		if event.wheel_delta > 0 editor_camera.zoom += 0.1;
		if event.wheel_delta < 0 editor_camera.zoom = clamp(editor_camera.zoom-0.1, 0.05, editor_camera.zoom);
    }

    // move selections
    if is_input_pressed(.ARROW_UP)  	editor_selection_move(.{0,GRID_SIZE});
	if is_input_pressed(.ARROW_DOWN)  	editor_selection_move(.{0,-GRID_SIZE});
	if is_input_pressed(.ARROW_RIGHT)  	editor_selection_move(.{GRID_SIZE, 0});
	if is_input_pressed(.ARROW_LEFT) 	editor_selection_move(.{-GRID_SIZE, 0});

	// save
	if is_input_pressed(83 /*s*/) && input_mod_ctrl { editor_save(); }

	if is_input_pressed(.F5) {
		set_plugin("game");
		return;
	}
}

editor_render :: (dt : float) {
	origin := vec_editor_to_window(.{0,0});
	scale := Vector2.{editor_camera.zoom, editor_camera.zoom};
	grid_cell_size = scalar_to_window(GRID_SIZE) * editor_camera.zoom;
	line := scalar_to_window(4) * editor_camera.zoom;

	//grid
	{
		// vertical lines
		nv := 100;
		for -nv..nv {
			pos := Vector2.{grid_cell_size*it+origin.x, window_center.y};
			th := ifx it%5 == 0 then 4. else 1.;
			size := Vector2.{th, xx window_height};
			c := ifx it==0 then GREEN else GREY;
			draw_square(pos, size, c);
		}
		// horizontal lines
		nh := 100;
		for -nh..nh {
			pos := Vector2.{window_center.x, grid_cell_size*it+origin.y};
			th := ifx it%5 == 0 then 4. else 1.;
			size := Vector2.{xx window_width, th};
			c := ifx it==0 then RED else GREY;
			draw_square(pos, size, c);
		}
	}

	// tilemap
	//@TODO move to gfx.jai when its ready
	{
		slice : u8 = 0;
		for grid : editor_level.tilegrid.layers {
			for entry : grid {
				assert(entry.id != 0, "id=% [%,%]", entry.id, it_index.x, it_index.y);

				pos_in_grid := get_pos_in_tilegrid(*editor_level.tilegrid, it_index.x, it_index.y);
				pos := vec_editor_to_window(pos_in_grid);
				draw_tilemap(entry.id, entry.slice, pos, scale);
			}
		}

		//debug rendering
		draw_circle(origin, 25, color=MAGENTA);
	}

	
	// draw spawners
	for editor_level.spawners {
		sprite := get_sprite(it.type);
		pos := vec_editor_to_window(it.position);
		draw_sprite(sprite, pos, scale);
	}

 	// cursor
	if !ui_hit_this_frame {
		color := ifx input_mod_ctrl then RED else ifx input_mod_shift then ORANGE else YELLOW;
		cp := vec_editor_to_window(Vector2.{cursor_box.x, cursor_box.y});
		draw_box(.{cp.x, cp.y, grid_cell_size, grid_cell_size}, color, line);
	}
	
	if tool.proc_render tool.proc_render(tool, dt);

	//~~~~ UI v2 ~~~~~
	win_theme := hud_theme.subwindow_theme;
    if subwindow_info_level.open  subwindow_state := add_subwindow(*subwindow_info_level, *win_theme);
    if subwindow_info_tools.open  subwindow_state := add_subwindow(*subwindow_info_tools, *win_theme);
    if subwindow_info_details.open  subwindow_state := add_subwindow(*subwindow_info_details, *win_theme);

    draw_popups();
}

level_input_id := 0;

draw_subwindow_level :: (state: *Subwindow_State, r: Rect, data: *void) {
	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	{// level name 
		r0 := Rect.{r.x, r.y+r.h-lh, r.w/2., lh};
		level_name := tprint("Name: % %", editor_level.name, ifx dirty then "[*]" else "");
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
			level_to_load = "";
			level_input_id += 1;
		}

		r1 := Rect.{r0.x+r0.w, r0.y, bw, r0.h};
		if button(r1, "New", *hud_theme.button_theme) { 
			editor_new_level(level_to_load); 
			level_to_load = "";
			level_input_id += 1;
		}

		text_theme := hud_theme.text_input_theme;
		text_theme.alignment = .Left;
		text_theme.font = hud_font;

		r2 := Rect.{r1.x+r1.w, r1.y, bw*2, r1.h};
		action, text, state := text_input(r2, level_to_load, *text_theme, identifier=level_input_id);
		level_to_load = state.text;
		line += 1;
	}
}

draw_subwindow_details :: (state: *Subwindow_State, r: Rect, data: *void) {
	if tool.proc_render_details {
		tool.proc_render_details(tool, state, r, data);
	}
}

editor_reset :: () {
	clear_selection();
}

editor_save :: () {
	level_save(*editor_level);
	dirty = false;
}

editor_load :: (name : string) {
	if !is_valid_level_name(name) {
		print("Failed to load, level name [%] did not exist\n", name);
		return;
	}

	if is_valid(*editor_level) level_reset(*editor_level);

	success := level_load(name, *editor_level);

	if success  {
		dirty = false;
		editor_reset();
	}
}

editor_reload :: () {
	name := tprint("%", editor_level.name);
	editor_load(name);
}

editor_new_level :: (name : string) {
	if is_valid_level_name(name) {
		print("Level name already exists [%]\n", name);
		return;
	}

	if is_valid(*editor_level) {
		level_reset(*editor_level);
	}

	editor_level.name = sprint(name);
	dirty = true;
	editor_reset();
	print("Editting new level: %\n", editor_level.name);
}

vec_editor_to_window :: (v : Vector2) -> Vector2 {
	result := v - editor_camera.position;
	scale := get_window_aspect_scale() * editor_camera.zoom;
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
	scale := get_window_aspect_scale() * editor_camera.zoom;
	result.x /= scale;
	result.y /= scale;
	result = result + editor_camera.position;
	return result;
}

to_editor_grid :: (pos : Vector2) -> Vector2 {
	if !cursor_snap_to_grid return pos;

	result : Vector2;
	gx := cast(s64)(pos.x / GRID_SIZE);
	gx2 : float = ifx pos.x >= 0 then gx + 0.5 else gx - 0.5;
	gx2 *= GRID_SIZE;
	result.x = gx2;

	gy := cast(s64)(pos.y / GRID_SIZE);
	gy2 : float = ifx pos.y >= 0 then gy + 0.5 else gy - 0.5;
	gy2 *= GRID_SIZE;
	result.y = gy2;

	return result;
}

editor_spawner_add :: (spawner : ActorSpawner) {
	array_add(*editor_level.spawners, spawner);
	dirty = true;
}

editor_spawner_delete :: (area : Box) {
	for < editor_level.spawners {
		spawner := it;
		if is_in_box(spawner.position, area) {
			print("DELETE: %\n", spawner);
			array_unordered_remove_by_index(*editor_level.spawners, it_index);
			spawner_reset(*spawner);
		}
	}
	dirty = true;
}

is_occupied :: (area : Box) -> bool{
	for editor_level.spawners {
		if is_in_box(it.position, area) {
			return true;
		}
	}
	return false;
}

editor_spawner_move :: (spawner : *ActorSpawner, pos : Vector2) {
	spawner.position = to_editor_grid(pos);
	dirty = true;
}

editor_selection_move :: (dv : Vector2) {
	if ui_hit_this_frame return;

	for selected_spawner_idxs {
		spawner := get_selection(it_index);
		pos := spawner.position + dv;
		editor_spawner_move(spawner, pos);
	}
}

// ~~~~~~ TOOLS ~~~~~~

draw_subwindow_tools :: (state: *Subwindow_State, r: Rect, data: *void) {
	// active tool info
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	r0 := Rect.{r.x, r.y+r.h-lh, r.w, lh};
    {
 	   	dropdown(r0, tool_options, *tool_dropdown_index, *hud_theme.dropdown_theme);
 		set_tool(tool_dropdown_index);
    }

    // tool sub-section
    r1 := Rect.{r.x,r.y, r.w, r.h-r0.h};
	if tool.proc_render_subwindow tool.proc_render_subwindow(tool, state, r1, data);
}

EditorTool :: struct {
	name : string;
	key : Key_Code;

	proc_init : EditorToolProc;
	proc_tick : EditorToolProc_Tick;
	proc_render : EditorToolProc_Render;
	proc_render_subwindow : EditorToolProc_RenderSubWindow;
	proc_render_details : EditorToolProc_RenderSubWindow;
}

EditorToolProc :: #type (t : *EditorTool);
EditorToolProc_Tick :: #type (t : *EditorTool, dt : float);
EditorToolProc_Render :: #type (t : *EditorTool, dt : float);
EditorToolProc_RenderSubWindow :: #type (t : *EditorTool, state: *Subwindow_State, r: Rect, data: *void);

tool : *EditorTool;
tools : [..] *EditorTool;
tool_options : [..] string;
tool_index : s32; //actively selected tool
tool_dropdown_index : s32 = 0; //pointer used for dropdown

register_tool :: (tool : *EditorTool) {
	assert(tool != null);

	array_add(*tools, tool);
	tool_text := sprint("%", tool.name);
	array_add(*tool_options, tool_text);
}

set_tool :: (index : s32) {
	if tool_index == index return;

	tool = tools[index];
	tool_index = index;
	tool_dropdown_index = tool_index;
	print("Tool set to [%]\n", tool.name);

	if tool.proc_init tool.proc_init(tool);
}

// ~~~~ Actor Spawner Tool ~~~~

EditorTool_Actor :: struct {
	#as using tool : EditorTool;

	actor_type := ActorType.Block;
}

tool_actor := EditorTool_Actor.{
	name = "Actors",
	key = 65, /*a*/

	proc_init = tool_actor_init,
	proc_tick = tool_actor_tick,
	proc_render = tool_actor_render,
	proc_render_subwindow = tool_actor_render_subwindow,
	proc_render_details = tool_actor_render_details,
};

tool_actor_init :: (tool : *EditorTool) {
	assert(tool != null);
	atool := cast(*EditorTool_Actor) tool;
	atool.actor_type = .Block;

	print("\ttool actor: name=%\n", atool.name);
	print("\ttool actor: key=%\n", atool.key);
	print("\ttool actor: type=%\n", atool.actor_type);
}

tool_actor_tick :: (t : *EditorTool, dt : float) {
	if ui_hit_this_frame return;

	atool := cast(*EditorTool_Actor) t;

	if is_input_down(.MOUSE_BUTTON_LEFT) {
		// delete
		if input_mod_ctrl {
			editor_spawner_delete(cursor_box);
			return;
		}
		// add
		else {
			if !is_occupied(cursor_box) {
				editor_spawner_add(ActorSpawner.{
						atool.actor_type, 
						.{cursor_box.x, cursor_box.y}, 
						.{1,1},
						"",
					} 
				);
			}
		}
	}

	//@TODO [SHIFT] get selection, fill on release
}

tool_actor_render :: (t : *EditorTool, dt : float) {}

tool_actor_render_subwindow :: (t : *EditorTool, state: *Subwindow_State, r: Rect, data: *void) {
	atool := cast(*EditorTool_Actor) t;

	// actor type label
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	rlabel := Rect.{r.x, r.y+r.h-lh, r.w, lh};
	actor := tprint("Actor Type: %", atool.actor_type);
	theme : = hud_theme.label_theme;
	theme.alignment = .Left;
    label(rlabel, actor, *theme);

    // actor pallet, draw buttons for each
    COLUMNS :: 4;
    AB :: 64.;
    root := Rect.{r.x, rlabel.y, AB, AB};
    index := 0;

    // actor buttons
	for enum_values_as_s64(ActorType) {
		type := cast(ActorType)it;

		if !is_valid_actor_spawner(type) continue;

		//@TODO render this button with the sprite
		tex := get_texture("T_world_entrance"); //default
		
		if type== {
			//case .Hero; 		return get_sprite("S_hero");
			//case .HeroRed; 		return get_sprite("S_hero_red");
			case .Kid; 			tex = get_texture("T_bug_preview");
//
			//case .WorldEntrance; return get_sprite("S_world_entrance");
			//case .WorldExit; 	return get_sprite("S_world_exit");
//
			//case .Block; 		return get_sprite("S_block");
//
			case .Console; 		tex = get_texture("T_button_sq_green_preview");
			case .ConsoleMovable; tex = get_texture("T_button_c_green_preview");
			//case .WallLock; 	return get_sprite("S_lock_green");
			//case .WallLockBig; 	return get_sprite("S_lock_big");
//
			//case .DropZone; 	return get_sprite("S_zone_drop");
			//case .TimerResetA; 	return get_sprite("S_zone_reset_green");
//
			//case .Sign; 	return get_sprite("S_sign");
		}
		assert(tex != null);
		
    	rbtn := Rect.{0,0, AB,AB};
    	col := (index % COLUMNS) * AB;
    	rbtn.x = root.x + col;
    	row := (index / COLUMNS) * AB;
    	rbtn.y = root.y - row - rbtn.h;
    	if button(rbtn, "", *hud_theme.button_theme, texture=*tex.texture, identifier=it) {
    		atool.actor_type = type;
	    }
	    index +=1;
    }
}

tool_actor_render_details :: (t : *EditorTool, state: *Subwindow_State, r: Rect, data: *void)  {
	root := r;
	th := hud_theme.label_theme;
	th.alignment = .Left;
	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	count := selected_spawner_idxs.count;

	{ // selection count
		r0 := Rect.{root.x, root.y+root.h-lh, root.w, lh};
		text := tprint("Selecting % spawners", count);
    	label(r0, text, *th);
    	root.h -= r0.h;
	}

	// display the first selection
	if count > 0 {
		spawner := get_selection();

		r0 := Rect.{root.x, root.y+root.h-lh, root.w, lh};
		text := tprint("ActorType: %", spawner.type);
    	label(r0, text, *th);
    	root.h -= r0.h;

    	r0 = Rect.{root.x, root.y+root.h-lh, root.w, lh};
		text = tprint("Position: %", spawner.position);
    	label(r0, text, *th);
    	root.h -= r0.h;

    	r0 = Rect.{root.x, root.y+root.h-lh, root.w*.25, lh};
		text = tprint("Data:");
    	label(r0, text, *th);

    	r0 = Rect.{root.x+root.w*.25, root.y+root.h-lh, root.w*.75, lh};
    	preview := tprint(spawner.data);
    	action, data_text, state := text_input(r0, preview, *hud_theme.text_input_theme);
    	if action & .ENTERED  {
    		reset(state);
    		string_reset(*spawner.data);
			spawner.data = sprint(data_text);
			dirty = true;
    	}
    	root.h -= r0.h;
	}
}



// ~~~~ Selection Tool ~~~~

tool_selection := EditorTool.{
	name = "Selection",
	key = 86 /*v*/,
	proc_tick = tool_selection_tick,
	proc_render = tool_selection_render,
	proc_render_subwindow = tool_selection_render_subwindow,
	proc_render_details = tool_actor_render_details,
};

selected_spawner_idxs : [..] s64;
selection_box : Box;
selection_start : Vector2;
selection_end : Vector2;

get_selection :: (index := 0) -> *ActorSpawner {
	if selected_spawner_idxs.count == 0 return null;
	if index < 0 || index >= selected_spawner_idxs.count return null;

	spawner_idx := selected_spawner_idxs[index];
	return *editor_level.spawners[spawner_idx];
}

has_selection :: () -> bool {
	return selected_spawner_idxs.count > 0;
}

clear_selection :: () {
	array_reset(*selected_spawner_idxs);
	selection_box = Box.{};
}

tool_selection_tick :: (t : *EditorTool, dt : float) {
	if ui_hit_this_frame return;

	// begin selection
	if is_input_pressed(.MOUSE_BUTTON_LEFT) {
		if !input_mod_shift && !input_mod_ctrl{
			clear_selection();
		}
		selection_box = cursor_box;
		selection_start = Vector2.{cursor_box.x, cursor_box.y};
		selection_end = selection_start;
	}
	// update selection box
	else if is_input_down(.MOUSE_BUTTON_LEFT) {
		selection_end = Vector2.{cursor_box.x, cursor_box.y};
		selection_box.x = selection_start.x + (selection_end.x-selection_start.x)/2.;
		selection_box.y = selection_start.y + (selection_end.y-selection_start.y)/2.;
		selection_box.w = abs((selection_end.x-selection_start.x)) + GRID_SIZE;
		selection_box.h = abs((selection_end.y-selection_start.y)) + GRID_SIZE;
	}

	// complete selection
	if is_input_released(.MOUSE_BUTTON_LEFT) {
		for editor_level.spawners {
			if is_in_box(it.position, selection_box) {
				if input_mod_ctrl { // delete
					array_unordered_remove_by_value(*selected_spawner_idxs, it_index);
				}
				else { // add
					selected_jdx := 0;
					for j, jdx : selected_spawner_idxs {
						if j < it_index {
							selected_jdx = jdx;
							break;
						}
					}
					array_insert_at(*selected_spawner_idxs, it_index, selected_jdx);
				}
			}
		}
		selection_box = Box.{};
	}

	if is_input_pressed(.DELETE) {
		if has_selection() {
			for selected_spawner_idxs {
				array_unordered_remove_by_index(*editor_level.spawners, it);
			}
			clear_selection();
			dirty = true;
		}
	}
}

tool_selection_render :: (t : *EditorTool, dt : float) {
	 // selection box 
	sp := vec_editor_to_window(Vector2.{selection_box.x, selection_box.y});
	w := scalar_to_window(selection_box.w) * editor_camera.zoom;
	h := scalar_to_window(selection_box.h) * editor_camera.zoom;
	line := scalar_to_window(4) * editor_camera.zoom;
	draw_box(.{sp.x, sp.y, w, h}, CYAN, line);

	// active selection
	for < selected_spawner_idxs {
		spawner := editor_level.spawners[it];
		sp := vec_editor_to_window(spawner.position);
		color := ifx it_index == 0 then MAGENTA else MAGENTA*0.50;
		color.w = 1;
		draw_box(.{sp.x, sp.y, grid_cell_size, grid_cell_size}, color, line*0.5);
	}
}

tool_selection_render_subwindow :: (t : *EditorTool, state: *Subwindow_State, r: Rect, data: *void) {
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	theme : = hud_theme.label_theme;
	theme.alignment = .Left;
	{
		r0 := Rect.{r.x, r.y+r.h-lh, r.w, lh};
		text := tprint("Cursor: %", Vector2.{cursor_box.x, cursor_box.y});
	    label(r0, text, *theme);

	    r0.y -= lh;
		text = tprint("Selection: %", selection_box);
	    label(r0, text, *theme);
	}
	
	if has_selection() {
		for selected_spawner_idxs {
			spawner := editor_level.spawners[it];
			line := 3+it_index;
			r0 := Rect.{r.x, r.y+r.h-lh*line, r.w, lh};
			text := tprint("Selection: % [%]", spawner.type, spawner.position);
	    	label(r0, text, *theme);
		}
	}
}


// ~~~~ Tilemap Tool ~~~~

EditorTool_Tilemap :: struct {
	#as using tool : EditorTool;
	selected_layer := 0;
	selected_tiletype := 0;
}

tool_tilemap := EditorTool_Tilemap.{
	name = "Tilemap",
	key = 84, /*t*/

	proc_init = tool_tilemap_init,
	proc_tick = tool_tilemap_tick,
	proc_render = tool_tilemap_render,
	proc_render_subwindow = tool_tilemap_render_subwindow,
	//proc_render_in_details = tool_render_in_details_tilemap, @CLEAN
};

tool_tilemap_init :: (t : *EditorTool) {
	assert(t != null);
	tmtool := cast(*EditorTool_Tilemap)t;
	tmtool.selected_layer = 0;
	tmtool.selected_tiletype = 1;
}

tool_tilemap_tick :: (t : *EditorTool, dt : float) {
	if ui_hit_this_frame return;

	tmtool := cast(*EditorTool_Tilemap) t;
	assert(tmtool != null);
	tg := *editor_level.tilegrid;

	if is_input_down(.MOUSE_BUTTON_LEFT) {
		layer := tmtool.selected_layer;
		// delete
		if input_mod_ctrl {
			log("delete: layer=%", layer);

			pos := Vector2.{cursor_box.x, cursor_box.y};
			if is_pos_in_tilegrid(tg, pos) {
				x,y := get_tilegrid_coords_from_pos(tg, pos);
				erase_tilegrid_cell(tg, layer, x, y);
			}
		}
		// add
		else {
			pos := Vector2.{cursor_box.x, cursor_box.y};
			if is_pos_in_tilegrid(tg, pos) {
				x,y := get_tilegrid_coords_from_pos(tg, pos);
				set_tilegrid_cell(tg, layer, x, y, tmtool.selected_tiletype);

				entry := get_tilegrid_entry(tg, layer, x, y);
				log("paint: layer=% tile=% pos=% entry=%", layer, tmtool.selected_tiletype, pos, entry);
			}
		}
	}
}

tool_tilemap_render :: (t : *EditorTool, dt : float) {}

tool_tilemap_render_subwindow :: (t : *EditorTool, state: *Subwindow_State, r: Rect, data: *void) {
	tmtool := cast(*EditorTool_Tilemap)t;
	//tg : *TileGrid = editor_level.tilegrid;

	lh := cast(float)hud_font_pixel_height+4.;
	layout := VerticalLayout.{ root=.{r.x, r.y, r.w, lh} };

	ui_label(*layout, "Position: %", editor_level.tilegrid.position);
	ui_line(*layout);

	slider(ui_next(*layout), *tmtool.selected_layer, 0, editor_level.tilegrid.layers.count-1, 1, *hud_theme.slider_theme, "Edit Layer: ", "");
	ui_line(*layout);
	
	ui_label(*layout, "Selected TileMap: %", tmtool.selected_tiletype);

	for tilemaps {
		txt := tprint("Tilemap: %/%", it_index, it.texture_guid);
		if button(ui_next(*layout), txt, identifier=it_index) {
			log("tiel selected %", it);
			tmtool.selected_tiletype = it_index;
		}
	}
}

tool_tilemap_select_layer_up :: (tool : *EditorTool_Tilemap) {
	tool.selected_layer += 1;
	if tool.selected_layer >= editor_level.tilegrid.layers.count
		tool.selected_layer = 0;
}

tool_tilemap_select_layer_down :: (tool : *EditorTool_Tilemap) {
	tool.selected_layer -= 1;
	if tool.selected_layer < 0
		tool.selected_layer = editor_level.tilegrid.layers.count-1;
}

