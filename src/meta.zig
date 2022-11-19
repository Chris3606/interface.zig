const std = @import("std");

pub const FnPtr = if (@hasDecl(std.meta, "FnPtr")) std.meta.FnPtr else FnPtrHelper;

/// This function returns a function pointer for a given function signature.
/// It's a helper to make code compatible to both stage1 and stage2.
///
/// You should only use this when the std.meta.FnPtr type isn't available.
fn FnPtrHelper(comptime Fn: type) type {
    if (@hasDecl(std.meta, "FnPtr")) {
        return std.meta.FnPtr(Fn);
    } else {
        return if (@import("builtin").zig_backend != .stage1)
            *const Fn
        else
            Fn;
    }
}
