const std = @import("std");
const builtin = @import("builtin");
const arch = builtin.cpu.arch;

const c = @cImport({
    @cInclude("MinHook.h");
});
pub const raw = c;

pub const WINAPI: std.builtin.CallingConvention = if (arch == .x86) .{ .x86_stdcall = .{} } else .{ .x86_64_win = .{} };
pub const CDECL: std.builtin.CallingConvention = if (arch == .x86) .{ .x86_win = .{} } else .{ .x86_64_win = .{} };
pub const FASTCALL: std.builtin.CallingConvention = if (arch == .x86) .{ .x86_fastcall = .{} } else .{ .x86_64_win = .{} };
pub const THISCALL: std.builtin.CallingConvention = if (arch == .x86) .{ .x86_thiscall = .{} } else .{ .x86_64_win = .{} };
pub const THISCALL_MINGW: std.builtin.CallingConvention = if (arch == .x86) .{ .x86_thiscall_mingw = .{} } else .{ .x86_64_win = .{} };
pub const VECTORCALL: std.builtin.CallingConvention = if (arch == .x86) .{ .x86_vectorcall = .{} } else .{ .x86_64_vectorcall = .{} };

pub const Status = enum(c_int) {
    /// Unknown error. Should not be returned.
    unknown = -1,
    /// Successful.
    ok = 0,
    /// MinHook is already initialized.
    already_initialized = 1,
    /// MinHook is not initialized yet, or already uninitialized.
    not_initialized = 2,
    /// The hook for the specified target function is already created.
    already_created = 3,
    /// The hook for the specified target function is not created yet.
    not_created = 4,
    /// The hook for the specified target function is already enabled.
    enabled = 5,
    /// The hook for the specified target function is not enabled yet, or already disabled.
    disabled = 6,
    /// The specified pointer is invalid. It points the address of non-allocated and/or non-executable region.
    not_executable = 7,
    /// The specified target function cannot be hooked.
    unsupported_function = 8,
    /// Failed to allocate memory.
    memory_alloc = 9,
    /// Failed to change the memory protection.
    memory_protect = 10,
    /// The specified module is not loaded.
    module_not_found = 11,
    /// The specified function is not found.
    function_not_found = 12,
};

pub const Error = error{
    Unknown,
    AlreadyInitialized,
    NotInitialized,
    AlreadyCreated,
    NotCreated,
    Enabled,
    Disabled,
    NotExecutable,
    UnsupportedFunction,
    MemoryAlloc,
    MemoryProtect,
    ModuleNotFound,
    FunctionNotFound,
};

fn checkStatus(status: c.MH_STATUS) Error!void {
    return switch (@as(Status, @enumFromInt(status))) {
        .ok => {},
        .unknown => Error.Unknown,
        .already_initialized => Error.AlreadyInitialized,
        .not_initialized => Error.NotInitialized,
        .already_created => Error.AlreadyCreated,
        .not_created => Error.NotCreated,
        .enabled => Error.Enabled,
        .disabled => Error.Disabled,
        .not_executable => Error.NotExecutable,
        .unsupported_function => Error.UnsupportedFunction,
        .memory_alloc => Error.MemoryAlloc,
        .memory_protect => Error.MemoryProtect,
        .module_not_found => Error.ModuleNotFound,
        .function_not_found => Error.FunctionNotFound,
    };
}

/// A handle to a created hook.
/// The FnType should be a function pointer type with the correct calling convention.
///
/// ## Calling Convention Requirements
///
/// Your detour function MUST use the same calling convention as the target function.
/// Common conventions for Windows:
/// - `WINAPI` / `STDCALL`: Most Windows API functions (kernel32, user32, etc.)
/// - `CDECL`: Standard C functions, many game engines
/// - `FASTCALL`: Performance-critical code, some compiler intrinsics
/// - `THISCALL`: C++ member functions
/// - `VECTORCALL`: SIMD-heavy code
///
/// ## Example
/// ```zig
/// // For hooking MessageBoxW (which uses WINAPI/STDCALL):
/// const MessageBoxWFn = *const fn (
///     hwnd: ?std.os.windows.HWND,
///     text: ?[*:0]const u16,
///     caption: ?[*:0]const u16,
///     uType: u32,
/// ) callconv(minhook.WINAPI) i32;
/// ```
pub fn Hook(comptime FnType: type) type {
    const FnInfo = @typeInfo(FnType).pointer.child;
    const Args = std.meta.ArgsTuple(FnInfo);
    const ReturnType = @typeInfo(FnInfo).@"fn".return_type.?;

    return struct {
        const Self = @This();

        target: *anyopaque,
        original: FnType,

        /// Enable this hook
        pub fn enable(self: Self) Error!void {
            return checkStatus(c.MH_EnableHook(self.target));
        }

        /// Disable this hook
        pub fn disable(self: Self) Error!void {
            return checkStatus(c.MH_DisableHook(self.target));
        }

        /// Remove this hook entirely
        pub fn remove(self: Self) Error!void {
            return checkStatus(c.MH_RemoveHook(self.target));
        }

        /// Queue this hook to be enabled (call applyQueued to apply)
        pub fn queueEnable(self: Self) Error!void {
            return checkStatus(c.MH_QueueEnableHook(self.target));
        }

        /// Queue this hook to be disabled (call applyQueued to apply)
        pub fn queueDisable(self: Self) Error!void {
            return checkStatus(c.MH_QueueDisableHook(self.target));
        }

        /// Call the original function with the provided arguments.
        /// Use this from within your detour to invoke the original behavior.
        pub fn call(self: Self, args: Args) ReturnType {
            return @call(.auto, self.original, args);
        }
    };
}

