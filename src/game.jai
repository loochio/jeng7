/* Game F prototype - 13 Sept 2025

Idea: Recusive level warping
Inspirations: Coccoon | Patrick's Parabox | Inception | Antichamber | Sokaban heros (thekla)
	Talos Principle

14 Sept 2025 from Moonbase420
// Dear maintainer: // 
// Once you are done trying to 'optimize' this routine, 
// and have realized what a terrible mistake that was, 
// please increment the following counter as a warning 
// to the next guy: // 
// total_hours_wasted_here = 42 //

*/

game_plugin := EnginePlugin.{
	name = "game",
	proc_init 	= game_init,
	proc_deinit = game_deinit,
	proc_begin 	= game_begin,
	proc_end 	= game_end,
	proc_tick 	= game_tick,
	proc_render = game_render,
};

level_root : string; 	// root level to load from
level_start : string; 	// level the player will begin in

game_paused := false;
input_up := false;
input_down := false;
input_right := false;
input_left := false;

debug_colliders := false;

game_init :: () {
	print("~~ Game Init ~~ \n");
	register_cheats();
	game_begin();
}

game_deinit :: () {
	game_end();
	print("~~ Game Deinit ~~\n");
}

game_begin :: () {
	print("~~ Game Begin ~~\n");
	game_paused = false;
	actor_id = 0;

	set_configs("game");
	assert(is_valid(level_root));
	assert(is_valid(level_start));

	// initialize from the root world
	root_world := world_init(level_root);
	assert(root_world != null);
	for * worlds {
		if !is_valid(it) continue;
		world_begin(it);

		if it.name == level_start {
			active_world = it;
		}
	}
	assert(active_world != null);

	//active_world = first_world; @CLEAN

	// Possess our first available option
	for * active_world.actors {
		if !is_valid(it) continue;

		if it.flags & .CanPossess {
			possess(it);
			break;
		}
	}
	print("\tInitial world activation: %\n", active_world.name);
}

game_end :: () {
	print("~~ Game End ~~\n");

	for worlds {
		if !is_valid(*it) continue;
		world_deinit(*it);
	}
	active_world = null;
}

game_restart :: () {
	print("Game Restart\n");
	game_end();
	game_begin();
}

game_tick :: (dt : float) {
	if is_input_pressed(.TAB) toggle_pause();
	if is_input_pressed(.ENTER) game_restart();

	#if DEVELOPER {
		if is_input_pressed(.F5) {
			set_plugin("editor");
			return;
		}
	}

	if game_paused  return;

	input_up = is_input_down(87) || is_input_down(.ARROW_UP); //w
	input_down = is_input_down(83) || is_input_down(.ARROW_DOWN); //s
	input_left = is_input_down(65) || is_input_down(.ARROW_LEFT); //a
	input_right = is_input_down(68) || is_input_down(.ARROW_RIGHT); //d

	// clear interaction flags because of same frame interactions
	//@TODO this really could be solved by having a ConsumeInput type of data
	for * active_world.actors {
		if !is_valid(it) continue;
		it.flags &= ~.InteractCooldown;
	}

	// Tick root worlds (ones without a parent)
	// we start from the negative active world's depth, keeping our active world ticked at depth=0
	world_tick_pure(active_world, dt);
	for worlds {
		if !is_valid(*it) continue;
		if it.parent == null world_tick(*it, dt, -active_world.depth);
	}
}

toggle_pause :: () {
	game_paused = !game_paused;
	pause_physics = game_paused;
	play_sound(.Pause);
}


// ~~~ physics simulation ~~~
PHYSICS_ITERATIONS :: 1;
PHYSICS_SLEEP_THRESHOLD :: 0.0001;
PARTITION_CELL_SIZE :: 75.; // world units, needs to be large enough to cover a collider size
PARTITION_RANGE :: 1;

pause_physics := false;

is_in_partition_range :: (a0 : *Actor, a1 : *Actor) -> bool {
	return abs(a0.partition_cell_x - a1.partition_cell_x) <= PARTITION_RANGE 
		&& abs(a0.partition_cell_y - a1.partition_cell_y) <= PARTITION_RANGE ;
}

get_partition_pos :: (cell_x : s64, cell_y : s64) -> Vector2 {
	return .{ 
		PARTITION_CELL_SIZE * (xx cell_x + 0.5), 
		PARTITION_CELL_SIZE * (xx cell_y + 0.5)
	};
}

get_partition_index_from_world_pos :: (pos : float) -> s64 {
	return xx (pos / PARTITION_CELL_SIZE);
}

physics_tick :: (using world : *World, dt : float) {
	if pause_physics return;

	// update pos
	for i : actors_head..actors_tail {
		a := *actors[i];
		if !is_valid(a) continue;

		if distance_squared(a.position, a.prev_position) < PHYSICS_SLEEP_THRESHOLD {
			a.body.asleep = true;
		}
		else {
			a.body.asleep = false;
			a.direction = normalize(a.position - a.prev_position);
		}

		a.prev_position = a.position;

		a.partition_cell_x = get_partition_index_from_world_pos(a.position.x);
		a.partition_cell_y = get_partition_index_from_world_pos(a.position.y);
	}

	// velocity, trigger overlaps 
	for i : actors_head..actors_tail {
		a := *actors[i];
		if !is_valid(a) continue;
		if !a.body.enabled continue;
		if a.body.type == .Static continue;

		a.position.x += a.velocity.x * dt;
		a.position.y += a.velocity.y * dt;
		drag := a.linear_drag * dt;
		if a.velocity.x > 0 {
			a.velocity.x = max(0., a.velocity.x - drag);
		}
		else if a.velocity.x < 0 {
			a.velocity.x = min(0., a.velocity.x + drag);
		}

		if a.velocity.y > 0 {
			a.velocity.y = max(0., a.velocity.y - drag);
		}
		else if a.velocity.y < 0 {
			a.velocity.y = min(0., a.velocity.y + drag);
		}
	}

	// collision resolution
	for 0..PHYSICS_ITERATIONS 
	{
		for i : actors_head..actors_tail {
			a := *actors[i];
			if !is_valid(a) continue;
			if !a.body.enabled continue;
			if a.body.asleep continue;
			if a.body.type != .Dynamic continue; 

			//@TODO factor in focused partition range (cells around Hero)

			for j : actors_head..actors_tail {
				b := *actors[j];
				if !is_valid(b) continue;
				if a == b continue;
				if !is_in_partition_range(a,b) continue;

				// a is overlapping b, resolve collision, move a out of b
				if is_overlap(a.position, *a.body, b.position, *b.body) {
					//@TODO we're doing this math twice
					apos := a.position;
					ar := a.body.size.x;
					bpos := b.position;
					br := b.body.size.x;
					dv := normalize(apos-bpos);
					dv *= ar + br - distance(apos, bpos); //overlap depth

					//@TODO distribute this move based on size/mass
					if b.body.type == {
						case .Dynamic; {
							a.position += dv/2;
							b.position -= dv/2;
						}
						case .Static; #through;
						case .Kinematic; {
							a.position += dv;
						}
					}

					if a.proc_onhit a.proc_onhit(a,b);
					if b.proc_onhit b.proc_onhit(b,a);
				}
			}
		}
	}
}

