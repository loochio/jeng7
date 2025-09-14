// build.jai 
// 13 Sept 2025

EXE_NAME := "GameF";
OUTPUT_PATH := "";

#run {
	workspace := compiler_create_workspace("Target workspace");
	options := get_build_options(workspace);
	options.output_executable_name = EXE_NAME;
	options.output_path = OUTPUT_PATH;
	set_build_options(options, workspace);

	compiler_begin_intercept(workspace);
    add_build_file("src/main.jai", workspace);
    set_build_options_dc(.{do_output=false});
    compiler_end_intercept(workspace);
};

#import "Compiler";