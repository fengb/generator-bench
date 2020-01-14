const std = @import("std");

pub fn Union2State(comptime Out: type) type {
    return union(enum) {
        /// Newly initialized or completed.
        inactive: void,

        /// Async function yielded a value.
        active: struct {
            frame: anyframe,
            out: Out,

            /// This exists because "priming the generator" dumps in a value without a next().
            consumed: bool,
        },

        pub fn init() @This() {
            return .{ .inactive = {} };
        }

        pub fn yield(self: *@This(), out: Out) void {
            std.debug.assert(self.* == .inactive or self.active.consumed);

            suspend {
                self.* = .{
                    .active = .{
                        .frame = @frame(),
                        .out = out,
                        .consumed = false,
                    },
                };
            }
        }

        pub fn next(self: *@This()) ?Out {
            switch (self.*) {
                .inactive => return null,
                .active => |*active| {
                    if (!active.consumed) {
                        active.consumed = true;
                        return active.out;
                    }

                    resume active.frame;
                    std.debug.assert(self.* == .active);
                    if (!active.consumed) {
                        active.consumed = true;
                        return active.out;
                    } else {
                        self.* = .inactive;
                        return null;
                    }
                },
            }
        }
    };
}

pub fn Intrusive(comptime Out: type) type {
    return union(enum) {
        /// Newly initialized or completed.
        inactive: void,

        /// Async function yielded a value.
        active: struct {
            frame: anyframe,
            out: Out,

            /// This exists because "priming the generator" dumps in a value without a next().
            consumed: bool,
        },

        pub fn init() @This() {
            return .{ .inactive = {} };
        }

        pub fn yield(self: *@This(), frame: anyframe, out: Out) void {
            std.debug.assert(self.* == .inactive or self.active.consumed);

            self.* = .{
                .active = .{
                    .frame = frame,
                    .out = out,
                    .consumed = false,
                },
            };
        }

        pub fn next(self: *@This()) ?Out {
            switch (self.*) {
                .inactive => return null,
                .active => |*active| {
                    if (!active.consumed) {
                        active.consumed = true;
                        return active.out;
                    }

                    resume active.frame;
                    std.debug.assert(self.* == .active);
                    if (!active.consumed) {
                        active.consumed = true;
                        return active.out;
                    } else {
                        self.* = .inactive;
                        return null;
                    }
                },
            }
        }
    };
}

const bench = @import("bench.zig");
test "Intrusive benchmark" {
    try bench.benchmark(struct {
        const Arg = struct {
            letters: []const u8,

            fn bench(a: Arg, Generator: var, comptime intru: bool) void {
                const GenType = Generator([]const u8);
                const Wrapper = struct {
                    fn doit(gen: *GenType, inner_arg: Arg) void {
                        for (inner_arg.letters) |l| {
                            const foo = [_]u8{l};
                            gen.yield(&foo);
                        }
                    }
                    fn doitIntrusive(gen: *GenType, inner_arg: Arg) void {
                        for (inner_arg.letters) |l| {
                            const foo = [_]u8{l};
                            suspend gen.yield(@frame(), &foo);
                        }
                    }
                };
                if (intru) {
                    var gen = Generator([]const u8).init();
                    _ = async Wrapper.doitIntrusive(&gen, a);
                    while (gen.next()) |bytes| {
                        bench.doNotOptimize(bytes);
                    }
                } else {
                    var gen = Generator([]const u8).init();
                    _ = async Wrapper.doit(&gen, a);
                    while (gen.next()) |bytes| {
                        bench.doNotOptimize(bytes);
                    }
                }
            }
        };

        pub const args = [_]Arg{
            .{ .letters = "h" ** 100 },
            .{ .letters = "h" ** 1000 },
            .{ .letters = "h" ** 10000 },
            .{ .letters = "h" ** 100000 },
        };

        pub const iterations = 10000;

        pub fn @"-----"(a: Arg) void {
            a.bench(Union2State, false);
        }

        pub fn NoGenerator(a: Arg) void {
            for (a.letters) |l| {
                const bytes = [_]u8{l};
                bench.doNotOptimize(bytes);
            }
        }

        pub fn union2State(a: Arg) void {
            a.bench(Union2State, false);
        }

        pub fn intrusive(a: Arg) void {
            a.bench(Intrusive, true);
        }
    });
}