/// Initialize the MinHook library.
/// You must call this function EXACTLY ONCE at the beginning of your program.
pub fn initialize() Error!void {
    return checkStatus(c.MH_Initialize());
}

/// Uninitialize the MinHook library.
/// You must call this function EXACTLY ONCE at the end of your program.
pub fn uninitialize() Error!void {
    return checkStatus(c.MH_Uninitialize());
}

/// Creates a hook for the specified target function, in disabled state.
/// Returns a Hook struct that can be used to enable/disable the hook and call the original function.
///
/// ## Parameters
/// - `FnType`: The function pointer type
/// - `target`: Pointer to the function to hook
/// - `detour`: Pointer to your replacement function (must have same signature and calling convention)
///
/// ## Example
/// ```zig
/// const hook = try minhook.create(@TypeOf(target_fn), target_fn, my_detour);
/// try hook.enable();
/// ```
pub fn create(comptime FnType: type, target: FnType, detour: FnType) Error!Hook(FnType) {
    var original: ?FnType = null;
    try checkStatus(c.MH_CreateHook(
        @ptrCast(@constCast(target)),
        @ptrCast(@constCast(detour)),
        @ptrCast(&original),
    ));
    return .{
        .target = @ptrCast(@constCast(target)),
        .original = original.?,
    };
}

/// Creates a hook for the specified API function, in disabled state.
///
/// ## Parameters
/// - `FnType`: The function pointer type
/// - `module_name`: The loaded module name (e.g., "user32", "kernel32")
/// - `proc_name`: The function name (e.g., "MessageBoxW")
/// - `detour`: Pointer to your replacement function
pub fn createApi(
    comptime FnType: type,
    module_name: [*:0]const u16,
    proc_name: [*:0]const u8,
    detour: FnType,
) Error!Hook(FnType) {
    var original: ?FnType = null;
    var target: ?*anyopaque = null;
    try checkStatus(c.MH_CreateHookApiEx(
        module_name,
        proc_name,
        @ptrCast(@constCast(detour)),
        @ptrCast(&original),
        @ptrCast(&target),
    ));
    return .{
        .target = target.?,
        .original = original.?,
    };
}

/// Enable all created hooks in one go.
pub fn enableAll() Error!void {
    return checkStatus(c.MH_EnableHook(null));
}

/// Disable all created hooks in one go.
pub fn disableAll() Error!void {
    return checkStatus(c.MH_DisableHook(null));
}

/// Queue all created hooks to be enabled.
pub fn queueEnableAll() Error!void {
    return checkStatus(c.MH_QueueEnableHook(null));
}

/// Queue all created hooks to be disabled.
pub fn queueDisableAll() Error!void {
    return checkStatus(c.MH_QueueDisableHook(null));
}

/// Remove all created hooks in one go.
pub fn removeAll() Error!void {
    return checkStatus(c.MH_RemoveHook(null));
}

/// Applies all queued changes in one go.
/// Use this with queueEnable/queueDisable for atomic hook state changes.
pub fn applyQueued() Error!void {
    return checkStatus(c.MH_ApplyQueued());
}

// ========= TESTS =========

test "double initialization error" {
    try initialize();
    defer uninitialize() catch {};

    const result = initialize();
    try std.testing.expectError(Error.AlreadyInitialized, result);
}

test "uninitialization without initialization error" {
    const result = uninitialize();
    try std.testing.expectError(Error.NotInitialized, result);
}

test "hook cdecl function" {
    const Impl = struct {
        const FnType = @TypeOf(&targetFn);
        var hook: Hook(FnType) = undefined;

        fn targetFn(a: i32, b: i32) callconv(CDECL) i32 {
            return a + b;
        }

        fn detourFn(a: i32, b: i32) callconv(CDECL) i32 {
            return hook.call(.{ a, b }) * 10;
        }
    };

    try initialize();
    defer uninitialize() catch {};

    const target = &Impl.targetFn;
    try std.testing.expectEqual(5, target(2, 3));

    Impl.hook = try create(Impl.FnType, target, &Impl.detourFn);
    try Impl.hook.enable();
    try std.testing.expectEqual(50, target(2, 3));

    try Impl.hook.disable();
    try std.testing.expectEqual(5, target(2, 3));
}

