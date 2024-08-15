[![CI](https://github.com/allyourcodebase/nativefiledialog-extended/actions/workflows/ci.yaml/badge.svg)](https://github.com/allyourcodebase/nativefiledialog-extended/actions)

# nativefiledialog-extended

This is [nativefiledialog-extended](https://github.com/btzy/nativefiledialog-extended), packaged for [Zig](https://ziglang.org/).

## Installation

First, update your `build.zig.zon`:

```
# Initialize a `zig build` project if you haven't already
zig init
zig fetch --save git+https://github.com/allyourcodebase/nativefiledialog-extended.git#1.2.1
```

You can then import `nativefiledialog-extended` in your `build.zig` with:

```zig
const nfd_dependency = b.dependency("nativefiledialog-extended", .{
    .target = target,
    .optimize = optimize,
});
your_exe.linkLibrary(nfd_dependency.artifact("nfd"));
```

## Dependencies

See https://github.com/btzy/nativefiledialog-extended/tree/v1.2.1#dependencies