game_render :: (dt : float) {
	{ // Parent World
		pos := Vector2.{window_width/2., window_height/2.};
		size := Vector2.{xx window_width, xx window_height};
		if active_world.parent == null {
			draw_square(pos, size, G_BLACK);
		}
		else {
			nests := -1.;
			//n := -1;
			//nests := ifx enter then n-active_world.transition_progress else n+active_world.transition_progress;
			clip := BoxFloat.{pos.x, pos.y, size.x, size.y};
			enter := active_world.transition_enter;
			world_render(active_world.parent, nests, clip, pos, false);
		}
	}
	
	{ // Active World, recursive rendering
		ACTIVE_WORLD_CLIP_SIZE :: 440.;
		clip_size_x := scalar_to_window(ACTIVE_WORLD_CLIP_SIZE) * 1.25;
		clip_size_y := scalar_to_window(ACTIVE_WORLD_CLIP_SIZE);
		sizex := clip_size_x;
		sizey := clip_size_y;

		// only scale the exit (@TODO for now)
		if active_world.transition_world != null && !active_world.transition_enter {
			assert(active_world.transition_progress >= 0);
			sc := SUBCLIP_SIZE_DEFAULT;
			dt := active_world.transition_progress;
			sizex = lerp(clip_size_x, sc, dt);
			sizey = lerp(clip_size_y, sc, dt);
		}

		clip := BoxFloat.{window_width/2., window_height/2., sizex, sizey};
		//clip := BoxFloat.{window_width/2., window_height/2., xx window_width, xx window_height};

		pos_in_window := Vector2.{0,0};
		world_render(active_world, 0, clip, pos_in_window);
	}
	
	//@TODO UI Layout rendering

	draw_text :: (line : s64, format_string: string, args: .. Any) {
		text := tprint(format_string, ..args);
		text_width := prepare_text(hud_font, text);
	    text_y := window_height - hud_font.character_height * line;
	    draw_prepared_text(hud_font, 0, text_y, G_WHITE);
	}
	draw_text(1, "[E] Pickup");
	draw_text(2, "[Q] Interact");
	draw_text(3, "[Arrows/WASD] Move");
	draw_text(4, "[TAB] Pause");
	draw_text(5, "[ENTER] Restart");
	draw_text(6, "[F2] Mute");

	draw_text(9, "World: %", active_world.name);

	if game_paused {
		text := "PAUSED";
		text_width := prepare_text(hud_font, text);
		text_x := (window_width - text_width) / 2;
	    text_y := window_height * 0.95;
	    draw_prepared_text(hud_font, text_x, xx text_y, G_BLACK);
	}

	if debug_colliders {
		for *a : active_world.actors {
			if !is_valid(a) continue;

			p := vec_world_to_window(a.position, a.world);
			draw_collider(p, *a.body);
			draw_collider(p, *a.interact_collider);
		}
	}
}

// ~~~ Worlds ~~~
World :: struct {
	using level : Level;
	flags : WorldFlags;
	timeflags : WorldTimeFlags;
	depth := 0.; // nested level, float due to transition progress
	age := 0.; // relative age, factoring in time dilation
	parent : *World;

	transition_time := 0.;
	transition_progress := 0.; //[0-1]
	transition_enter := true; //@TODO move to WorldFlags
	transition_actor : *Actor;
	transition_world : *World;

	actors : [MAX_ACTORS_PER_WORLD] Actor;
	actors_head := 0;
	actors_tail := 0;
	
	camera : Camera;
	focus : *Actor;
	focus_default : *Actor;
	background_fill := G_WHITE;
}

WorldFlags :: enum_flags u8 {
	Initialized 	:: 1;
}

WorldTimeFlags :: enum_flags u8 {
	TimeFlipped 	:: 1;
	TimeInfinite 	:: 1<<1;
}


MAX_WORLDS :: 8;
worlds : [MAX_WORLDS] World;
MAX_ACTORS_PER_WORLD :: 4096;
actor_id := 0;
active_world : *World;

world_init :: (level_name : string, depth := 0.) -> *World {
	w : *World;
	for * worlds {
		if is_valid(it) continue;

		worlds[it_index] = .{};
		w = it;
		w.flags |= .Initialized;
		//w.flags |= .TimeFlipped; make time faster
		w.depth = depth;
		break;
	}
	assert(w != null);

	level_load(level_name, *w.level);
	print("World initialize: % [%]\n", w.name, w);

	// warps, linking worlds
	for w.spawners {
		if it.type != .WorldEntrance continue;

		level_name := it.data;
		assert(is_valid(level_name));
		if exists(level_name) continue;

		print("recursive world init: %\n", level_name);
		world_init(level_name, depth+1);
	}
	return w;
}


world_deinit :: (using world : *World) {
	level_reset(*level);
	flags = 0;

	for * actors {
		destroy(it);
	}
}

world_begin :: (world : *World) {
	assert(is_valid(world));
	
	// initial actor spawning
	for * world.spawners {
		a := spawn(world, it);
		assert(a != null);
	}

	// link up any actors we need
	for *a : world.actors {
		if !is_valid(a) continue;
		if a.type == .Console || a.type == .ConsoleMovable{
			for *b : world.actors {
				if !is_valid(b) continue;
				if b.type == .WallLock {
					a.link = b.id;
				}
			}
		}
	}
}

get_world :: (name : string) -> *World{
	for * worlds {
		if !is_valid(it) continue;
		if it.name == name  return it;
	}
	assert(false, "failed to find world [%]\n", name);
	return null;
}

