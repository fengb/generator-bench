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

const generator = @import("generator.zig");

test "Generator benchmark" {
    try benchmark(struct {
        const Arg = struct {
            letters: []const u8,

            fn bench(a: Arg, Generator: var) void {
                const GenType = Generator([]const u8);
                const Wrapper = struct {
                    fn doit(gen: *GenType, inner_arg: Arg) void {
                        for (inner_arg.letters) |l| {
                            const foo = [_]u8{l};
                            gen.yield(&foo);
                        }
                    }
                };
                var gen = Generator([]const u8).init();
                _ = async Wrapper.doit(&gen, a);
                while (gen.next()) |bytes| {
                    doNotOptimize(bytes);
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
            a.bench(generator.Union4State);
        }

        pub fn NoGenerator(a: Arg) void {
            for (a.letters) |l| {
                const bytes = [_]u8{l};
                doNotOptimize(bytes);
            }
        }

        pub fn Union4State(a: Arg) void {
            a.bench(generator.Union4State);
        }

        pub fn Union3State(a: Arg) void {
            a.bench(generator.Union4State);
        }

        pub fn Union2State(a: Arg) void {
            a.bench(generator.Union2State);
        }

        pub fn StructOptional(a: Arg) void {
            a.bench(generator.StructOptional);
        }
    });
}
