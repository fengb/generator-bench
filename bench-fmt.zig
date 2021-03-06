const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const time = std.time;

const Decl = builtin.TypeInfo.Declaration;

pub fn benchmark(comptime B: type) !void {
    const args = if (@hasDecl(B, "args")) B.args else [_]void{{}};
    const iterations: u32 = if (@hasDecl(B, "iterations")) B.iterations else 100000;

    comptime var max_fn_name_len = 0;
    const functions = comptime blk: {
        var res: []const Decl = &[_]Decl{};
        for (meta.declarations(B)) |decl| {
            if (decl.data != Decl.Data.Fn)
                continue;

            if (max_fn_name_len < decl.name.len)
                max_fn_name_len = decl.name.len;
            res = res ++ [_]Decl{decl};
        }

        break :blk res;
    };
    if (functions.len == 0)
        @compileError("No benchmarks to run.");

    const max_name_spaces = comptime math.max(max_fn_name_len + digits(u64, 10, args.len) + 1, "Benchmark".len);

    var timer = try time.Timer.start();
    debug.warn("\n", .{});
    debug.warn("Benchmark", .{});
    nTimes(' ', (max_name_spaces - "Benchmark".len) + 1);
    nTimes(' ', digits(u64, 10, math.maxInt(u64)) - "Mean(ns)".len);
    debug.warn("Mean(ns)\n", .{});
    nTimes('-', max_name_spaces + digits(u64, 10, math.maxInt(u64)) + 1);
    debug.warn("\n", .{});

    inline for (functions) |def| {
        for (args) |arg, index| {
            var runtime_sum: u128 = 0;

            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                timer.reset();

                const res = switch (@TypeOf(arg)) {
                    void => @field(B, def.name)(),
                    else => @field(B, def.name)(arg),
                    //void => @call(.{ .modifier = .never_inline }, @field(B, def.name), .{}),
                    //else => @call(.{ .modifier = .never_inline }, @field(B, def.name), .{arg}),
                };

                const runtime = timer.read();
                runtime_sum += runtime;
                doNotOptimize(res);
            }

            const runtime_mean = @intCast(u64, runtime_sum / iterations);

            debug.warn("{}.{}", .{ def.name, index });
            nTimes(' ', (max_name_spaces - (def.name.len + digits(u64, 10, index) + 1)) + 1);
            nTimes(' ', digits(u64, 10, math.maxInt(u64)) - digits(u64, 10, runtime_mean));
            debug.warn("{}\n", .{runtime_mean});
        }
    }
}

/// Pretend to use the value so the optimizer cant optimize it out.
fn doNotOptimize(val: var) void {
    const T = @TypeOf(val);
    var store: T = undefined;
    @ptrCast(*volatile T, &store).* = val;
}

fn digits(comptime N: type, comptime base: comptime_int, n: N) usize {
    comptime var res = 1;
    comptime var check = base;

    inline while (check <= math.maxInt(N)) : ({
        check *= base;
        res += 1;
    }) {
        if (n < check)
            return res;
    }

    return res;
}

fn nTimes(c: u8, times: usize) void {
    var i: usize = 0;
    while (i < times) : (i += 1)
        debug.warn("{c}", .{c});
}

var buffer: [1000]u8 = undefined;
test "Generator benchmark" {
    try benchmark(struct {
        const Arg = struct {
            e: enum {
                Int,
                Float,
                Struct,
            },

            fn bench(a: Arg, bufPrint: var) !void {
                switch (comptime a.e) {
                    .Int => {
                        _ = try bufPrint(&buffer, "{d}", .{9223372036854775807});
                    },
                    .Float => {
                        _ = try bufPrint(&buffer, "f64: {d:.5}", .{@as(f64, 1.409706e-42)});
                    },
                    .Struct => {
                        const S = struct {
                            const SelfType = @This();
                            a: ?*SelfType = null,
                            b: ?*SelfType = null,
                            c: ?*SelfType = null,
                        };

                        var inst = S{};
                        inst.a = &inst;
                        inst.b = &inst;
                        inst.c = &inst;
                        _ = try bufPrint(&buffer, "{}", .{inst});
                    },
                }
            }
        };

        pub const args = [_]Arg{ .{ .e = .Int }, .{ .e = .Float }, .{ .e = .Struct } };

        pub const iterations = 100000;

        pub fn @"-----"(a: Arg) !void {
            try a.bench(std.fmtgen.bufPrint);
        }

        pub fn fmt(a: Arg) !void {
            try a.bench(std.fmt.bufPrint);
        }

        pub fn fmtgen(a: Arg) !void {
            try a.bench(std.fmtgen.bufPrint);
        }
    });
}
