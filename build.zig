const std = @import("std");

pub fn build(b: *std.build.Builder) void {
     const target = b.standardTargetOptions(.{});
     const optimize = b.standardOptimizeOption(.{});
    const ggmlObject = b.addObject(.{
        //.root_source_file = .{ .path = "ggml.c"},
        .name = "ggml.o",
        .target = target,
        .optimize = optimize
    });
    ggmlObject.addIncludePath("./");
    ggmlObject.addIncludePath("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include");
     ggmlObject.addCSourceFiles(&.{
     "ggml.c",
    },
    //-O3 -DNDEBUG -std=c11   -fPIC -pthread -DGGML_USE_ACCELERATE
    &.{
        // "-F/ggmlObjectrary/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks",
        "-std=c11",
        "-O3",
        "-DNDEBUG",
        "-fPIC",
        "-pthread",
        "-DGGML_USE_ACCELERATE"
    });
    // We just need the header files for the Accelerate Framework for creating the 
    // object file 
    // The main file step will use the dynamic library to link 
    ggmlObject.linkFramework("Accelerate");
    ggmlObject.linkLibC();    

    var cxxFlags = &.{
        "-O3",
        "-DNDEBUG",
        "-std=c++11",
        "-fPIC",
        "-pthread"
    };
    const whisperObject = b.addObject(.{
        .name = "whisper.o",
        .target = target,
        .optimize = optimize
    });
    whisperObject.addIncludePath("./");
    whisperObject.addIncludePath("./examples");
    whisperObject.addCSourceFile("whisper.cpp", cxxFlags);
    whisperObject.linkLibCpp();

    var mainFile = b.addExecutable(.{
        .name = "main",
        });
    mainFile.addIncludePath("./");
    mainFile.addIncludePath("./examples");
    mainFile.addCSourceFiles(&.{"examples/main/main.cpp", "examples/common.cpp"}, cxxFlags);
    mainFile.addObject(whisperObject);
    mainFile.addObject(ggmlObject);
    mainFile.linkFramework("Accelerate");
    mainFile.install();
}