is_valid ::(world : *World) -> bool {
	return world.flags & .Initialized != 0;
}

exists :: (world_name : string) -> bool {
	for * worlds {
		if !is_valid(it) continue;
		if it.name == world_name  return true;
	}
	return false;
}

// Convert a vector in the given world space
// replacing coords_world_to_window() to accommadate new world system
vec_world_to_window :: (world_pos : Vector2, world : *World, nests := 0.) -> Vector2 {
	result := world_pos - world.camera.position;
	scale := get_window_aspect_scale();
	scale *= get_nest_scale(nests);
	result.x *= scale * forced_window_scale_x;
	result.y *= scale * forced_window_scale_y;
	result.x += window_width/2.;
	result.y += window_height/2.;
	return result;
}

set_active_world :: (actor : *Actor) {
	assert(actor.flags & .Possessed != 0);
	active_world = actor.world;
	active_world.focus = actor;
}

world_enter_begin :: (a : *Actor, world : *World) {
	// enter world immediately if not possessed
	if a.flags & .Possessed == 0{
		world_enter(a, world);
		return;
	}

	assert(a.flags & .Possessed != 0);
	a.world.transition_time = WORLD_TRANSITION_TIME;
	a.world.transition_actor = a;
	a.world.transition_world = world;
	a.world.transition_enter = true;

	// update the parent world we're warping to
	// There can be multiple parent worlds associated with this world.
	world.parent = a.world;
	play_sound(.Warp);
}

world_enter_end :: (world : *World) {
	assert(world.transition_actor != null);
	assert(world.transition_world != null);
	assert(world.transition_enter);
	world_enter(world.transition_actor, world.transition_world);
	world.transition_actor = null;
	world.transition_world = null;
}

world_enter :: (a : *Actor, world : *World) {
	// warp to the pos of target world's exit
	pos := Vector2.{};
	for world.actors { //@OPTIMIZE iterate on world.head/tail
		if !is_valid(*it) continue;

		if it.type == .WorldExit {
			pos = it.position;
			break;
		}
	}

	new_actor := move_actor_to_world(a, world, pos);
	if new_actor {
		assert(!is_valid(a));
		if new_actor.flags & .Possessed
			set_active_world(new_actor);
	}
}

world_exit_begin :: (a : *Actor) {
	// exit world immediately if not possessed
	if a.flags & .Possessed == 0{
		world_exit(a);
		return;
	}

	a.world.transition_time = WORLD_TRANSITION_TIME;
	a.world.transition_actor = a;
	a.world.transition_enter = false;
	a.world.transition_world = a.world.parent;
	assert(a.world.parent != null);
}

world_exit_end :: (world : *World) {
	assert(world.transition_actor != null);
	assert(world.transition_world != null);
	assert(!world.transition_enter);
	world_exit(world.transition_actor);
	world.transition_actor = null;
	world.transition_world = null;
}

world_exit :: (a : *Actor) {
	assert(a != null);
	assert(a.world.parent != null);

	// set the focus of this exiting world
	for * a.world.actors { //@OPTIMIZE iterate on world.head/tail
		if !is_valid(it) continue;

		// set our focus to the exit
		if it.type == .WorldExit && a.flags & .Possessed {
			a.world.focus = it;
			break;
		}
	}

	// warp to the parent entrance position
	pos := Vector2.{};
	for * a.world.parent.actors { //@OPTIMIZE iterate on world.head/tail
		if !is_valid(it) continue;

		if it.type == .WorldEntrance && a.world == it.child_world {
			pos = it.position;
			break;
		}
	}

	new_actor := move_actor_to_world(a, a.world.parent, pos);
	if new_actor {
		assert(!is_valid(a));
		set_active_world(new_actor);
		play_sound(.Warp, pitch_min=.7, pitch_max=.7);
	}
}

move_actor_to_world :: (actor : *Actor, world : *World, pos := Vector2.{}) -> *Actor{
	if actor.world == world {
		print("attempting to reenter world=% with actor=% flags=%\n", world.name, actor.type, actor.flags);
		return null;
	}
	print("attemping move world=% : [%] % \n", world.name, actor, actor.type);

	// force blocked items to drop before we start moving memory between worlds
	item := actor.held_item;
	if item != null && (item.flags & .BlockWarping != 0) {
		print("force dropping item=% | flags=%\n", item.type, item.flags);
		item_drop(actor);
		item = null;
	}

	assert(actor.world != world);
	new_actor := init_actor(world);
	memcpy(new_actor, actor, size_of(Actor));

	// we need to reset the world bc it gets overwritten with memcpy()
	new_actor.world = world;
	new_actor.position = pos;

	if item != null {
		i := move_actor_to_world(item, world);
		item_pickup(i, new_actor);
	}

	//@TODO generic proc in the Actor
	//new_actor.proc_on_world_move(new_actor);
	if new_actor.type == {
		case .WorldEntrance; {
			// update the linked worlds along with their depth (level of nesting)
			new_actor.child_world.parent = world;
			new_actor.child_world.depth = world.depth+1;
		}
	}

	// update world conditions, wipe any time flags
	//@TODO potentially sloppy, does this need to be more precise
	//@TODO2 yes, this needs to be more precise for TimeInfinite (for now)
	for *w : worlds {
		if !is_valid(w) continue;
		w.timeflags &= ~.TimeInfinite;
	}

	// cleanup the old actor now that we're done with it
	deinit_actor(actor);
	return new_actor;
}

// ticking the active world, not subject to nested time
world_tick_pure :: (using world : *World, dt : float) {
	// World transitions
	if transition_time > 0 {
		transition_time -= dt;
		transition_progress = 1. - (transition_time / WORLD_TRANSITION_TIME);

		if transition_time <= 0 {
			assert(transition_progress >= 1., "%", transition_progress);
			transition_time = 0;
			transition_progress = 0.;

			//@TODO generalize to world_transition_end
			if transition_enter {
				world_enter_end(world);
			}
			else {
				world_exit_end(world);
			}
		}
		return;
	}

	physics_tick(world, dt);

	// actors
    for i : actors_head..actors_tail {
		a := *actors[i];
    	if !is_valid(a) continue;

    	if a.proc_tick_pure a.proc_tick_pure(a, dt);
    }
}

