const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("ZagEngine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "ZagEngine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "ZagEngine", .module = mod },
            },
        }),
    });

    exe.root_module.link_libc = true;
    exe.root_module.linkSystemLibrary("SDL3", .{});
    exe.root_module.linkSystemLibrary("vulkan", .{});

    // --------------------------------------------------
    // Shader compilation
    // --------------------------------------------------

    const Shader = struct {
        source: []const u8,
        output: []const u8,
        import_name: []const u8,
    };

    const shaders = [_]Shader{
        .{
            .source = "shaders/triangle.vert",
            .output = "triangle.vert.spv",
            .import_name = "triangle_vert",
        },
        .{
            .source = "shaders/triangle.frag",
            .output = "triangle.frag.spv",
            .import_name = "triangle_frag",
        },
    };

    for (shaders) |shader| {
        const compile = b.addSystemCommand(&.{
            "glslc",
            "--target-env=vulkan1.0",
            "-o",
        });

        const spirv = compile.addOutputFileArg2(
            shader.output,
            .{},
        );

        compile.addFileArg2(
            b.path(shader.source),
            .{},
        );

        // Make the compiled SPIR-V available to main.zig.
        exe.root_module.addAnonymousImport(
            shader.import_name,
            .{
                .root_source_file = spirv,
            },
        );
    }

    // --------------------------------------------------
    // Install executable
    // --------------------------------------------------

    b.installArtifact(exe);

    // --------------------------------------------------
    // Run
    // --------------------------------------------------

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    // --------------------------------------------------
    // Tests
    // --------------------------------------------------

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");

    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
