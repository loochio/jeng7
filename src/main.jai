/* main.jai
Game F prototype
13 Sept 2025

Idea: Recusive level warping
Inspirations: Coccoon | Patrick's Parabox

Forked this engine version due to a difficult collection of memory issues that I finally fixed.
I was encountering undefined behavior when toggling between game/editor.
This was due to several cases of double freeing memory. woops
*/

engine_cfg := EngineConfig.{
	name = "Game F",
	world_width = 640,
	world_height = 480,
	window_width = 1920,
	window_height = 1080,
	aspect = 640. / 480.,
	x = 300,
	y = 100,
	bg_color = G_GREY4,
	
	asset_folder = "assets",
	img_folder = "/img",
	font = "OpenSans-BoldItalic.ttf",

	vsync = false,
};

main :: () {

	//@CLEAN
	//#if DEVELOPER {
	//	default_plugin = "editor";
	//}

	print("main - detected default plugin [%]\n", default_plugin); // defined in build.jai
	engine_cfg.startup_plugin = default_plugin;

	array_add(*engine_cfg.plugins, game_plugin);
	array_add(*engine_cfg.plugins, editor_plugin);
	engine_init(engine_cfg);
}

#load "game.jai";
#load "editor.jai";
