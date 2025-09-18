// build.jai 
// 13 Sept 2025

EXE_NAME := "GameF";
OUTPUT_PATH := "";

TARGET_PLUGIN_GAME :: #string DONE
default_plugin := "game";
DONE

TARGET_PLUGIN_EDITOR :: #string DONE
default_plugin := "editor";
DONE

TARGET_PLUGIN_EDITOR2 :: #string DONE
default_plugin := "editor2";
DONE

#run {
	workspace := compiler_create_workspace("Target workspace");
	options := get_build_options(workspace);
	options.output_executable_name = EXE_NAME;
	options.output_path = OUTPUT_PATH;
	set_build_options(options, workspace);

	compiler_begin_intercept(workspace);
    add_build_file("src/main.jai", workspace);
    set_build_options_dc(.{do_output=false});

    // parse for our starting plugin
    args := options.compile_time_command_line;
    set_default_plugin := false;
    for arg: args {
    	print("arg=%\n", arg);
        if arg == {
          case "editor"; {
          	add_build_string(TARGET_PLUGIN_EDITOR, workspace);
          	print("Building for plugin: [editor]\n");
          	set_default_plugin = true;
          }
          case "editor2"; {
          	add_build_string(TARGET_PLUGIN_EDITOR2, workspace);
          	print("Building for plugin: [editor2]\n");
          	set_default_plugin = true;
          }
        }
    }

    if !set_default_plugin {
    	add_build_string(TARGET_PLUGIN_GAME, workspace);
        print("Building for plugin: [game]\n");
    }

    compiler_end_intercept(workspace);
};

#import "Basic";
#import "Compiler";