test "hook stdcall function" {
    const Impl = struct {
        const FnType = @TypeOf(&targetFn);
        var hook: Hook(FnType) = undefined;

        fn targetFn(a: i32, b: i32) callconv(WINAPI) i32 {
            return a + b;
        }

        fn detourFn(a: i32, b: i32) callconv(WINAPI) i32 {
            return hook.call(.{ a, b }) * 10;
        }
    };

    try initialize();
    defer uninitialize() catch {};

    const target = &Impl.targetFn;
    try std.testing.expectEqual(7, target(3, 4));

    Impl.hook = try create(Impl.FnType, target, &Impl.detourFn);
    try Impl.hook.enable();
    defer Impl.hook.disable() catch {};

    try std.testing.expectEqual(70, target(3, 4));
}

test "hook fastcall function" {
    const Impl = struct {
        const FnType = @TypeOf(&targetFn);
        var hook: Hook(FnType) = undefined;

        fn targetFn(a: i32, b: i32) callconv(FASTCALL) i32 {
            return a + b;
        }

        fn detourFn(a: i32, b: i32) callconv(FASTCALL) i32 {
            return hook.call(.{ a, b }) * 10;
        }
    };

    try initialize();
    defer uninitialize() catch {};

    const target = &Impl.targetFn;
    try std.testing.expectEqual(9, target(4, 5));

    Impl.hook = try create(Impl.FnType, target, &Impl.detourFn);
    try Impl.hook.enable();
    defer Impl.hook.disable() catch {};

    try std.testing.expectEqual(90, target(4, 5));
}

test "hook thiscall function" {
    const Impl = struct {
        const FnType = @TypeOf(&targetFn);
        var hook: Hook(FnType) = undefined;

        fn targetFn(self: *anyopaque, value: i32) callconv(THISCALL) i32 {
            _ = self;
            return value * 2;
        }

        fn detourFn(self: *anyopaque, value: i32) callconv(THISCALL) i32 {
            return hook.call(.{ self, value }) * 10;
        }
    };

    try initialize();
    defer uninitialize() catch {};

    var dummy: i32 = 0;
    const target = &Impl.targetFn;
    try std.testing.expectEqual(10, target(&dummy, 5));

    Impl.hook = try create(Impl.FnType, target, &Impl.detourFn);
    try Impl.hook.enable();
    defer Impl.hook.disable() catch {};

    try std.testing.expectEqual(100, target(&dummy, 5));
}

test "queue enable and disable" {
    const Impl = struct {
        const FnType = @TypeOf(&targetFn);
        var hook: Hook(FnType) = undefined;

        fn targetFn(a: i32, b: i32) callconv(CDECL) i32 {
            return a + b;
        }

        fn detourFn(a: i32, b: i32) callconv(CDECL) i32 {
            return hook.call(.{ a, b }) * 10;
        }
    };

    try initialize();
    defer uninitialize() catch {};

    const target = &Impl.targetFn;

    Impl.hook = try create(Impl.FnType, target, &Impl.detourFn);

    try Impl.hook.queueEnable();
    try std.testing.expectEqual(5, target(2, 3));

    try applyQueued();
    try Impl.hook.queueDisable();
    try std.testing.expectEqual(50, target(2, 3));

    try applyQueued();
    try std.testing.expectEqual(5, target(2, 3));
}

test "hook removal" {
    const Impl = struct {
        const FnType = @TypeOf(&targetFn);
        var hook: Hook(FnType) = undefined;

        fn targetFn(a: i32, b: i32) callconv(CDECL) i32 {
            return a + b;
        }

        fn detourFn(a: i32, b: i32) callconv(CDECL) i32 {
            return hook.call(.{ a, b }) * 10;
        }
    };

    try initialize();
    defer uninitialize() catch {};

    const target = &Impl.targetFn;
    Impl.hook = try create(Impl.FnType, target, &Impl.detourFn);
    try Impl.hook.enable();
    try std.testing.expectEqual(50, target(2, 3));

    try Impl.hook.remove();
    try std.testing.expectEqual(5, target(2, 3));

    Impl.hook = try create(Impl.FnType, target, &Impl.detourFn);
    try Impl.hook.enable();
    defer Impl.hook.remove() catch {};

    try std.testing.expectEqual(50, target(2, 3));
}

test "createApi hook Windows API function" {
    const Impl = struct {
        // GetCurrentProcessId: DWORD WINAPI GetCurrentProcessId(void)
        const FnType = *const fn () callconv(WINAPI) c.DWORD;
        var hook: Hook(FnType) = undefined;
        const fake_pid: c.DWORD = 12345;

        fn detourFn() callconv(WINAPI) c.DWORD {
            return fake_pid;
        }
    };

    try initialize();
    defer uninitialize() catch {};

    const kernel32 = std.unicode.utf8ToUtf16LeStringLiteral("kernel32.dll");
    Impl.hook = try createApi(Impl.FnType, kernel32, "GetCurrentProcessId", &Impl.detourFn);
    defer Impl.hook.remove() catch {};

    const real_pid = Impl.hook.original();

    try Impl.hook.enable();

    const getpid: Impl.FnType = @ptrCast(Impl.hook.target);
    try std.testing.expectEqual(Impl.fake_pid, getpid());

    try Impl.hook.disable();

    try std.testing.expectEqual(real_pid, getpid());
}