//@TODO is there a way we could schedule an arbitrary tick func? like a Task (struct)
world_tick :: (using world : *World, dt : float, nests := 0.) {
	assert(is_valid(world));

	// Time dilation, time moves faster in nested worlds (think Inception)
	pure_dt := dt;
	nest_time := get_nest_time(nests);

	// time calculations based on flags
	if world.timeflags & .TimeInfinite {
		dt = 0.;
	}
	else if world.timeflags & .TimeFlipped {
		dt = dt/nest_time;
	}
	else {
		dt = dt*nest_time;
	}
	age += dt;

    // cam lerp 
    camera.zoom = get_nest_scale(nests);
    if focus != null {
    	fp := focus.position;
    	camera.position = fp;
    }
	else {
		camera.position.x = 0;
		camera.position.y = 0;
	}
	
	// actor ticks
    for i : actors_head..actors_tail {
		a := *actors[i];
    	if !is_valid(a) continue;

    	if (a.proc_tick) a.proc_tick(a, dt);

    	if a.body.type != .Static {
 	   		a.sprite.flipped = a.direction.x < 0;
    	}
		
		sprite_tick(*a.sprite, dt);
    	
    	a.lifetime_dt += dt;
		if a.lifetime > 0 && a.lifetime_dt >= a.lifetime {
			if a.proc_onlifetime_expired
				a.proc_onlifetime_expired(a);

			if a.flags & .DestroyAfterLifetime {
				print("LIFETIME EXPIRATION type=%\n", a.type);
				destroy(a);
			}
		}

		for child : a.children {
			child.position = a.position;
			child.position += child.relative_position;
		}
    }

    // recursive world ticks, tick child worlds
    if nests > WORLD_TICK_NEST_MAX {
    	world.timeflags |= .TimeInfinite;
    	return;
    }

    for actors {
    	if !is_valid(*it) continue;
    	if it.child_world == null continue;

    	// passing pure_dt because we continue to do nested scaling later
    	world_tick(it.child_world, pure_dt, nests+1);
    }
}

WORLD_NESTED_SCALE :: 0.5;
WORLD_NESTED_SCALE_VEC :: Vector2.{WORLD_NESTED_SCALE, WORLD_NESTED_SCALE};
SUBCLIP_SIZE_DEFAULT :: 200.;
SUBCLIP_SIZE_MAX :: 2000; //@TODO should be max(window_width, window_height);
SUBCLIP_OUTLINE_THICKNESS :: 8.;
WORLD_NESTED_TIME :: 0.15;
WORLD_TIME_PER_CYCLE :: 10.; // for the revolving outline marker
WORLD_TRANSITION_TIME :: 0.25; 
WORLD_TICK_NEST_MAX :: 10.;
WORLD_RENDER_NEST_MAX :: 4.;



get_nest_scale :: (nests := 0.) -> float {
	return pow(WORLD_NESTED_SCALE, nests);
}

get_nest_scale_vec :: (nests := 0.) -> Vector2 {
	scale := get_nest_scale(nests);
	return Vector2.{scale, scale};
}

get_nest_time :: (nests := 0.) -> float {
	return pow(WORLD_NESTED_TIME, nests);
}

get_nest_color :: (nests : float) -> Vector4 {
	return lerp(BLUE, RED, nests / 5.);
}

get_world_color :: (world : *World) -> Vector4 {
	if world.timeflags & .TimeInfinite {
		return G_BLACK;
	}
	return get_nest_color(world.depth);
}

world_render :: (using world : *World, nests : float, window_clip : BoxFloat, pos_in_window : Vector2, should_render_subworlds := true) {
	assert(is_valid(world), "%", world.name);

	{ // scissor clip for this world, cleared before next recursive call
		//@TODO change window_clip to an AABB
		x0 := cast(s32)(window_clip.x - window_clip.w/2.);
		y0 := cast(s32)(window_clip.y - window_clip.h/2.);
		x1 := cast(s32)(window_clip.x + window_clip.w/2.);
		y1 := cast(s32)(window_clip.y + window_clip.h/2.);
		set_scissor(x0,y0,x1,y1);
	}

	{ // background fill
		color := world.background_fill * get_world_color(world);
		draw_square(.{window_clip.x, window_clip.y}, .{window_clip.w, window_clip.h}, color);
	}
	
	// sprite rendering, sorted by position.y
	sorted_actors : [..] *Actor;

	for i : actors_head..actors_tail {
		a := *actors[i];
		if !is_valid(a) continue;

		if ENABLE_FRUSTRUM_CULLING
		{
			//skip entities not in view
			//@TODO prob not precise with all of sprite's variables
			ep := vec_world_to_window(a.position, world, nests);
			ew := a.sprite.size.x;
			eh := a.sprite.size.y;
			if ep.x < -ew || ep.x > (window_width+ew) || ep.y < -eh || ep.y > (window_height+eh) 
				continue;
		}
		
		idx := 0;
		for sorted_actors {
			if a.sprite.layer > it.sprite.layer {
				idx += 1;
				continue;
			}
			if a.sprite.layer < it.sprite.layer {
				break;
			}
			// factor in relative offset if attached to parent
			ya := a.position.y - a.relative_position.y;
			yb := it.position.y - it.relative_position.y; 
			if ya < yb {
				idx += 1;
				continue;
			}
		}
		array_insert_at(*sorted_actors, a, idx);
	}

	// nest scaling, accounting for tranisitons
	enter := world.transition_enter;
	n := ifx enter then nests - world.transition_progress else nests + world.transition_progress;
	nscale := get_nest_scale_vec(n);

	// final window scale
	winscale := get_window_aspect_scale();
	scale := winscale * nscale;

	// sprite rendering
	for a : sorted_actors {
		assert(is_valid(a));

		// inlining vec_world_to_window() for clarity
		pos := a.position - world.camera.position;
		pos *= scale;
		pos.x += window_width/2.;
		pos.y += window_height/2.;
		pos += pos_in_window; // recursively add our pos

		render_sprite(*a.sprite, pos, nscale);
	}

	// draw window_clip border 
	{
		outline := window_clip;
		thickness := scalar_to_window(SUBCLIP_OUTLINE_THICKNESS) * nscale.x;
		color := world.background_fill * get_world_color(world) * .75;
		color.w = 1;
		draw_box(outline, color, thickness);

		// time marker, white box on outline
		draw_dot :: (outline : BoxFloat, world : *World, nests : float, nscale : Vector2, offset := 0.) {
			progress := fmod_cycling(world.age,WORLD_TIME_PER_CYCLE) / WORLD_TIME_PER_CYCLE;
			progress -= offset;
			p := get_box_percent_pos(*outline, progress);
			ofactor := pow(1-offset, 15.);
			size := scalar_to_window(8 * ofactor) * nscale.x;
			c := G_WHITE;
			c.w *= ofactor;
			if nests < 0 c.w *= 0.1;
			draw_circle(p, size, color=c);
		}
		trails :: 10;
		for 0..trails {
			draw_dot(outline, world, nests, nscale, 0.01*it);
		}
		//draw_dot(outline, world, nests, nscale);
		//draw_dot(outline, world, nests, nscale, 0.01);
		//draw_dot(outline, world, nests, nscale, 0.02);
		//draw_dot(outline, world, nests, nscale, 0.03);
	}

	// clear the scissor now so we can set a new one in our recursive subworld_render() call
	clear_scissor();

	// recursive actor rendering, only for subworld_render(..) for now.
	//@OPTIMIZE we should simplify this to just find WorldEntrance and handle subworld_render(..) here
	if should_render_subworlds {
		for a : sorted_actors {
			if a.proc_render {
				pos := vec_world_to_window(a.position, world, n);
				pos += pos_in_window; // recursively add our pos
				a.proc_render(a, n, window_clip, pos);
			}
		}
	}

	//@OPTIMIZE move this to an array_reset_safe(..) type of func
	if sorted_actors.data != null
		array_reset(*sorted_actors);
}

