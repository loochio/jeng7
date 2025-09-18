// editor2.jai - Game F - 18 Sept 2025
// Level Editor - v2


editor2_plugin := EnginePlugin.{
	name = "editor2",
	proc_init 	= editor2_init,
	proc_deinit = editor2_deinit,
	proc_begin 	= editor2_begin,
	proc_end 	= editor2_end,
	proc_tick 	= editor2_tick,
	proc_render = editor2_render,
};

//@TODO unused hooks, maybe remove these? it depends if we want to pause/resume plugins
editor2_begin :: () {}
editor2_end :: () {}

editor2_init :: () {
	//@TODO register terminal commands

	//@TODO ui init
	/* ui widgets
		subwindow - level info 
		subwindow - tools (actor, warps, tilemap)
		subwindow - inspector (spawners, actors, tilemaps, etc)
	*/
}

editor2_deinit :: () {}

editor2_tick :: (dt : float) {}
editor2_render :: (dt : float) {}
