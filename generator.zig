const std = @import("std");

pub fn Union4State(comptime Out: type) type {
    return union(enum) {
        /// Newly initialized or completed.
        inactive: void,

        /// Currently running. This is not a reliable check and exists to help prevent accidental concurrent writes.
        running: void,

        /// Async function yielded a value that has not been consumed yet.
        /// This exists because "priming the generator" dumps in a value without a next().
        yielded: YieldResult,

        /// Previously yielded result was consumed. next() will resume the suspended frame.
        consumed: YieldResult,

        const YieldResult = struct {
            frame: anyframe,
            out: Out,
        };

        pub fn init() @This() {
            return .{ .inactive = {} };
        }

        pub fn yield(self: *@This(), out: Out) void {
            std.debug.assert(self.* == .inactive or self.* == .running);

            suspend {
                self.* = .{
                    .yielded = .{
                        .frame = @frame(),
                        .out = out,
                    },
                };
            }
        }

        fn consume(self: *@This(), result: YieldResult) Out {
            self.* = .{ .consumed = result };
            return result.out;
        }

        pub fn next(self: *@This()) ?Out {
            switch (self.*) {
                .running => unreachable, // Generator is already running. Probably a concurrency bug.
                .inactive => return null,
                .yielded => |result| return self.consume(result),
                .consumed => |orig| {
                    // Copy elision footgun
                    const copy = orig;
                    self.* = .{ .running = {} };
                    resume copy.frame;
                    switch (self.*) {
                        .inactive, .consumed => unreachable, // Bad state. Probably a concurrency bug.
                        .yielded => |result| return self.consume(result),
                        .running => {
                            self.* = .{ .inactive = {} };
                            return null;
                        },
                    }
                },
            }
        }
    };
}

pub fn Union3State(comptime Out: type) type {
    return union(enum) {
        /// Newly initialized or completed.
        inactive: void,

        /// Async function yielded a value that has not been consumed yet.
        /// This exists because "priming the generator" dumps in a value without a next().
        yielded: YieldResult,

        /// Previously yielded result was consumed. next() will resume the suspended frame.
        consumed: YieldResult,

        const YieldResult = struct {
            frame: anyframe,
            out: Out,
        };

        pub fn init() @This() {
            return .{ .inactive = {} };
        }

        pub fn yield(self: *@This(), out: Out) void {
            std.debug.assert(self.* == .inactive or self.* == .running);

            suspend {
                self.* = .{
                    .yielded = .{
                        .frame = @frame(),
                        .out = out,
                    },
                };
            }
        }

        fn consume(self: *@This(), result: YieldResult) Out {
            self.* = .{ .consumed = result };
            return result.out;
        }

        pub fn next(self: *@This()) ?Out {
            switch (self.*) {
                .inactive => return null,
                .yielded => |result| return self.consume(result),
                .consumed => |orig| {
                    resume orig.frame;
                    switch (self.*) {
                        .inactive => unreachable, // Bad state. Probably a concurrency bug.
                        .yielded => |result| return self.consume(result),
                        .consumed => {
                            self.* = .{ .inactive = {} };
                            return null;
                        },
                    }
                },
            }
        }
    };
}

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

pub fn StructOptional(comptime Out: type) type {
    return struct {
        active: ?struct {
            frame: anyframe,
            out: Out,

            /// This exists because "priming the generator" dumps in a value without a next().
            consumed: bool,
        },

        pub fn init() @This() {
            return .{ .active = null };
        }

        pub fn yield(self: *@This(), out: Out) void {
            std.debug.assert(self.active == null or self.active.?.consumed);

            suspend {
                self.active = .{
                    .frame = @frame(),
                    .out = out,
                    .consumed = false,
                };
            }
        }

        pub fn next(self: *@This()) ?Out {
            if (self.active) |*active| {
                if (!active.consumed) {
                    active.consumed = true;
                    return active.out;
                }

                resume active.frame;
                std.debug.assert(self.active != null);
                if (!active.consumed) {
                    active.consumed = true;
                    return active.out;
                } else {
                    self.active = null;
                    return null;
                }
            } else {
                return null;
            }
        }
    };
}