subworld_render := (a : *Actor, nests : float, window_clip : BoxFloat, pos_in_window : Vector2) {
	// find new clipping box, subdividing our current window_clip
	nscale := get_nest_scale(nests);
	subclip : BoxFloat;
	subclip.x = pos_in_window.x;
	subclip.y = pos_in_window.y;

	// only widen this subclip for the target transition entrance
	subclip_size := SUBCLIP_SIZE_DEFAULT;

	if a.world.transition_world != null &&  a.world.transition_world == a.child_world {
		subclip_max := max(window_width*1.25, window_height*1.25);
		subclip_size = lerp(SUBCLIP_SIZE_DEFAULT, subclip_max, a.world.transition_progress);
	}
	
	box_size := subclip_size * nscale;
	subclip.w = box_size;
	subclip.h = box_size;

	overlapping, intersection := get_box_intersection(window_clip, subclip);

	if overlapping {
		//scuffed eps check
		assert(intersection.w <= subclip.w+1. && intersection.h <= subclip.h+1., 
			"nests=% | win=% | sub=% | intersection=%", nests, window_clip, subclip, intersection);

		origin := pos_in_window;
		origin.x -= window_width/2.;
		origin.y -= window_height/2.;

		if nests <= WORLD_RENDER_NEST_MAX {
			world_render(a.child_world, nests+1, intersection, origin);
		}
		else {
			draw_box(intersection, get_world_color(a.child_world));
		}
	}
}

// get the position around the edge of the box given a percent
// start in bottom left, progress clockwise
get_box_percent_pos :: (box : *BoxFloat, percent : float) -> Vector2{
	percent = clamp(percent, 0., 1.);
	result : Vector2;
	x := box.x;
	y := box.y;
	w := box.w;
	h := box.h;

	if percent >= 0 && percent < .25 {
		result.x = x-w/2.;
		result.y = lerp(y-h/2., y+h/2., percent*4);
	}
	else if percent >= .25 && percent < .5 {
		result.x = lerp(x-w/2., x+w/2., (percent-.25)*4);
		result.y = y+h/2.;
	}
	else if percent >= .5 && percent < .75 {
		result.x = x+w/2.;
		result.y = lerp(y+h/2., y-h/2., (percent-.5)*4);
	}
	else { 
		result.x = lerp(x+w/2., x-w/2., (percent-.75)*4);
		result.y = y-h/2.;
	}
	return result;
}


// Holding World data for spawning actors
Level :: struct {
	name : string;
	spawners : [..] ActorSpawner;
}

ActorSpawner :: struct {
	type : ActorType;
	position : Vector2;
	scale := Vector2.{1,1};
	data : string;
}

level_save :: (level : *Level) {
	path := tprint("levels/%.level", level.name);
	builder: String_Builder;
	init_string_builder(*builder);

	// level name
	name_len := cast(*u8)*level.name.count;
	append(*builder, name_len, size_of(s64));
	append(*builder, level.name);

	{ // level spawners
		count := cast(*u8)*level.spawners.count;
		append(*builder, count, size_of(s64));
		for * level.spawners {
			spawner := cast(*u8)it;
			append(*builder, spawner, size_of(ActorSpawner));

			// extra spawner data
			len := cast(*u8)*it.data.count;
			append(*builder, len, size_of(s64));
			append(*builder, it.data);
		}
	}

	write_entire_file(path, *builder);
	reset(*builder);
	print("Saved %\n", path);
}

is_valid_level_name :: (name : string) -> bool {
	path := tprint("levels/%.level", name);
	return file_exists(path);
}

level_load :: (name : string, level : *Level) -> bool {
	path := tprint("levels/%.level", name);
	buffer, success := read_entire_file(path);

	if !success {
		print("Failed to load level: %\n", path);
		return false;
	}

	// Level should have been freed before hand
	assert(level.name.count == 0, "%", level.name);
	assert(level.spawners.count == 0 && level.spawners.data == null);

	// name
	name_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*name_len, size_of(s64));
	level.name = alloc_string(name_len);
	consume_u8_and_length(*buffer, level.name.data, name_len);

 	// spawners
	spawner_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*spawner_len, size_of(s64));
	assert(level.spawners.count == 0);
	for 0..spawner_len-1 {
		spawner := ActorSpawner.{};
		consume_u8_and_length(*buffer, cast(*u8)*spawner, size_of(ActorSpawner));

		len := 0;
		consume_u8_and_length(*buffer, cast(*u8)*len, size_of(s64));
		spawner.data = alloc_string(len);
		consume_u8_and_length(*buffer, spawner.data.data, len);

		//@TODO need to figure out this enum validation
		if type_of(spawner.type) == ActorType {
			array_add(*level.spawners, spawner);
		}
		else{
			print("\tFailed to parse spawner: % in level=%\n", spawner.type, level.name);
		}

		{// Validation
			low, high := enum_range(ActorType);
			type : s64 = xx spawner.type;
			assert(type >= low, "%", type);
			assert(type <= high, "%", type);
		}
	}

	if name != level.name {
		print("\told name [%] detected on level=%, updating name\n", level.name, name);
		string_reset(*level.name);
		level.name = sprint(name);
	}

	print("LOADED: name=% | spawners=%\n", level.name, level.spawners.count);
	return true;
}

