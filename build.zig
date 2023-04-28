const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.build.Builder) void {
    if (falseMacx86_64()) {
        std.debug.print("Your arch is announced as x86_64, but it seems to actually be ARM64. Not fixing that can lead to bad performance. For more info see: https://github.com/ggerganov/whisper.cpp/issues/66#issuecomment-1282546789\n", .{});
        return;
    }

    // var default_c_flags = .{ "-I.", "-O3", "-std=c11", "-fPIC", "-pthread" };
    // var default_cpp_flags = .{ "-I.", "-I./examples", "-O3", "-std=c++11", "-fPIC", "-pthread" };
    // var ld_flags = [_][]const u8{};

    const target = b.standardTargetOptions(.{});

    var target_cpu = target.getCpuArch();
    if (target_cpu.isX86()) {
        std.debug.print("all features\n {any}\n", .{target_cpu.allFeaturesList()});
    } else if (target_cpu.isAARCH64()) {
        var all_features = target_cpu.allFeaturesList();
        for (all_features) |feature| {
            std.debug.print("feature: {s}\n", .{feature.name});
        }
    } else {}
    const optimize = b.standardOptimizeOption(.{});
    const ggmlObject = b.addObject(.{
        .name = "ggml.o",
        .target = target,
        .optimize = optimize,
    });
    ggmlObject.addIncludePath("./");
    ggmlObject.addIncludePath("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include");
    ggmlObject.addCSourceFiles(&.{
        "ggml.c",
    },
    //-O3 -DNDEBUG -std=c11   -fPIC -pthread -DGGML_USE_ACCELERATE
    &.{
        "-std=c11",
        "-O3",
        "-DNDEBUG",
        "-fPIC",
        "-pthread",
        "-DGGML_USE_ACCELERATE",
    });
    // We just need the header files for the Accelerate Framework for creating the
    // object file
    // The main file step will use the dynamic library to link
    ggmlObject.linkFramework("Accelerate");
    ggmlObject.linkLibC();

    var cxxFlags = &.{ "-O3", "-DNDEBUG", "-std=c++11", "-fPIC", "-pthread" };
    const whisperObject = b.addObject(.{ .name = "whisper.o", .target = target, .optimize = optimize });
    whisperObject.addIncludePath("./");
    whisperObject.addIncludePath("./examples");
    whisperObject.addCSourceFile("whisper.cpp", cxxFlags);
    whisperObject.linkLibCpp();

    // zig automatically adds `lib` prefix and a `.a` suffix
    var lib_static_library = b.addStaticLibrary(.{ .name = "whisper", .optimize = optimize, .target = target });
    lib_static_library.addObject(ggmlObject);
    lib_static_library.addObject(whisperObject);

    var lib_dynamic = b.addSharedLibrary(.{ .name = "whisper", .optimize = optimize, .target = target });
    lib_dynamic.addObject(ggmlObject);
    lib_dynamic.addObject(whisperObject);
    b.installArtifact(lib_dynamic);
    b.installArtifact(lib_static_library);
    // var mainFile = b.addExecutable(.{ .name = "main", .optimize = optimize, .target = target });
    var mainFile = b.addExecutable(.{ .name = "main" });
    mainFile.addIncludePath("./");
    mainFile.addIncludePath("./examples");
    mainFile.addCSourceFiles(&.{ "examples/main/main.cpp", "examples/common.cpp" }, cxxFlags);
    mainFile.addObject(whisperObject);
    mainFile.addObject(ggmlObject);
    mainFile.linkFramework("Accelerate");
    b.installArtifact(mainFile);
}

pub fn falseMacx86_64() bool {
    if (builtin.target.isDarwin()) {
        var opt_cpu: i32 = 0;
        var len: usize = 4;
        _ = std.os.darwin.sysctlbyname("hw.optional.cpu", &opt_cpu, &len, null, 0);
        if (opt_cpu == 1) {
            return true;
        } else {
            return false;
        }
    } else {
        return false;
    }
}
