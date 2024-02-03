const std = @import("std");

pub fn build(b: *std.Build) !void {
    const cflags = &[_][]const u8{
        "-O3",
        "-fPIC",
        "-flto=thin",
        "-fvisibility=default",
        "-std=c2x",
        "-D_GNU_SOURCE",
        "-DCONFIG_VERSION=\"0.1.0\"",
        "-mllvm",
        "-polly",
        "-mllvm",
        "-polly-parallel",
        "-fopenmp",
        "-mllvm",
        "-polly-vectorizer=stripmine",
    };

    const ldflags = &[_][]const u8{
        "-O3",
        "-fPIC",
        "-flto=thin",
        "-fuse-ld=lld",
        "-Wl,--emit-relocs",
        "-march=x86-64-v3",
        "-lm",
    };

    const lib_objects = &[_][]const u8{
        "quickjs/quickjs.c",
        "quickjs/libregexp.c",
        "quickjs/cutils.c",
        "quickjs/libunicode.c",
        "quickjs/quickjs-libc.c",
        "quickjs/libbf.c",
    };

    const stage1_lib = b.addSystemCommand(&[_][]const u8{
        "clang",
        "-shared",
        "-fprofile-instr-generate",
        "-o",
        "libqjs-stage1.so",
    } ++ cflags ++ ldflags ++ lib_objects);

    const stage1 = b.addSystemCommand(&[_][]const u8{
        "clang",
        "-o",
        "run-test262-stage1",
        "-fprofile-instr-generate",
        "quickjs/run-test262.c",
        "-L.",
        "-lqjs-stage1",
    } ++ cflags ++ ldflags);
    stage1.step.dependOn(&stage1_lib.step);

    const run_stage1 = b.addSystemCommand(&[_][]const u8{
        "env",
        "LD_LIBRARY_PATH=.:/home/theo/llvm-builds/install/lib:/home/theo/llvm-builds/install/lib/x86_64-unknown-linux-gnu",
        "LLVM_PROFILE_FILE=run-test262-stage1.profraw",
        "./run-test262-stage1",
        "-m",
        "-c",
        "quickjs/test262.conf",
        "-a",
    });
    run_stage1.step.dependOn(&stage1.step);

    const stage2_lib = b.addSystemCommand(&[_][]const u8{
        "clang",
        "-shared",
        "-fprofile-instr-use=run-test262-stage1.profraw",
        "-o",
        "libqjs-stage2.so",
    } ++ cflags ++ ldflags ++ lib_objects);
    stage2_lib.step.dependOn(&run_stage1.step);

    const stage2 = b.addSystemCommand(&[_][]const u8{
        "clang",
        "-o",
        "run-test262-stage2",
        "-fprofile-instr-use=run-test262-stage1.profraw",
        "quickjs/run-test262.c",
        "-L.",
        "-lqjs-stage2",
    } ++ cflags ++ ldflags);
    stage2.step.dependOn(&stage2_lib.step);

    const run_bolt = b.addSystemCommand(&[_][]const u8{
        "llvm-bolt",
        "-p",
        "run-test262-stage2.profraw",
        "-o",
        "run-test262-stage2-bolted",
        "run-test262-stage2",
    });
    run_bolt.step.dependOn(&stage2.step);

    const run_stage2 = b.addSystemCommand(&[_][]const u8{
        "env",
        "LD_LIBRARY_PATH=.:/home/theo/llvm-builds/install/lib:/home/theo/llvm-builds/install/lib/x86_64-unknown-linux-gnu",
        "LLVM_PROFILE_FILE=run-test262-stage2.profraw",
        "./run-test262-stage2-bolted",
        "-m",
        "-c",
        "quickjs/test262.conf",
        "-a",
    });
    run_stage2.step.dependOn(&run_bolt.step);

    const run_all = b.step("run", "Run all tests");
    run_all.dependOn(&run_stage2.step);
}