level_reset :: (level : *Level) {
	assert(is_valid(level));
	assert(level.name.count > 0);
	string_reset(*level.name);

	for * level.spawners {
		spawner_reset(it);
	}

	if level.spawners.data != null
		array_reset(*level.spawners);
}

spawner_reset :: (spawner : *ActorSpawner) {
	assert(spawner != null);
	string_reset(*spawner.data);
}

is_valid :: (level : *Level) -> bool {
	return level.name.count > 0;
}

// ~~~ Actors ~~~

Actor :: struct {
	id := 0;
	type := ActorType.EMPTY;
	flags : ActorFlags;
	world : *World;
	child_world : *World;

	proc_begin : ActorProc;
	proc_tick : ActorProc_Tick;
	proc_tick_pure : ActorProc_Tick;
	proc_render : ActorProc_Render;
	proc_on_interact : ActorProc_Overlap;
	proc_on_dropped : ActorProc;
	proc_on_pickup : ActorProc;

	sprite : Sprite;

	position : Vector2;
	prev_position : Vector2;
	partition_cell_x := 0;
	partition_cell_y := 0;

	direction : Vector2;
	velocity : Vector2;

	body : Collider;
	proc_onhit : ActorProc_Overlap;
	linear_drag := 800; 	// linear reduction in velocity on each tick
	bounce := 0.5; 			// amount we bounce off a collision
	scale := Vector2.{1,1}; //@TODO do we use this?

	speed := Vector2.{1,1}; // speed of the character added per frame (typically Heros)
	interact_collider : Collider;
	proc_onoverlap_interact : ActorProc_Overlap;

	lifetime := -1.;
	lifetime_dt := 0.;
	proc_onlifetime_expired : ActorProc;

	held_item : *Actor;
	weight : u8 = 0;
	strength : u8 = 0;

	children : [..]*Actor;
	parent : *Actor;
	relative_position : Vector2;

	link : s64 = 0;
}

ActorType :: enum s64 #specified {
	EMPTY 		:: -1; // should never be serialized, using for world.actor mem

	Hero		:: 0;
	Marker		:: 1;
	Block 		:: 2;
	Tile_Red 	:: 3;
	WorldEntrance :: 4;
	WorldExit 	:: 5; // warps to the parent world
	//Key 		:: 6; @CLEAN

	//Hero :: 1000; //@TODO scuffed enum values for now
	HeroRed		:: 1001; 
	Kid			:: 1002;

	Console 		:: 2000;
	ConsoleMovable 	:: 2001;

	WallLock 		:: 3000; // instant
	//WallLockTimed 	:: 3001; // 2 second open duration

	DropZone 		:: 4000; // causes held items to drop
}

ActorFlags :: enum_flags s64 {
	Initialized		:: 1;
	CanPossess 		:: 1 <<2;
	Possessed 		:: 1 <<3;

	Pickupable		:: 1<<19;
	Interactable	:: 1<<20;
	BlockWarping	:: 1<<21; // VERY IMPORTANT for exits or else the game logically doesn't make sense
	InteractCooldown :: 1<<22;
	DestroyAfterLifetime :: 1<<23;
}

get_actor_tid :: (type : ActorType) -> TextureID {
	if type== {
		case .Hero; 			return TextureID.Hero;
		case .HeroRed; 			return TextureID.HeroRed;
		case .Kid; 			return TextureID.Bug;

		case .Block;			return TextureID.Tile_01;

		case .Console; 			return TextureID.Bush;
		case .ConsoleMovable;	return TextureID.Pebble;
		case .WallLock; 		return TextureID.Stone;
		//case .WallLock; 		return TextureID.Tile_Magma; @CLEAN 

		case .DropZone; 		return TextureID.DropZone;


		case .Tile_Red;			return TextureID.Tile_Magma;
		case .Marker; 			return TextureID.Marker;
		case .WorldEntrance; 	return TextureID.Entrance;
		case .WorldExit; 		return TextureID.Exit;
		//case .Key; 				return TextureID.ManaGem; @CLEAN
	}
	assert(false, "%", type);
	return .COUNT;
}

get_actor_sprite :: (type : ActorType) -> *Sprite {
	tid := get_actor_tid(type);
	return get_sprite(tid);
}


ActorProc :: #type (actor : *Actor);
ActorProc_Tick :: #type (actor : *Actor, dt : float);
ActorProc_Render :: #type (actor : *Actor, nests : float, clip : BoxFloat, pos_in_window : Vector2);
ActorProc_Overlap :: #type (a0 : *Actor, a1 : *Actor);

is_valid :: (actor : *Actor) -> bool{
	return actor.type != .EMPTY && actor.flags & .Initialized != 0;
}

is_valid_actor_spawner :: (type : ActorType) -> bool {
	if type== {
		case .EMPTY; return false;
		case .Marker; return false;
	}
	return true;
}

get_actor :: (aid : s64) -> *Actor {
	for worlds {
		for *a : it.actors {
			if !is_valid(a) continue;

			if a.id == aid return a;
		}
	}
	assert(false, "actor id not found = %", aid);
	return null;
}

init_actor :: (world : *World) -> *Actor{
	// find available memory in our world
	a : *Actor;
	while a == null {
		//reached the end of our static allocs
		//@TODO I'm not sure what I want to do here yet
		assert(world.actors_tail < MAX_ACTORS_PER_WORLD);

		a = *world.actors[world.actors_tail];
		world.actors_tail += 1;

		if is_valid(a) continue;

		world.actors[world.actors_tail-1] = Actor.{};
		a.world = world;
		a.flags |= .Initialized;
		actor_id += 1;
		a.id = actor_id;
		break;
	}
	assert(a != null);
	return a;
}

deinit_actor :: (a : *Actor) {
	a.type = .EMPTY;
	a.flags = 0;
}

destroy :: (a : *Actor) {
	deinit_actor(a);
	collider_reset(*a.body);
	collider_reset(*a.interact_collider);
	array_reset_keeping_memory(*a.children);
}

