const std = @import("std");

pub fn build(b: *std.Build) void {
    const upstream = b.dependency("nativefiledialog-extended", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Link mode") orelse .static;
    const strip = b.option(bool, "strip", "Omit debug information");
    const pic = b.option(bool, "pie", "Produce Position Independent Code");

    const portal = b.option(bool, "portal", "Use xdg-desktop-portal instead of GTK") orelse false;
    const append_extension = b.option(bool, "append-extension", "Automatically append file extension to an extensionless selection in SaveDialog()") orelse false;
    const override_recent_with_default = b.option(bool, "override-recent-with-default", "Use defaultPath instead of recent folder on Windows") orelse false;

    const enable_x11 = b.option(bool, "x11", "Support X11 on Linux") orelse true;
    const enable_wayland = b.option(bool, "wayland", "Support Wayland on Linux") orelse true;

    const flags: []const []const u8 = &.{
        "-nostdlib",
        "-fno-exceptions",
        "-fno-rtti",
    };

    const nfd = b.addLibrary(.{
        .linkage = linkage,
        .name = "nfd",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .pic = pic,
            .strip = strip,
        }),
    });
    b.installArtifact(nfd);
    nfd.root_module.addIncludePath(upstream.path("src/include"));
    nfd.installHeadersDirectory(upstream.path("src/include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    if (target.result.os.tag == .windows) {
        nfd.root_module.link_libcpp = true;
        nfd.root_module.addCSourceFile(.{ .file = upstream.path("src/nfd_win.cpp"), .flags = flags });
        nfd.root_module.linkSystemLibrary("ole32", .{});
        nfd.root_module.linkSystemLibrary("uuid", .{});
        nfd.root_module.linkSystemLibrary("shell32", .{});
        if (override_recent_with_default) nfd.root_module.addCMacro("NFD_OVERRIDE_RECENT_WITH_DEFAULT", "1");
    } else if (target.result.os.tag.isDarwin()) {
        // Whether this is correct is completely untested since I don't use macOS.

        nfd.root_module.addCSourceFile(.{ .file = upstream.path("src/nfd_cocoa.m"), .flags = flags });
        nfd.root_module.linkFramework("AppKit", .{});

        // Zig has dropped support for MacOS 12
        // https://github.com/ziglang/zig/commit/21f0fce28bcceb5ee227f456401f250d9c62b31b
        nfd.root_module.addCMacro("NFD_MACOS_ALLOWEDCONTENTTYPES", "1");
        nfd.root_module.linkFramework("UniformTypeIdentifiers", .{});
    } else {
        nfd.root_module.link_libcpp = true;
        if (append_extension) nfd.root_module.addCMacro("NFD_APPEND_EXTENSION", "1");
        if (portal) {
            nfd.root_module.addCSourceFile(.{ .file = upstream.path("src/nfd_portal.cpp"), .flags = flags });
            nfd.root_module.linkSystemLibrary("dbus-1", .{});
            nfd.root_module.addCMacro("NFD_PORTAL", "1");
        } else {
            nfd.root_module.addCSourceFile(.{ .file = upstream.path("src/nfd_gtk.cpp"), .flags = flags });
            nfd.root_module.linkSystemLibrary("gtk+-3.0", .{});
        }
        if (enable_x11) nfd.root_module.addCMacro("NFD_X11", "1");
        if (enable_wayland) skip_wayland: {
            nfd.root_module.addCMacro("NFD_WAYLAND", "1");

            if (b.systemIntegrationOption("wayland-client", .{})) {
                nfd.root_module.linkSystemLibrary("wayland-client", .{});
            } else if (b.lazyDependency("wayland", .{
                .target = target,
                .optimize = optimize,
            })) |wayland| {
                nfd.root_module.linkLibrary(wayland.artifact("wayland-client"));
            }

            const use_system_wayland_scanner = b.systemIntegrationOption("wayland-scanner", .{});
            const host_wayland = if (!use_system_wayland_scanner)
                b.lazyDependency("wayland", .{
                    .target = b.graph.host,
                    .optimize = std.builtin.OptimizeMode.Debug,
                })
            else
                null;

            const use_system_wayland_protocols = b.systemIntegrationOption("wayland-protocols", .{});

            const wayland_protocols: std.Build.LazyPath = if (use_system_wayland_protocols) blk: {
                const pkgdatadir = b.run(&.{
                    b.graph.environ_map.get("PKG_CONFIG") orelse "pkg-config",
                    "wayland-protocols",
                    "--variable=pkgdatadir",
                });
                break :blk .{ .cwd_relative = std.mem.trim(u8, pkgdatadir, &std.ascii.whitespace) };
            } else if (b.lazyDependency("wayland_protocols", .{})) |wayland_protocols|
                wayland_protocols.path(".")
            else
                break :skip_wayland;

            const run_wayland_scanner1: *std.Build.Step.Run = .create(b, "run wayland-scanner");
            const run_wayland_scanner2: *std.Build.Step.Run = .create(b, "run wayland-scanner");
            if (use_system_wayland_scanner) {
                run_wayland_scanner1.addArg("wayland-scanner");
                run_wayland_scanner2.addArg("wayland-scanner");
            } else if (host_wayland) |wayland_host| {
                run_wayland_scanner1.addArtifactArg(wayland_host.artifact("wayland-scanner"));
                run_wayland_scanner2.addArtifactArg(wayland_host.artifact("wayland-scanner"));
            }

            run_wayland_scanner1.addArg("client-header");
            run_wayland_scanner1.addFileArg(wayland_protocols.path(b, "unstable/xdg-foreign/xdg-foreign-unstable-v1.xml"));
            const header_file = run_wayland_scanner1.addOutputFileArg("xdg-foreign-unstable-v1.h");
            nfd.root_module.addIncludePath(header_file.dirname());

            run_wayland_scanner2.addArg("public-code");
            run_wayland_scanner2.addFileArg(wayland_protocols.path(b, "unstable/xdg-foreign/xdg-foreign-unstable-v1.xml"));
            const source_file = run_wayland_scanner2.addOutputFileArg("xdg-foreign-unstable-v1.c");
            nfd.root_module.addCSourceFile(.{ .file = source_file });
        }
    }

    const install_tests_step = b.step("install-tests", "Install all test executables");

    for (test_sources) |sub_path| {
        const name = b.allocator.dupe(u8, std.Io.Dir.path.stem(sub_path)) catch @panic("OOM");
        std.mem.replaceScalar(u8, name, '.', '-');
        std.mem.replaceScalar(u8, name, '_', '-');

        const test_exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .pic = pic,
                .strip = strip,
                .link_libc = true,
                .link_libcpp = std.mem.eql(u8, std.Io.Dir.path.extension(sub_path), ".cpp"),
            }),
        });
        test_exe.root_module.addCSourceFile(.{ .file = upstream.path(b.fmt("test/{s}", .{sub_path})), .flags = flags });
        test_exe.root_module.linkLibrary(nfd);

        install_tests_step.dependOn(&b.addInstallArtifact(test_exe, .{}).step);

        const run_test_exe = b.addRunArtifact(test_exe);

        const test_step = b.step(name, b.fmt("Run {s}", .{sub_path}));
        test_step.dependOn(&run_test_exe.step);
    }
}

const test_sources: []const []const u8 = &.{
    "test_opendialog.c",
    "test_opendialog_cpp.cpp",
    "test_opendialog_native.c",
    "test_opendialog_with.c",
    "test_opendialog_native_with.c",
    "test_opendialogmultiple.c",
    "test_opendialogmultiple_cpp.cpp",
    "test_opendialogmultiple_native.c",
    "test_opendialogmultiple_enum.c",
    "test_opendialogmultiple_enum_native.c",
    "test_pickfolder.c",
    "test_pickfolder_cpp.cpp",
    "test_pickfolder_native.c",
    "test_pickfolder_with.c",
    "test_pickfolder_native_with.c",
    "test_pickfoldermultiple.c",
    "test_pickfoldermultiple_native.c",
    "test_savedialog.c",
    "test_savedialog_native.c",
    "test_savedialog_with.c",
    "test_savedialog_native_with.c",
};
