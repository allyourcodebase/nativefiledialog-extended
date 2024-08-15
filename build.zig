const std = @import("std");

pub fn build(b: *std.Build) void {
    const upstream = b.dependency("nativefiledialog-extended", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Omit debug information");
    const pic = b.option(bool, "pie", "Produce Position Independent Code");

    const portal = b.option(bool, "portal", "Use xdg-desktop-portal instead of GTK") orelse false;
    const use_allowedcontenttypes_if_available = b.option(bool, "use-allowedcontenttypes-if-available", "Use allowedContentTypes for filter lists on macOS >= 11.0") orelse true;
    const append_extension = b.option(bool, "append-extension", "Automatically append file extension to an extensionless selection in SaveDialog()") orelse false;

    const nfd = b.addStaticLibrary(.{
        .name = "nfd",
        .target = target,
        .optimize = optimize,
        .pic = pic,
        .strip = strip,
    });
    b.installArtifact(nfd);
    nfd.addIncludePath(upstream.path("src/include"));
    nfd.installHeadersDirectory(upstream.path("src/include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    if (target.result.os.tag == .windows) {
        nfd.linkLibCpp();
        nfd.addCSourceFile(.{ .file = upstream.path("src/nfd_win.cpp") });
        nfd.linkSystemLibrary("ole32");
        nfd.linkSystemLibrary("uuid");
        nfd.linkSystemLibrary("shell32");
    } else if (target.result.os.tag.isDarwin()) {
        nfd.addCSourceFile(.{ .file = upstream.path("src/nfd_cocoa.m") });
        nfd.linkFramework("AppKit");
        // Whether this is correct is completely untested since I don't use macOS.
        nfd.root_module.addCMacro("NFD_MACOS_ALLOWEDCONTENTTYPES", if (use_allowedcontenttypes_if_available) "1" else "0");
        if (use_allowedcontenttypes_if_available and target.result.os.isAtLeast(.macos, .{ .major = 11, .minor = 0, .patch = 0 }).?) {
            nfd.linkFramework("UniformTypeIdentifiers");
        }
    } else {
        nfd.linkLibCpp();
        if (append_extension) nfd.root_module.addCMacro("NFD_APPEND_EXTENSION", "1");
        if (portal) {
            nfd.addCSourceFile(.{ .file = upstream.path("src/nfd_portal.cpp") });
            nfd.linkSystemLibrary("dbus-1");
            nfd.root_module.addCMacro("NFD_PORTAL", "1");
        } else {
            nfd.addCSourceFile(.{ .file = upstream.path("src/nfd_gtk.cpp") });
            nfd.linkSystemLibrary("gtk+-3.0");
        }
    }

    const install_tests_step = b.step("install-tests", "Install all test executables");

    for (test_sources) |sub_path| {
        const name = b.dupe(std.fs.path.stem(sub_path));
        std.mem.replaceScalar(u8, name, '.', '-');
        std.mem.replaceScalar(u8, name, '_', '-');

        const test_exe = b.addExecutable(.{
            .name = name,
            .target = target,
            .optimize = optimize,
            .pic = pic,
            .strip = strip,
        });
        test_exe.addCSourceFile(.{ .file = upstream.path("test").path(b, sub_path) });
        test_exe.linkLibrary(nfd);

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