// hero configs
HERO_SPEED_DEFAULT 	:: Vector2.{50,50};
HERO_SPEED_FAST 	:: Vector2.{200,200};
hero_throw_strength := 375.;

spawn :: (world : *World, type : ActorType, pos := Vector2.{0,0}) -> *Actor{
	spawner := ActorSpawner.{type, pos, .{1,1}, ""};
	return spawn(world, *spawner);
}

spawn :: (world : *World, spawner : *ActorSpawner) -> *Actor{
	a := init_actor(world);
	a.type = spawner.type;
	a.sprite = get_actor_sprite(a.type);
	a.position = spawner.position;
	
	if a.type == {
		case .Hero; #through;
		case .HeroRed;
		{
			a.flags |= .CanPossess | .Interactable | .Pickupable;
			a.speed = HERO_SPEED_DEFAULT;
			a.body.type = .Dynamic;
			a.body.size = .{12,12};
			a.body.is_a = .Pawn | .Hero; //@TODO should only be one type
			a.body.collides_with = .Wall | .Pawn;
			a.interact_collider.type = .Trigger;
			a.interact_collider.size = .{36,36};
			a.interact_collider.is_a = .Pawn; //@TODO .Hero
			a.interact_collider.collides_with = .Pawn | .Hero;

			a.proc_tick_pure = player_tick_pure;

			// swap on interact
			a.proc_on_interact = (target : *Actor, interactor : *Actor) {
				assert(interactor.flags & .Possessed != 0, "%", interactor.type);
				assert(target.flags & .Possessed == 0, "%", target.type);
				possess(target, interactor);
			}
		}

		case .Kid; {
			a.flags |= .Pickupable;
			a.body.type = .Dynamic;
			a.body.size = .{12,12};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Wall | .Pawn;
		}

		case .WorldEntrance; {
			a.flags |= .Interactable | .Pickupable;
			a.body.type = .Kinematic;
			a.body.size = .{SUBCLIP_SIZE_DEFAULT/4.,SUBCLIP_SIZE_DEFAULT/4.};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;
			a.weight = 1;

			// link this world to a child world
			a.child_world = get_world(spawner.data);
			a.child_world.parent = a.world;

			a.proc_render = subworld_render; 

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				world_enter_begin(interactor, a.child_world);
			}

			//@TODO warp on collision, needs to work given that everything warps back right away
			//a.proc_onhit = (a0 : *Actor, a1 : *Actor) {
			//	if a1.flags & .BlockWarping return;
			//
			//	world_enter_begin(a1, a0.child_world);
			//}
		}

		case .WorldExit; {
			a.flags |= .Interactable | .BlockWarping | .Pickupable;
			a.body.type = .Kinematic;
			a.body.size = .{16,16};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;
			a.weight = 1;
			a.world.focus = a;
			a.world.focus_default = a;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				world_exit_begin(interactor);
			}
		}

		case .Block; {
			a.body.type = .Static;
			a.body.size = .{16,16};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn | .Wall;
		}

		case .Console; {
			a.flags |= .Interactable;
			a.body.type = .Static;
			a.body.size = .{16,16};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn | .Wall;

			a.proc_on_interact = console_interact;
			a.proc_onlifetime_expired = console_deinteract;
		}

		case .ConsoleMovable; {
			a.flags |= .Interactable | .Pickupable;
			a.body.type = .Dynamic;
			a.body.size = .{16,16};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;

			a.proc_on_interact = console_interact;
			a.proc_onlifetime_expired = console_deinteract;
		}

		case .WallLock; {
			a.body.type = .Static;
			a.body.size = .{16,16};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn | .Wall;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				if a.body.type != .Inactive {
					a.body.type = .Inactive;
					a.sprite = get_sprite(.ExitOutline);
				}
				else {
					a.body.type = .Static;
					a.sprite = get_actor_sprite(a.type);
				}
			}
		}

		case .DropZone; {
			a.body.type = .Trigger;
			a.body.size = .{16,16};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn;

			a.proc_onhit = (a0 : *Actor, a1 : *Actor) {
				//if a1.flags & .BlockWarping return;
				
				if is_holding_item(a1) item_drop(a1);
			}
		}
	}

	if a.type == {
		case .HeroRed; {
			a.strength = 1;
		}
	}

	if a.proc_begin a.proc_begin(a);

	return a;
}

// Player takes control of this actor
possess :: (target : *Actor, current : * Actor = null) {
	assert(target.flags & .CanPossess != 0);
	assert(target.flags & .Possessed == 0);

	print("\n Possessed target=%\n", target.type);
	target.flags |= .Possessed;
	target.world.focus = target;

	if current {
		assert(current.flags & .CanPossess != 0);
		assert(current.flags & .Possessed != 0);
		assert(current.world == target.world);
		current.flags &= ~.Possessed;
		print("\n \tunpossessed old=%\n", current.type);
	}
}

player_tick_pure :: (a : *Actor, dt : float) {
	assert(a.flags & (.CanPossess) != 0);

	// skip non-possessed heros
	if  a.flags & .Possessed == 0 return;

	// movement
	dv : Vector2;
    if input_up  dv.y += 1.;
    if input_down dv.y -= 1.;
    if input_right dv.x += 1.;
    if input_left dv.x -= 1.;

	a.position.x += dv.x * a.speed.x * dt;
	a.position.y += dv.y * a.speed.y * dt;

    // item pickups
    if is_input_pressed(69) { //E
    	if a.held_item {
    		item_drop(a);
    	}
    	else
    	{
    		w := a.world;
    		for i : w.actors_head..w.actors_tail {
				b := *w.actors[i];
	    		if !is_valid(b) continue;
	    		if a == b continue;
	    		if b.flags & .Pickupable == 0 continue;
	    		if !is_in_partition_range(a, b) continue;

	    		if is_overlap(a.position, *a.interact_collider, b.position, *b.body) {
	    			item_pickup(b, a);

	    			// pickup our first one
	    			//@TODO refine this to base on direction
	    			break;
	    		}
	    	}
    	}
	}
    // Interact
	if is_input_pressed(81) && (a.flags & .InteractCooldown == 0) { //Q
		w := a.world;
		for i : w.actors_head..w.actors_tail {
			b := *w.actors[i];
    		if !is_valid(b) continue;
    		if a == b continue;
    		if b.flags & .Interactable == 0 continue;
    		if !is_in_partition_range(a, b) continue;

    		if is_overlap(a.position, *a.interact_collider, b.position, *b.body) {
    			interact(b, a);
    			break;
    		}
    	}
	}
}

