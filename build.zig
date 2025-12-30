const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("minhook", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const c_flags: []const []const u8 = &.{
        "-DWIN32_LEAN_AND_MEAN",
        "-D_WIN32_WINNT=0x0501",
        "-fno-sanitize=alignment",
    };

    mod.addCSourceFiles(.{
        .root = b.path("vendor/minhook/src"),
        .files = &.{
            "buffer.c",
            "hook.c",
            "trampoline.c",
        },
        .flags = c_flags,
    });

    const cpu_arch = target.result.cpu.arch;
    if (cpu_arch == .x86_64) {
        mod.addCSourceFile(.{
            .file = b.path("vendor/minhook/src/hde/hde64.c"),
            .flags = c_flags,
        });
    } else if (cpu_arch == .x86) {
        mod.addCSourceFile(.{
            .file = b.path("vendor/minhook/src/hde/hde32.c"),
            .flags = c_flags,
        });
    }

    mod.addIncludePath(b.path("vendor/minhook/include"));
    mod.addIncludePath(b.path("vendor/minhook/src"));
    mod.addIncludePath(b.path("vendor/minhook/src/hde"));

    const static = b.addLibrary(.{
        .name = "minhook",
        .root_module = mod,
        .linkage = .static,
    });
    const shared = b.addLibrary(.{
        .name = "minhook",
        .root_module = mod,
        .linkage = .dynamic,
    });

    b.installArtifact(static);
    b.installArtifact(shared);

    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
