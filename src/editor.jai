// editor.jai - Game F


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

EditorTool :: enum u8 {
	PlaceSpawner;
	EraseSpawner;
	HeroSpawner;
	Warps;
}

tool := EditorTool.PlaceSpawner;
actor_to_spawn : ActorType;

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

	editor_begin();
}

editor_deinit :: () {
	print("~~~ Editor Deinit ~~~ Level=%\n", editor_level.name);
	level_reset(*editor_level);
}

editor_begin :: () {
	print("~~~ Editor Begin ~~~ start_level=% | editor_level=%\n", start_level, editor_level.name);
	editor_load(start_level);
}

editor_end :: () {
	//@TODO unused currently
}

editor_tick :: (dt : float) {
	deadzone.x = window_width*0.15;
	deadzone.y = xx window_height;
	cursor_in_deadzone = is_cursor_deadzone(mouse_pos_window);

	if !cursor_in_deadzone {
		mp := mouse_pos_window; //@TODO reimplement
		//mp := coords_window_to_world(mouse_pos_window, *editor_camera);
		if cursor_snap_to_grid {
			gx := cast(s64)(mp.x / GRID_SIZE);
			gx2 : float = ifx mp.x >= 0 then gx + 0.5 else gx - 0.5;
			cursor_position.x = gx2 * GRID_SIZE;

			gy := cast(s64)(mp.y / GRID_SIZE);
			gy2 : float = ifx mp.y >= 0 then gy + 0.5 else gy - 0.5;
			cursor_position.y = gy2 * GRID_SIZE;
		}
		else {
			cursor_position = mp;
		}

		// tools
		if is_input_pressed(.MOUSE_BUTTON_LEFT) 
			|| (is_input_down(.MOUSE_BUTTON_LEFT) && is_input_down(.SHIFT)){
			if tool== {

				case .PlaceSpawner; {
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
					if warp_level_name != editor_level.name {
						warp := WarpSpawner.{ cursor_position, warp_level_name };
						array_add(*editor_level.warps, warp);
						dirty = true;
					}
					else {
						print("Warp [%] cannot have the same name as level: %\n", warp_level_name, editor_level.name);
					}
				}
			}
		}
		else if is_input_released(.MOUSE_BUTTON_LEFT) {
			prev_placement = .{99999,99999}; //random big number that we'll never collide with
		}
	}

	// tool selects
	if is_input_pressed(49) tool = .PlaceSpawner;
	else if is_input_pressed(50) tool = .EraseSpawner;
	else if is_input_pressed(51) tool = .HeroSpawner;
	else if is_input_pressed(52) tool = .Warps;

	EDITOR_CAM_SPEED :: 5.;
	if is_input_down(.ARROW_UP) 		editor_camera.position.y += EDITOR_CAM_SPEED;
	if is_input_down(.ARROW_DOWN) 		editor_camera.position.y -= EDITOR_CAM_SPEED;
	if is_input_down(.ARROW_RIGHT) 		editor_camera.position.x += EDITOR_CAM_SPEED; 
	if is_input_down(.ARROW_LEFT) 		editor_camera.position.x -= EDITOR_CAM_SPEED;

	// actor type
	//@TODO need to pull from a valid list of spawnable actors
	//low := ActorType.Hero;
	//high := ActorType.WorldExit;
	low, high := enum_range(ActorType);
	if is_input_pressed(.PAGE_UP) {
		actor_to_spawn = ifx actor_to_spawn == xx high then xx low else actor_to_spawn+1;
	}
	if is_input_pressed(.PAGE_DOWN) {
		actor_to_spawn = ifx actor_to_spawn == xx low then xx high else actor_to_spawn-1;
	}

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
	//@CLEAN origin := coords_world_to_window(.{0,0}, *editor_camera);
	origin := Vector2.{0,0};
	draw_circle(origin, 5, color=GREEN);

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
		render_sprite(sprite, it.position);
		//@CLEAN render_sprite(sprite, it.position, *editor_camera);
	}
	// hero spawn points, RED = index 0
	for editor_level.hero_spawn_points {
		//p := coords_world_to_window(it, *editor_camera); @CLEAN
		p := it;
		r := GRID_SIZE;
		c := lerp(RED, GREEN, it_index/cast(float)editor_level.hero_spawn_points.count);
		draw_circle(p, r, r-8, color=c);
		sprite := get_actor_sprite(.Hero);
		render_sprite(sprite, it);
		//@CLEAN render_sprite(sprite, it, *editor_camera);
	}

	// warps
	for editor_level.warps {
		//p := coords_world_to_window(it.position, *editor_camera);
		p := it.position;
		r := 12.;
		draw_circle(p, r, r-8, color=GREEN);
	}

	//cursor
	//cp := coords_world_to_window(cursor_position, *editor_camera);
	cp := cursor_position;
	draw_box(.{cp.x, cp.y, size, size}, ifx cursor_in_deadzone then BLACK else YELLOW, 8);

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
}

editor_save :: () {
	print("attempting to save...\n");
	level_save(*editor_level);
	dirty = false;
}

editor_load :: (name : string) {
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
	level_reset(*editor_level);
	editor_level.name = sprint(name);
	print("Editting new level: %\n", editor_level.name);
}

is_cursor_deadzone :: (pos : Vector2) -> bool {
	return pos.x < deadzone.x;
}
