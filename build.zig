const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.build.Builder) !void {
    var basic_cflags = [_][]const u8{ "-I.", "-O3", "-std=c11", "-fPIC", "-pthread" };
    var basic_cppflags = .{ "-I.", "-I./examples", "-O3", "-std=c++11", "-fPIC", "-pthread" };
    var alloc = b.allocator;
    var c_flags = std.ArrayList([]const u8).init(alloc);
    var cpp_flags = std.ArrayList([]const u8).init(alloc);
    defer c_flags.deinit();
    defer cpp_flags.deinit();
    try c_flags.appendSlice(&basic_cflags);
    try cpp_flags.appendSlice(&basic_cppflags);
    // var ld_flags = [_][]const u8{};

    const target = b.standardTargetOptions(.{});

    var target_cpu = builtin.cpu;
    var all_features = target_cpu.features;
    if (target_cpu.arch.isX86()) {
        const x86_target = std.Target.x86;
        if (x86_target.featureSetHas(all_features, x86_target.Feature.f16c)) {
            try c_flags.append("-mf16c");
        }
        if (x86_target.featureSetHas(all_features, x86_target.Feature.fma)) {
            try c_flags.append("-mfma");
        }

        if (x86_target.featureSetHas(all_features, x86_target.Feature.avx)) {
            try c_flags.append("-mavx");
        }

        if (x86_target.featureSetHas(all_features, x86_target.Feature.avx2)) {
            try c_flags.append("-mavx2");
        }

        if (x86_target.featureSetHas(all_features, x86_target.Feature.sse3)) {
            try c_flags.append("-msse3");
        }
    }
    if (target_cpu.arch.isPPC64()) {
        const ppc64_target = std.Target.powerpc;
        if (ppc64_target.featureSetHas(all_features, ppc64_target.Feature.power9_vector)) {
            try c_flags.append("-mpower9-vector");
        }
        try cpp_flags.append("-std=c++23");
        try cpp_flags.append("-DGGML_BIG_ENDIAN");
    }

    //TODO: How do I get arbitrary flags here
    var maybe_use_accelerate = b.option(bool, "macos_accelerate", "use the accelerate framework in macOS (if available) for ML models");
    if (maybe_use_accelerate) |use_accelerate| {
        if (use_accelerate) {
            try c_flags.append("-DGGML_USE_ACCELERATE");
        }
    }

    var maybe_use_openblas = b.option(bool, "use_openblas", "use open BLAS when available");
    if (maybe_use_openblas) |use_openblas| {
        if (use_openblas) {
            try c_flags.appendSlice(&.{ "-DGGML_USE_OPENBLAS", "-I/usr/local/include/openblas" });
        }
    }
    var maybe_use_gprof = b.option(bool, "gprof", "use gnu prof");
    if (maybe_use_gprof) |use_gprof| {
        if (use_gprof) {
            try c_flags.append("-pg");
            try cpp_flags.append("-pg");
        }
    }

    if (!target_cpu.arch.isAARCH64()) {
        try c_flags.append("-mcpu=native");
        try cpp_flags.append("-mcpu=native");
    }

    if (target_cpu.arch.isARM()) {
        if (!std.mem.startsWith(u8, target_cpu.model.name, "armv6")) {
            try c_flags.appendSlice(&.{ "-mfpu=neon-fp-armv8", "-mfp16-format=ieee", "-mno-unaligned-access" });
        }
        if (!std.mem.startsWith(u8, target_cpu.model.name, "armv7")) {
            try c_flags.appendSlice(&.{ "-mfpu=neon-fp-armv8", "-mfp16-format=ieee", "-mno-unaligned-access", "-funsafe-math-optimizations" });
        }

        if (!std.mem.startsWith(u8, target_cpu.model.name, "armv8")) {
            try c_flags.appendSlice(&.{ "-mfp16-format=ieee", "-mno-unaligned-access" });
        }
    }
    //TODO: Flags for accelerate, aarch64, arm and rpi
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
    }, c_flags.items);
    // We just need the header files for the Accelerate Framework for creating the
    // object file
    // The main file step will use the dynamic library to link
    if (maybe_use_accelerate) |use_accelerate| {
        if (use_accelerate) {
            ggmlObject.linkFramework("Accelerate");
        }
    }
    if (maybe_use_openblas) |open_blas| {
        if (open_blas) {
            ggmlObject.linkSystemLibraryName("openblas");
        }
    }
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
