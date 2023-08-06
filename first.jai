#run {
    #import "Compiler";
    #import "Basic";

    options := get_build_options();
    set_build_options_dc(.{ do_output = false });

    w := compiler_create_workspace("Pathtracer");

    options.output_executable_name = "pathtracer";
    options.output_path            = "build";

    machine_optimization := options.llvm_options.machine_code_optimization_setting;
    bitcode_optimization := options.llvm_options.bitcode_optimization_setting;
    print("Compiling % build using optimization setting '% (%)'...\n",
            ifx machine_optimization > .NONE then "release" else "debug", machine_optimization, bitcode_optimization);

    set_build_options(options, w);

    add_build_file("pathtracer.jai", w);
}
