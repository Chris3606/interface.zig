const interface = @import("interface.zig");
const Interface = interface.Interface;
const SelfType = interface.SelfType;

const std = @import("std");
const mem = std.mem;
const expectEqual = std.testing.expectEqual;
const assert = std.debug.assert;

test "Simple NonOwning interface" {
    const NonOwningTest = struct {
        fn run() !void {
            const Fooer = Interface(struct {
                foo: fn (*SelfType) usize,
            }, interface.Storage.NonOwning);

            const TestFooer = struct {
                const Self = @This();

                state: usize,

                pub fn foo(self: *Self) usize {
                    const tmp = self.state;
                    self.state += 1;
                    return tmp;
                }
            };

            var f = TestFooer{ .state = 42 };
            var fooer = try Fooer.init(&f);
            defer fooer.deinit();

            try expectEqual(@as(usize, 42), fooer.call("foo", .{}));
            try expectEqual(@as(usize, 43), fooer.call("foo", .{}));
        }
    };

    try NonOwningTest.run();
    comptime try NonOwningTest.run();
}

test "Comptime only interface" {
    // return error.SkipZigTest;
    const TestIFace = Interface(struct {
        foo: fn (*SelfType, u8) u8,
    }, interface.Storage.Comptime);

    const TestType = struct {
        const Self = @This();

        state: u8,

        pub fn foo(self: Self, a: u8) u8 {
            return self.state + a;
        }
    };

    comptime var iface = try TestIFace.init(TestType{ .state = 0 });
    try expectEqual(@as(u8, 42), iface.call("foo", .{42}));
}

test "Owning with Wrappers" {
    std.debug.print("\n", .{});

    // Interface class defining a function send, and an optional deinit function.
    const Messenger = struct {
        const Self = @This();

        const IFace = Interface(struct {
            deinit: ?fn(*SelfType) void,
            send: fn(*SelfType, msg: []const u8) void,
        }, interface.Storage.Owning);

        iface: IFace,

        // Wrap the interface's init, since the interface is owning it requires an allocator argument
        // to allocate space for the implementing struct.
        pub fn init(impl_ptr: anytype, allocator: *std.mem.Allocator) !Self {
            return Self{ .iface = try IFace.init(impl_ptr, allocator) };
        }
        
        // Wrap interface's deinit, and also ensure to call the proper function in the implementation if it has one
        pub fn deinit(self: *Self) void {
            // Call implementer's deinit if it has one
            _ = self.iface.call("deinit", .{});

            // Deinitialize interface, which includes deallocating the implementing struct/
            self.iface.deinit();
        }

        // Wrap the send function call
        pub fn send(self: *Self, buf: []const u8) void {
            return self.iface.call("send", .{buf});
        }
    };

    // Class implementing the messenger interface
    const MyMessenger = struct {
        const Self = @This();

        id : u32,

        pub fn init(id: u32) Self {
            return Self { .id = id };
        }

        pub fn deinit(self: *Self) void {
            std.debug.print("    {d}: Deinitializing implementation...\n", .{self.id});
        }

        pub fn send(self: *Self, msg: []const u8) void {
            std.debug.print("    {d}: {s}\n", .{self.id, msg});
        }
    };

    // Create implementation and wrap in interface
    const my_messenger = comptime MyMessenger.init(42);
    var messenger = try Messenger.init(my_messenger, std.testing.allocator);
    defer messenger.deinit();

    messenger.send("Hello!");
}

test "Owning interface with optional function and a non-method function" {
    const OwningOptionalFuncTest = struct {
        fn run() !void {
            const TestOwningIface = Interface(struct {
                someFn: ?fn (*const SelfType, usize, usize) usize,
                otherFn: fn (*SelfType, usize) anyerror!void,
                thirdFn: fn (usize) usize,
            }, interface.Storage.Owning);

            const TestStruct = struct {
                const Self = @This();

                state: usize,

                pub fn someFn(self: Self, a: usize, b: usize) usize {
                    return self.state * a + b;
                }

                // Note that our return type need only coerce to the virtual function's
                // return type.
                pub fn otherFn(self: *Self, new_state: usize) void {
                    self.state = new_state;
                }

                pub fn thirdFn(arg: usize) usize {
                    return arg + 1;
                }
            };

            var iface_instance = try TestOwningIface.init(comptime TestStruct{ .state = 0 }, std.testing.allocator);
            defer iface_instance.deinit();

            try iface_instance.call("otherFn", .{100});
            try expectEqual(@as(usize, 42), iface_instance.call("someFn", .{ 0, 42 }).?);
            try expectEqual(@as(usize, 101), iface_instance.call("thirdFn", .{100}));
        }
    };

    try OwningOptionalFuncTest.run();
}

test "Interface with virtual async function implemented by an async function" {
    const AsyncIFace = Interface(struct {
        const async_call_stack_size = 1024;

        foo: fn (*SelfType) callconv(.Async) void,
    }, interface.Storage.NonOwning);

    const Impl = struct {
        const Self = @This();

        state: usize,
        frame: anyframe = undefined,

        pub fn foo(self: *Self) void {
            suspend {
                self.frame = @frame();
            }
            self.state += 1;
            suspend {}
            self.state += 1;
        }
    };

    var i = Impl{ .state = 0 };
    var instance = try AsyncIFace.init(&i);
    _ = async instance.call("foo", .{});

    try expectEqual(@as(usize, 0), i.state);
    resume i.frame;
    try expectEqual(@as(usize, 1), i.state);
    resume i.frame;
    try expectEqual(@as(usize, 2), i.state);
}

test "Interface with virtual async function implemented by a blocking function" {
    const AsyncIFace = Interface(struct {
        readBytes: fn (*SelfType, []u8) callconv(.Async) anyerror!void,
    }, interface.Storage.Inline(8));

    const Impl = struct {
        const Self = @This();

        pub fn readBytes(self: Self, outBuf: []u8) void {
            _ = self;

            for (outBuf) |*c| {
                c.* = 3;
            }
        }
    };

    var instance = try AsyncIFace.init(Impl{});

    var buf: [256]u8 = undefined;
    try await async instance.call("readBytes", .{buf[0..]});

    try expectEqual([_]u8{3} ** 256, buf);
}
