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
    }

    const install_tests_step = b.step("install-tests", "Install all test executables");

    for (test_sources) |sub_path| {
        const name = b.dupe(std.fs.path.stem(sub_path));
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
                .link_libcpp = std.mem.eql(u8, std.fs.path.extension(sub_path), ".cpp"),
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