console_interact :: (a : *Actor, interactor : *Actor) {
	// start lifetime timer
	a.lifetime = 3.;
	a.lifetime_dt = 0.;

	// open first time
	link_actor := get_actor(a.link);
	interact(link_actor, a);

	a.sprite = get_sprite(.ManaGem);
	play_sound(.RoundBegin);
}

console_deinteract :: (a : *Actor) {
	a.lifetime = -1.;
	// close the link
	link_actor := get_actor(a.link);
	interact(link_actor, a);

	a.sprite = get_actor_sprite(a.type);
	play_sound(.Pause);
}

attach :: (parent : *Actor, child : *Actor, offset := Vector2.{0,0}, keep_body_enabled := false) {
	child.parent = parent;
	child.relative_position = offset;
	child.body.enabled = keep_body_enabled;
	array_add(*parent.children, child);
}

detach :: (child : *Actor) {
	assert(child != null);
	assert(child.parent != null);
	assert(child.parent.children.count > 0);

	child.position -= child.relative_position;
	child.relative_position = .{0,0};
	array_unordered_remove_by_value(*child.parent.children, child);
	child.parent = null;
}

is_holding_item :: (actor : *Actor) -> bool {
	return actor.held_item != null;
}

can_pickup_item :: (item : *Actor, owner : *Actor) -> bool {
	return item.weight <= owner.strength;
}

item_pickup :: (item : *Actor, owner : *Actor) {
	assert(item != null);
	assert(owner != null);

	if !can_pickup_item(item, owner) {
		sfx := play_sound(.PickupStart, vol_min=0.15, vol_max=0.2, pitch_min=0.4, pitch_max=0.5);
		return;
	}

	if is_holding_item(owner)
		item_drop(owner);

	assert(owner.held_item == null);
	owner.held_item = item;
	offset := Vector2.{0., owner.body.size.y + item.body.size.y};
	attach(owner, item, offset);

	if item.proc_on_pickup 
		item.proc_on_pickup(item);

	sfx := play_sound(.PickupStart);
	if sfx {
		sfx.user_volume_scale = random_get_within_range(0.15, 0.2);
		sfx.rate_scale = random_get_within_range(0.7, 0.8); 
	}
}

item_drop :: (owner : *Actor) {
	assert(owner != null);

	if !is_holding_item(owner) return;

	item := owner.held_item;
	if item.proc_on_dropped 
		item.proc_on_dropped(item);

	// throw if moving
	//@TODO prob a more clever math to find if we're moving
	if length_squared(owner.position - owner.prev_position) > 0 {
		item.velocity = owner.direction * hero_throw_strength;

		sfx := play_sound(.PickupThrow);
		if sfx {
			sfx.user_volume_scale = random_get_within_range(0.15, 0.2);
			sfx.rate_scale = random_get_within_range(0.7, 0.8); 
		}
	}
	else
	{
		play_sound(.PickupDrop, vol_min=0.15, vol_max=0.2, pitch_min=0.6, pitch_max=0.7);
	}

	detach(item);
	item.body.enabled = true;
	owner.held_item = null;
}

interact :: (target : *Actor, interactor : *Actor) {
	assert(target != null);
	assert(interactor != null);

	if target.flags & .InteractCooldown return;

	target.flags |= .InteractCooldown;
	interactor.flags |= .InteractCooldown;
	if target.proc_on_interact 
		target.proc_on_interact(target, interactor);
}

register_cheats :: () {

	//@DESIGN these terminal commands are meant to be found in game.
	// Knowledge based keys, "unlocks" when entered into the game for the first time
	// Store that unlock state in GameCareer save profile
	//@TODO terminal auto complete only shows commands you have unlocked
	register_cmd("reset", (args: .. Any) { game_restart(); });

	register_cmd("teser", (args: .. Any) { 
		// reset and reverse time
		game_restart(); 
		for * worlds {
			if !is_valid(it) continue;
			it.timeflags |= .TimeFlipped;
		}
	});

	/*
	register_cmd("rseet", (args: .. Any) { 
		// typo, deliberately fuck up the screen bc why not?
		//@TODO the engine level mod needs to be undone after the next restart
		// Probably stuff this into a GameState struct, ensure we wipe it every restart
		game_restart(); 
		//forced_window_scale_y *= -2.; 
		forced_window_scale_y *= -1.; //@TODO needs to be undone
		//forced_window_scale_x *= -1.; //@TODO needs to be undone
		print("force_window_scale_y = %\n", forced_window_scale_y);

		//@DESIGN with the way this fucks up the sprite translations,
		// I can see a fun idea where the sprite moves out of the way, and we can see behind it.
		// Put a secret behind there?
	});
	*/

	/* @TODO maybe reimplement, active_world.hero was removed
	register_cmd("fast", (args: .. Any) { 
		// make hero fast
		//@DESIGN a more fun idea would decrease the hero tick dt
		active_world.hero.speed = HERO_SPEED_FAST;
	});

	register_cmd("slow", (args: .. Any) { 
		// make hero slow, default
		active_world.hero.speed = HERO_SPEED_DEFAULT;
	});
	*/
	
	//@TODO hid this behind a DEBUG build define
	register_cmd("colliders", (args: .. Any) { debug_colliders = !debug_colliders; });
}

// game.ini settings
set_configs :: (filename : string) {
	path := tprint("config/%.ini", filename);
	buffer, success := read_entire_file(path);
	defer(free(buffer));

	if !success {
		print("Failed to load config: %\n", path);
		return;
	}

	lines := split(buffer, "\n");
	for lines {
		line := trim(it);

		if line.count == 0 continue;
		if begins_with_nocase(line, "#") continue;

		statement := split(line, "=");

		if statement.count != 2 {
			print("\t[ERROR] malformed line: %\n", line);
			continue;
		}

		key := statement[0];
		value := trim(statement[1]);
		if key== {
			case "root";  {
				string_reset(*level_root);
				level_root = sprint(value);
			}
			case "start"; {
				string_reset(*level_start);
				level_start = sprint(value);
			}
		}
	}

	print("~~~ Loaded configs: % ~~~\n", path);
	print("\troot: %\n", level_root);
	print("\tstart: %\n", level_start);
}

#load "engine.jai";
