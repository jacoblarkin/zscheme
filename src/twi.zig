const std = @import("std");
const parser = @import("parser.zig");

pub const LispValTag = enum {
    Nil,
    Bool,
    Char,
    Integer,
    Rational,
    Real,
    Complex,
    String,
    Symbol,
    Cons,
    Vector,
    ByteVector,
    Func,
};

pub const LispVal = union(LispValTag) {
    Nil: void,
    Bool: bool,
    Char: u8,
    Integer: i64,
    Rational: [2]i64,
    Real: f64,
    Complex: [2]f64,
    String: []const u8,
    Symbol: []const u8,
    Cons: ConsStruct,
    Vector: std.ArrayList(LispVal),
    ByteVector: std.ArrayList(u8),
    Func: LispFunc,

    fn isnil(val: LispVal) bool {
        return switch (val) {
            LispValTag.Nil => true,
            else => false,
        };
    }

    fn isbool(val: LispVal) bool {
        return switch (val) {
            LispValTag.Bool => true,
            else => false,
        };
    }

    fn ischar(val: LispVal) bool {
        return switch (val) {
            LispValTag.Char => true,
            else => false,
        };
    }

    fn isinteger(val: LispVal) bool {
        return switch (val) {
            LispValTag.Integer => true,
            else => false,
        };
    }

    fn isrational(val: LispVal) bool {
        return switch (val) {
            LispValTag.Rational => true,
            else => false,
        };
    }

    fn isreal(val: LispVal) bool {
        return switch (val) {
            LispValTag.Real => true,
            else => false,
        };
    }

    fn iscomplex(val: LispVal) bool {
        return switch (val) {
            LispValTag.Complex => true,
            else => false,
        };
    }

    fn isnumber(val: LispVal) bool {
        return switch (val) {
            LispValTag.Integer, LispValTag.Rational, LispValTag.Real, LispValTag.Complex => true,
            else => false,
        };
    }

    fn issymbol(val: LispVal) bool {
        return switch (val) {
            LispValTag.Symbol => true,
            else => false,
        };
    }

    fn isstring(val: LispVal) bool {
        return switch (val) {
            LispValTag.String => true,
            else => false,
        };
    }

    fn iscons(val: LispVal) bool {
        return switch (val) {
            LispValTag.Cons => true,
            else => false,
        };
    }

    fn isvector(val: LispVal) bool {
        return switch (val) {
            LispValTag.Vector => true,
            else => false,
        };
    }

    fn isbytevector(val: LispVal) bool {
        return switch (val) {
            LispValTag.ByteVector => true,
            else => false,
        };
    }

    fn isfunction(val: LispVal) bool {
        return switch (val) {
            LispValTag.Func => true,
            else => false,
        };
    }

    fn booleq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Bool => |b1| switch (other) {
                LispValTag.Bool => |b2| b1 == b2,
                else => false,
            },
            else => false,
        };
    }

    fn chareq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Char => |c1| switch (other) {
                LispValTag.Char => |c2| c1 == c2,
                else => false,
            },
            else => false,
        };
    }

    fn integereq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Integer => |in1| switch (other) {
                LispValTag.Integer => |in2| in1 == in2,
                else => false,
            },
            else => false,
        };
    }

    fn rationaleq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Rational => |in1| switch (other) {
                LispValTag.Rational => |in2| in1[0] == in2[0] and in1[1] == in2[1],
                else => false,
            },
            else => false,
        };
    }

    fn realeq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Real => |in1| switch (other) {
                LispValTag.Real => |in2| in1 == in2,
                else => false,
            },
            else => false,
        };
    }

    fn complexeq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Complex => |in1| switch (other) {
                LispValTag.Complex => |in2| in1[0] == in2[0] and in1[1] == in2[1],
                else => false,
            },
            else => false,
        };
    }

    fn inexacteq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Complex => |in1| switch (other) {
                LispValTag.Real => |in2| in1[0] == in2 and in1[1] == 0,
                LispValTag.Complex => |in2| in1[0] == in2[0] and in1[1] == in2[1],
                else => false,
            },
            LispValTag.Real => |in1| switch (other) {
                LispValTag.Real => |in2| in1 == in2,
                LispValTag.Complex => |in2| in1 == in2[0] and in2[1] == 0,
                else => false,
            },
            else => false,
        };
    }

    fn exacteq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Rational => |in1| switch (other) {
                LispValTag.Integer => |in2| in1[0] == in2 and in1[1] == 1,
                LispValTag.Rational => |in2| in1[0] == in2[0] and in1[1] == in2[1],
                else => false,
            },
            LispValTag.Integer => |in1| switch (other) {
                LispValTag.Integer => |in2| in1 == in2,
                LispValTag.Rational => |in2| in1 == in2[0] and in2[1] == 1,
                else => false,
            },
            else => false,
        };
    }

    fn stringeq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.String => |s1| switch (other) {
                LispValTag.String => |s2| std.mem.eql(u8, s1, s2),
                else => false,
            },
            else => false,
        };
    }

    fn symboleq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Symbol => |s1| switch (other) {
                LispValTag.Symbol => |s2| std.mem.eql(u8, s1, s2),
                else => false,
            },
            else => false,
        };
    }

    fn conseq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Cons => |cn1| switch (other) {
                LispValTag.Cons => |cn2| cn1.Car == cn2.Car and cn1.Cdr == cn2.Cdr,
                else => false,
            },
            else => false,
        };
    }

    fn consequal(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Cons => |cn1| switch (other) {
                LispValTag.Cons => |cn2| cn1.Car.equal(cn2.Car.*) and
                    cn1.Cdr.equal(cn2.Cdr.*),
                else => false,
            },
            else => false,
        };
    }

    fn vectoreq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Vector => |v1| switch (other) {
                LispValTag.Vector => |v2| &v1.items == &v2.items,
                else => false,
            },
            else => false,
        };
    }

    fn vectorequal(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Vector => |v1| switch (other) {
                LispValTag.Vector => |v2| {
                    if (v1.items.len != v2.items.len) return false;
                    for (v1.items, v2.items) |e1, e2| {
                        if (!e1.equal(e2)) return false;
                    }
                    return true;
                },
                else => false,
            },
            else => false,
        };
    }

    fn bytevectoreq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.ByteVector => |v1| switch (other) {
                LispValTag.ByteVector => |v2| &v1.items == &v2.items,
                else => false,
            },
            else => false,
        };
    }

    fn bytevectorequal(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.ByteVector => |v1| switch (other) {
                LispValTag.ByteVector => |v2| std.mem.eql(u8, v1.items, v2.items),
                else => false,
            },
            else => false,
        };
    }

    fn funceq(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Func => |f1| switch (other) {
                LispValTag.Func => |f2| f1.func == f2.func,
                else => false,
            },
            else => false,
        };
    }

    fn eqv(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Nil => true,
            LispValTag.Bool => booleq(val, other),
            LispValTag.Char => chareq(val, other),
            LispValTag.Integer, LispValTag.Rational => exacteq(val, other),
            LispValTag.Real, LispValTag.Complex => inexacteq(val, other),
            LispValTag.String => stringeq(val, other),
            LispValTag.Symbol => symboleq(val, other),
            LispValTag.Cons => conseq(val, other),
            LispValTag.Vector => vectoreq(val, other),
            LispValTag.ByteVector => bytevectoreq(val, other),
            LispValTag.Func => funceq(val, other),
        };
    }

    fn equal(val: LispVal, other: LispVal) bool {
        return switch (val) {
            LispValTag.Nil => true,
            LispValTag.Bool => booleq(val, other),
            LispValTag.Char => chareq(val, other),
            LispValTag.Integer, LispValTag.Rational => exacteq(val, other),
            LispValTag.Real, LispValTag.Complex => inexacteq(val, other),
            LispValTag.String => stringeq(val, other),
            LispValTag.Symbol => symboleq(val, other),
            LispValTag.Cons => consequal(val, other),
            LispValTag.Vector => vectorequal(val, other),
            LispValTag.ByteVector => bytevectorequal(val, other),
            LispValTag.Func => funceq(val, other),
        };
    }

    fn plusInteger(val: LispVal, other: i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Integer = v + other },
            LispValTag.Rational => |v| return LispVal{ .Rational = [2]i64{ v[0] + v[1] * other, v[1] } },
            LispValTag.Real => |v| return LispVal{ .Real = v + @as(f64, @floatFromInt(other)) },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] + @as(f64, @floatFromInt(other)), v[1] } },
            else => {
                std.debug.print("Runtime Error: can only add numbers.\n", .{});
                return val;
            },
        }
    }

    fn plusRational(val: LispVal, other: [2]i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Rational = [2]i64{ v * other[1] + other[0], other[1] } },
            LispValTag.Rational => |v| return LispVal{ .Rational = [2]i64{ v[0] * other[1] + v[1] * other[0], v[1] * other[1] } },
            LispValTag.Real => |v| return LispVal{ .Real = v + @as(f64, @floatFromInt(other[0])) / @as(f64, @floatFromInt(other[1])) },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] + @as(f64, @floatFromInt(other[0])) / @as(f64, @floatFromInt(other[1])), v[1] } },
            else => {
                std.debug.print("Runtime Error: can only add numbers.\n", .{});
                return val;
            },
        }
    }

    fn plusReal(val: LispVal, other: f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Real = @as(f64, @floatFromInt(v)) + other },
            LispValTag.Rational => |v| return LispVal{ .Real = other + @as(f64, @floatFromInt(v[0])) / @as(f64, @floatFromInt(v[1])) },
            LispValTag.Real => |v| return LispVal{ .Real = v + other },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] + other, v[1] } },
            else => {
                std.debug.print("Runtime Error: can only add numbers.\n", .{});
                return val;
            },
        }
    }

    fn plusComplex(val: LispVal, other: [2]f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Complex = [2]f64{ @as(f64, @floatFromInt(v)) + other[0], other[1] } },
            LispValTag.Rational => |v| return LispVal{ .Complex = [2]f64{ other[0] + @as(f64, @floatFromInt(v[0])) / @as(f64, @floatFromInt(v[1])), other[1] } },
            LispValTag.Real => |v| return LispVal{ .Complex = [2]f64{ v + other[0], other[1] } },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] + other[0], v[1] + other[1] } },
            else => {
                std.debug.print("Runtime Error: can only add numbers.\n", .{});
                return val;
            },
        }
    }

    fn minusInteger(val: LispVal, other: i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Integer = v - other },
            LispValTag.Rational => |v| return LispVal{ .Rational = [2]i64{ v[0] - v[1] * other, v[1] } },
            LispValTag.Real => |v| return LispVal{ .Real = v - @as(f64, @floatFromInt(other)) },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] - @as(f64, @floatFromInt(other)), v[1] } },
            else => {
                std.debug.print("Runtime Error: can only add numbers.\n", .{});
                return val;
            },
        }
    }

    fn minusRational(val: LispVal, other: [2]i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Rational = [2]i64{ v * other[1] - other[0], other[1] } },
            LispValTag.Rational => |v| return LispVal{ .Rational = [2]i64{ v[0] * other[1] - v[1] * other[0], v[1] * other[1] } },
            LispValTag.Real => |v| return LispVal{ .Real = v - @as(f64, @floatFromInt(other[0])) / @as(f64, @floatFromInt(other[1])) },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] - @as(f64, @floatFromInt(other[0])) / @as(f64, @floatFromInt(other[1])), v[1] } },
            else => {
                std.debug.print("Runtime Error: can only add numbers.\n", .{});
                return val;
            },
        }
    }

    fn minusReal(val: LispVal, other: f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Real = @as(f64, @floatFromInt(v)) - other },
            LispValTag.Rational => |v| return LispVal{ .Real = @as(f64, @floatFromInt(v[0])) / @as(f64, @floatFromInt(v[1])) - other },
            LispValTag.Real => |v| return LispVal{ .Real = v - other },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] - other, v[1] } },
            else => {
                std.debug.print("Runtime Error: can only add numbers.\n", .{});
                return val;
            },
        }
    }

    fn minusComplex(val: LispVal, other: [2]f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Complex = [2]f64{ @as(f64, @floatFromInt(v)) - other[0], -other[1] } },
            LispValTag.Rational => |v| return LispVal{ .Complex = [2]f64{ @as(f64, @floatFromInt(v[0])) / @as(f64, @floatFromInt(v[1])) - other[0], -other[1] } },
            LispValTag.Real => |v| return LispVal{ .Complex = [2]f64{ v - other[0], -other[1] } },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] - other[0], v[1] - other[1] } },
            else => {
                std.debug.print("Runtime Error: can only add numbers.\n", .{});
                return val;
            },
        }
    }

    fn timesInteger(val: LispVal, other: i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Integer = v * other },
            LispValTag.Rational => |v| return LispVal{ .Rational = [2]i64{ v[0] * other, v[1] } },
            LispValTag.Real => |v| return LispVal{ .Real = v * @as(f64, @floatFromInt(other)) },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] * @as(f64, @floatFromInt(other)), v[1] * @as(f64, @floatFromInt(other)) } },
            else => {
                std.debug.print("Runtime Error: can only multiply numbers.\n", .{});
                return val;
            },
        }
    }

    fn timesRational(val: LispVal, other: [2]i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Rational = [2]i64{ v * other[0], other[1] } },
            LispValTag.Rational => |v| return LispVal{ .Rational = [2]i64{ v[0] * other[0], v[1] * other[1] } },
            LispValTag.Real => |v| return LispVal{ .Real = v * @as(f64, @floatFromInt(other[0])) / @as(f64, @floatFromInt(other[1])) },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] * @as(f64, @floatFromInt(other[0])) / @as(f64, @floatFromInt(other[1])), v[1] * @as(f64, @floatFromInt(other[0])) / @as(f64, @floatFromInt(other[1])) } },
            else => {
                std.debug.print("Runtime Error: can only multiply numbers.\n", .{});
                return val;
            },
        }
    }

    fn timesReal(val: LispVal, other: f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Real = @as(f64, @floatFromInt(v)) * other },
            LispValTag.Rational => |v| return LispVal{ .Real = other * @as(f64, @floatFromInt(v[0])) / @as(f64, @floatFromInt(v[1])) },
            LispValTag.Real => |v| return LispVal{ .Real = v * other },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] * other, v[1] * other } },
            else => {
                std.debug.print("Runtime Error: can only multiply numbers.\n", .{});
                return val;
            },
        }
    }

    fn timesComplex(val: LispVal, other: [2]f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Complex = [2]f64{ @as(f64, @floatFromInt(v)) * other[0], @as(f64, @floatFromInt(v)) * other[1] } },
            LispValTag.Rational => |v| return LispVal{ .Complex = [2]f64{ other[0] * @as(f64, @floatFromInt(v[0])) / @as(f64, @floatFromInt(v[1])), other[1] * @as(f64, @floatFromInt(v[0])) / @as(f64, @floatFromInt(v[1])) } },
            LispValTag.Real => |v| return LispVal{ .Complex = [2]f64{ v * other[0], v * other[1] } },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] * other[0] - v[1] * other[1], v[0] * other[1] + v[1] * other[0] } },
            else => {
                std.debug.print("Runtime Error: can only multiply numbers.\n", .{});
                return val;
            },
        }
    }

    fn divideInteger(val: LispVal, other: i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Rational = [2]i64{ v, other } },
            LispValTag.Rational => |v| return LispVal{ .Rational = [2]i64{ v[0], other * v[1] } },
            LispValTag.Real => |v| return LispVal{ .Real = v / @as(f64, @floatFromInt(other)) },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] / @as(f64, @floatFromInt(other)), v[1] / @as(f64, @floatFromInt(other)) } },
            else => {
                std.debug.print("Runtime Error: can only multiply numbers.\n", .{});
                return val;
            },
        }
    }

    fn divideRational(val: LispVal, other: [2]i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Rational = [2]i64{ v * other[1], other[0] } },
            LispValTag.Rational => |v| return LispVal{ .Rational = [2]i64{ v[0] * other[1], v[1] * other[0] } },
            LispValTag.Real => |v| return LispVal{ .Real = v * @as(f64, @floatFromInt(other[1])) / @as(f64, @floatFromInt(other[0])) },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] * @as(f64, @floatFromInt(other[1])) / @as(f64, @floatFromInt(other[0])), v[1] * @as(f64, @floatFromInt(other[1])) / @as(f64, @floatFromInt(other[0])) } },
            else => {
                std.debug.print("Runtime Error: can only multiply numbers.\n", .{});
                return val;
            },
        }
    }

    fn divideReal(val: LispVal, other: f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Real = @as(f64, @floatFromInt(v)) / other },
            LispValTag.Rational => |v| return LispVal{ .Real = @as(f64, @floatFromInt(v[0])) / (other * @as(f64, @floatFromInt(v[1]))) },
            LispValTag.Real => |v| return LispVal{ .Real = v / other },
            LispValTag.Complex => |v| return LispVal{ .Complex = [2]f64{ v[0] / other, v[1] / other } },
            else => {
                std.debug.print("Runtime Error: can only multiply numbers.\n", .{});
                return val;
            },
        }
    }

    fn divideComplex(val: LispVal, other: [2]f64) LispVal {
        const otherMag2 = other[0] * other[0] + other[1] * other[1];
        const otherConj = [2]f64{ other[0], -other[1] };
        return val.timesComplex(otherConj).divideReal(otherMag2);
    }

    fn lessThanInteger(val: LispVal, other: i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = v < other },
            LispValTag.Rational => |v| return LispVal{ .Bool = v[0] < other * v[1] },
            LispValTag.Real => |v| return LispVal{ .Bool = v < @as(f64, @floatFromInt(other)) },
            else => {
                std.debug.print("Runtime Error: Can only compare Integers, Rationals, or Reals.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn lessThanRational(val: LispVal, other: [2]i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = other[1] * v < other[0] },
            LispValTag.Rational => |v| return LispVal{ .Bool = other[1] * v[0] < other[0] * v[1] },
            LispValTag.Real => |v| return LispVal{ .Bool = v * @as(f64, @floatFromInt(other[1])) < @as(f64, @floatFromInt(other[0])) },
            else => {
                std.debug.print("Runtime Error: Can only compare Integers, Rationals, or Reals.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn lessThanReal(val: LispVal, other: f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = @as(f64, @floatFromInt(v)) < other },
            LispValTag.Rational => |v| return LispVal{ .Bool = @as(f64, @floatFromInt(v[0])) < other * @as(f64, @floatFromInt(v[1])) },
            LispValTag.Real => |v| return LispVal{ .Bool = v < other },
            else => {
                std.debug.print("Runtime Error: Can only compare Integers, Rationals, or Reals.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn greaterThanInteger(val: LispVal, other: i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = v > other },
            LispValTag.Rational => |v| return LispVal{ .Bool = v[0] > other * v[1] },
            LispValTag.Real => |v| return LispVal{ .Bool = v > @as(f64, @floatFromInt(other)) },
            else => {
                std.debug.print("Runtime Error: Can only compare Integers, Rationals, or Reals.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn greaterThanRational(val: LispVal, other: [2]i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = other[1] * v > other[0] },
            LispValTag.Rational => |v| return LispVal{ .Bool = other[1] * v[0] > other[0] * v[1] },
            LispValTag.Real => |v| return LispVal{ .Bool = v * @as(f64, @floatFromInt(other[1])) > @as(f64, @floatFromInt(other[0])) },
            else => {
                std.debug.print("Runtime Error: Can only compare Integers, Rationals, or Reals.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn greaterThanReal(val: LispVal, other: f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = @as(f64, @floatFromInt(v)) > other },
            LispValTag.Rational => |v| return LispVal{ .Bool = @as(f64, @floatFromInt(v[0])) > other * @as(f64, @floatFromInt(v[1])) },
            LispValTag.Real => |v| return LispVal{ .Bool = v > other },
            else => {
                std.debug.print("Runtime Error: Can only compare Integers, Rationals, or Reals.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn equalToInteger(val: LispVal, other: i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = v == other },
            LispValTag.Rational => |v| return LispVal{ .Bool = v[0] == other * v[1] },
            LispValTag.Real => |v| return LispVal{ .Bool = v == @as(f64, @floatFromInt(other)) },
            LispValTag.Complex => |v| return LispVal{ .Bool = v[1] == 0.0 and v[0] == @as(f64, @floatFromInt(other)) },
            else => {
                std.debug.print("Runtime Error: Can only compare numbers.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn equalToRational(val: LispVal, other: [2]i64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = other[1] * v == other[0] },
            LispValTag.Rational => |v| return LispVal{ .Bool = other[1] * v[0] == other[0] * v[1] },
            LispValTag.Real => |v| return LispVal{ .Bool = v * @as(f64, @floatFromInt(other[1])) == @as(f64, @floatFromInt(other[0])) },
            LispValTag.Complex => |v| return LispVal{ .Bool = v[1] == 0.0 and v[0] * @as(f64, @floatFromInt(other[1])) == @as(f64, @floatFromInt(other[0])) },
            else => {
                std.debug.print("Runtime Error: Can only compare numbers.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn equalToReal(val: LispVal, other: f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = @as(f64, @floatFromInt(v)) == other },
            LispValTag.Rational => |v| return LispVal{ .Bool = @as(f64, @floatFromInt(v[0])) == other * @as(f64, @floatFromInt(v[1])) },
            LispValTag.Real => |v| return LispVal{ .Bool = v == other },
            LispValTag.Complex => |v| return LispVal{ .Bool = v[1] == 0.0 and v[0] == other },
            else => {
                std.debug.print("Runtime Error: Can only compare numbers.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    fn equalToComplex(val: LispVal, other: [2]f64) LispVal {
        switch (val) {
            LispValTag.Integer => |v| return LispVal{ .Bool = @as(f64, @floatFromInt(v)) == other[0] and other[1] == 0.0 },
            LispValTag.Rational => |v| return LispVal{ .Bool = (@as(f64, @floatFromInt(v[0])) == other[0] * @as(f64, @floatFromInt(v[1])) and other[1] == 0.0) },
            LispValTag.Real => |v| return LispVal{ .Bool = (v == other[0] and other[1] == 0.0) },
            LispValTag.Complex => |v| return LispVal{ .Bool = (v[1] == other[1] and v[0] == other[0]) },
            else => {
                std.debug.print("Runtime Error: Can only compare numbers.\n", .{});
                return LispVal{ .Nil = {} };
            },
        }
    }

    pub fn print(val: LispVal) void {
        switch (val) {
            .Nil => std.debug.print("Nil", .{}),
            .Bool => |b| std.debug.print("{s}", .{if (b) "#t" else "#f"}),
            .Char => |c| std.debug.print("{c}", .{c}),
            .Integer => |i| std.debug.print("{d}", .{i}),
            .Rational => |r| std.debug.print("{d}/{d}", .{ r[0], r[1] }),
            .Real => |r| std.debug.print("{d}", .{r}),
            .Complex => |c| std.debug.print("{d} + {d}i", .{ c[0], c[1] }),
            .String => |s| std.debug.print("\"{s}\"", .{s}),
            .Symbol => |s| std.debug.print("{s}", .{s}),
            .Cons => |c| {
                std.debug.print("(", .{});
                var cons = c;
                while (true) {
                    cons.Car.print();
                    std.debug.print(" ", .{});
                    switch (cons.Cdr.*) {
                        LispValTag.Nil => break,
                        LispValTag.Cons => |nc| cons = nc,
                        else => cons.Cdr.print(),
                    }
                }
                std.debug.print(")", .{});
            },
            .Vector => |v| {
                std.debug.print("#(", .{});
                for (v.items, 0..) |e, i| {
                    if (i != 0) std.debug.print(" ", .{});
                    e.print();
                }
                std.debug.print(")", .{});
            },
            .ByteVector => |v| {
                std.debug.print("#u8(", .{});
                for (v.items, 0..) |e, i| {
                    if (i != 0) std.debug.print(" ", .{});
                    std.debug.print("{d}", .{e});
                }
                std.debug.print(")", .{});
            },
            .Func => |f| std.debug.print("<function: {s}>", .{f.name}),
        }
    }
};

pub const ConsStruct = struct {
    Car: *LispVal,
    Cdr: *LispVal,
};

pub const LispFunc = struct {
    name: []const u8,
    arity: ?usize,
    func: *const fn (ConsStruct) LispVal,
};

var NilVal = LispVal{ .Nil = {} };

fn plus(args: ConsStruct) LispVal {
    var argsC = args;
    var arg = argsC.Car;
    var sum = LispVal{ .Integer = 0 };
    while (arg.* != LispValTag.Nil) {
        switch (arg.*) {
            LispValTag.Integer => |v| sum = sum.plusInteger(v),
            LispValTag.Rational => |v| sum = sum.plusRational(v),
            LispValTag.Real => |v| sum = sum.plusReal(v),
            LispValTag.Complex => |v| sum = sum.plusComplex(v),
            else => break,
        }
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return sum;
}

fn minus(args: ConsStruct) LispVal {
    var diff = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr == LispValTag.Nil) {
        return diff.timesInteger(-1);
    } else if (cdr != LispValTag.Cons) {
        return diff; // Probably should be a runtime error
    }
    var argsC = args.Cdr.Cons;
    var arg = argsC.Car;
    while (arg.* != LispValTag.Nil) {
        switch (arg.*) {
            LispValTag.Integer => |v| diff = diff.minusInteger(v),
            LispValTag.Rational => |v| diff = diff.minusRational(v),
            LispValTag.Real => |v| diff = diff.minusReal(v),
            LispValTag.Complex => |v| diff = diff.minusComplex(v),
            else => break,
        }
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return diff;
}

fn times(args: ConsStruct) LispVal {
    var argsC = args;
    var arg = argsC.Car;
    var prod = LispVal{ .Integer = 1 };
    while (arg.* != LispValTag.Nil) {
        switch (arg.*) {
            LispValTag.Integer => |v| prod = prod.timesInteger(v),
            LispValTag.Rational => |v| prod = prod.timesRational(v),
            LispValTag.Real => |v| prod = prod.timesReal(v),
            LispValTag.Complex => |v| prod = prod.timesComplex(v),
            else => break,
        }
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return prod;
}

fn divide(args: ConsStruct) LispVal {
    var quot = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr == LispValTag.Nil) {
        var unit = LispVal{ .Integer = 1 };
        return switch (quot) {
            LispValTag.Integer => |v| unit.divideInteger(v),
            LispValTag.Rational => |v| unit.divideRational(v),
            LispValTag.Real => |v| unit.divideReal(v),
            LispValTag.Complex => |v| unit.divideComplex(v),
            else => quot,
        };
    } else if (cdr != LispValTag.Cons) {
        return quot; // Probably should be a runtime error
    }
    var argsC = args.Cdr.Cons;
    var arg = argsC.Car;
    while (arg.* != LispValTag.Nil) {
        switch (arg.*) {
            LispValTag.Integer => |v| quot = quot.divideInteger(v),
            LispValTag.Rational => |v| quot = quot.divideRational(v),
            LispValTag.Real => |v| quot = quot.divideReal(v),
            LispValTag.Complex => |v| quot = quot.divideComplex(v),
            else => break,
        }
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return quot;
}

fn lessThan(args: ConsStruct) LispVal {
    var first = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr != LispValTag.Cons) {
        std.debug.print("Runtime Error: Expected at lest two arguments.\n", .{});
        return LispVal{ .Nil = {} };
    }
    var argsC = args.Cdr.Cons;
    var arg = argsC.Car;
    while (arg.* != LispValTag.Nil) {
        const lt = switch (arg.*) {
            LispValTag.Integer => |v| first.lessThanInteger(v),
            LispValTag.Rational => |v| first.lessThanRational(v),
            LispValTag.Real => |v| first.lessThanReal(v),
            else => break,
        };
        if (lt != LispValTag.Bool or !lt.Bool) {
            return lt;
        }
        first = arg.*;
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return LispVal{ .Bool = true };
}

fn greaterThan(args: ConsStruct) LispVal {
    var first = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr != LispValTag.Cons) {
        std.debug.print("Runtime Error: Expected at lest two arguments.\n", .{});
        return LispVal{ .Nil = {} };
    }
    var argsC = args.Cdr.Cons;
    var arg = argsC.Car;
    while (arg.* != LispValTag.Nil) {
        const lt = switch (arg.*) {
            LispValTag.Integer => |v| first.greaterThanInteger(v),
            LispValTag.Rational => |v| first.greaterThanRational(v),
            LispValTag.Real => |v| first.greaterThanReal(v),
            else => break,
        };
        if (lt != LispValTag.Bool or !lt.Bool) {
            return lt;
        }
        first = arg.*;
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return LispVal{ .Bool = true };
}
fn equalTo(args: ConsStruct) LispVal {
    var first = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr != LispValTag.Cons) {
        std.debug.print("Runtime Error: Expected at lest two arguments.\n", .{});
        return LispVal{ .Nil = {} };
    }
    var argsC = args.Cdr.Cons;
    var arg = argsC.Car;
    while (arg.* != LispValTag.Nil) {
        const lt = switch (arg.*) {
            LispValTag.Integer => |v| first.equalToInteger(v),
            LispValTag.Rational => |v| first.equalToRational(v),
            LispValTag.Real => |v| first.equalToReal(v),
            LispValTag.Complex => |v| first.equalToComplex(v),
            else => break,
        };
        if (lt != LispValTag.Bool or !lt.Bool) {
            return lt;
        }
        first = arg.*;
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return LispVal{ .Bool = true };
}

fn ifScheme(args: ConsStruct) LispVal {
    const then = switch (args.Car.*) {
        LispValTag.Bool => |b| b,
        else => true,
    };
    if (then) {
        return args.Cdr.Cons.Car.*;
    }
    return args.Cdr.Cons.Cdr.Cons.Car.*;
}

fn orScheme(args: ConsStruct) LispVal {
    return switch (args.Car.*) {
        LispValTag.Nil => LispVal{ .Bool = false },
        LispValTag.Bool => |b| {
            if (b) return args.Car.*;
            return switch (args.Cdr.*) {
                LispValTag.Nil => args.Car.*,
                LispValTag.Cons => |c| orScheme(c),
                else => args.Cdr.*,
            };
        },
        else => args.Car.*,
    };
}

fn lessThanOrEqual(args: ConsStruct) LispVal {
    var first = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr != LispValTag.Cons) {
        std.debug.print("Runtime Error: Expected at lest two arguments.\n", .{});
        return LispVal{ .Nil = {} };
    }
    var argsC = args.Cdr.Cons;
    var arg = argsC.Car;
    while (arg.* != LispValTag.Nil) {
        const lt = switch (arg.*) {
            LispValTag.Integer => |v| first.lessThanInteger(v),
            LispValTag.Rational => |v| first.lessThanRational(v),
            LispValTag.Real => |v| first.lessThanReal(v),
            else => break,
        };
        if (lt != LispValTag.Bool) {
            return lt;
        }
        if (!lt.Bool) {
            const eq = switch (arg.*) {
                LispValTag.Integer => |v| first.equalToInteger(v),
                LispValTag.Rational => |v| first.equalToRational(v),
                LispValTag.Real => |v| first.equalToReal(v),
                LispValTag.Complex => |v| first.equalToComplex(v),
                else => break,
            };
            if (eq != LispValTag.Bool or !eq.Bool) {
                return eq;
            }
        }
        first = arg.*;
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return LispVal{ .Bool = true };
}

fn greaterThanOrEqual(args: ConsStruct) LispVal {
    var first = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr != LispValTag.Cons) {
        std.debug.print("Runtime Error: Expected at lest two arguments.\n", .{});
        return LispVal{ .Nil = {} };
    }
    var argsC = args.Cdr.Cons;
    var arg = argsC.Car;
    while (arg.* != LispValTag.Nil) {
        const lt = switch (arg.*) {
            LispValTag.Integer => |v| first.greaterThanInteger(v),
            LispValTag.Rational => |v| first.greaterThanRational(v),
            LispValTag.Real => |v| first.greaterThanReal(v),
            else => break,
        };
        if (lt != LispValTag.Bool) {
            return lt;
        }
        if (!lt.Bool) {
            const eq = switch (arg.*) {
                LispValTag.Integer => |v| first.equalToInteger(v),
                LispValTag.Rational => |v| first.equalToRational(v),
                LispValTag.Real => |v| first.equalToReal(v),
                LispValTag.Complex => |v| first.equalToComplex(v),
                else => break,
            };
            if (eq != LispValTag.Bool or !eq.Bool) {
                return eq;
            }
        }
        first = arg.*;
        switch (argsC.Cdr.*) {
            LispValTag.Cons => |c| argsC = c,
            else => break,
        }
        arg = argsC.Car;
    }
    return LispVal{ .Bool = true };
}

fn schemeEqv(args: ConsStruct) LispVal {
    var first = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr != LispValTag.Cons) {
        std.debug.print("Runtime Error: Expected two arguments.\n", .{});
        return LispVal{ .Nil = {} };
    }
    const argsC = args.Cdr.Cons;
    const arg = argsC.Car;
    return LispVal{ .Bool = first.eqv(arg.*) };
}

fn schemeEqual(args: ConsStruct) LispVal {
    var first = args.Car.*;
    const cdr = args.Cdr.*;
    if (cdr != LispValTag.Cons) {
        std.debug.print("Runtime Error: Expected two arguments.\n", .{});
        return LispVal{ .Nil = {} };
    }
    const argsC = args.Cdr.Cons;
    const arg = argsC.Car;
    return LispVal{ .Bool = first.equal(arg.*) };
}

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMap(LispVal),

    pub fn init(allocator: std.mem.Allocator) !Interpreter {
        var values = std.StringHashMap(LispVal).init(allocator);
        try values.put("+", LispVal{ .Func = LispFunc{ .name = "+", .arity = null, .func = plus } });
        try values.put("-", LispVal{ .Func = LispFunc{ .name = "-", .arity = null, .func = minus } });
        try values.put("*", LispVal{ .Func = LispFunc{ .name = "*", .arity = null, .func = times } });
        try values.put("/", LispVal{ .Func = LispFunc{ .name = "/", .arity = null, .func = divide } });
        try values.put("<", LispVal{ .Func = LispFunc{ .name = "<", .arity = null, .func = lessThan } });
        try values.put(">", LispVal{ .Func = LispFunc{ .name = ">", .arity = null, .func = greaterThan } });
        try values.put("<=", LispVal{ .Func = LispFunc{ .name = "<=", .arity = null, .func = lessThanOrEqual } });
        try values.put(">=", LispVal{ .Func = LispFunc{ .name = ">=", .arity = null, .func = greaterThanOrEqual } });
        try values.put("=", LispVal{ .Func = LispFunc{ .name = "=", .arity = null, .func = equalTo } });
        try values.put("eqv?", LispVal{ .Func = LispFunc{ .name = "eqv?", .arity = 2, .func = schemeEqv } });
        try values.put("eq?", LispVal{ .Func = LispFunc{ .name = "eq?", .arity = 2, .func = schemeEqv } });
        try values.put("equal?", LispVal{ .Func = LispFunc{ .name = "equal?", .arity = 2, .func = schemeEqual } });
        try values.put("if", LispVal{ .Func = LispFunc{ .name = "if", .arity = 3, .func = ifScheme } });
        try values.put("or", LispVal{ .Func = LispFunc{ .name = "or", .arity = null, .func = orScheme } });
        return Interpreter{
            .allocator = allocator,
            .values = values,
        };
    }

    pub fn deinit(interpreter: *Interpreter) void {
        interpreter.values.deinit();
    }

    fn lookup(interpreter: *Interpreter, name: []const u8) LispVal {
        return interpreter.values.get(name) orelse {
            std.debug.print("Runtime Error: Could not find name {s}", .{name});
            return LispVal{ .Nil = {} };
        };
    }

    pub fn interpret(interpreter: *Interpreter, expr: *const parser.Expression) LispVal {
        return switch (expr.*) {
            parser.ExpressionTag.BoolLiteral, parser.ExpressionTag.CharLiteral, parser.ExpressionTag.IntegerLiteral, parser.ExpressionTag.RationalLiteral, parser.ExpressionTag.RealLiteral, parser.ExpressionTag.ComplexLiteral, parser.ExpressionTag.StringLiteral, parser.ExpressionTag.ByteVector => interpretLiteral(interpreter, expr),
            parser.ExpressionTag.Identifier => |ident| interpreter.lookup(ident),
            parser.ExpressionTag.Vector => |v| interpretVector(interpreter, v),
            parser.ExpressionTag.QuotedExpression => |qe| interpretQuoted(interpreter, qe, false),
            parser.ExpressionTag.QuasiQuotedExpression => |qqe| interpretQuoted(interpreter, qqe, true),
            parser.ExpressionTag.Cons => interpretCons(interpreter, expr),
            parser.ExpressionTag.Nil => LispVal{ .Nil = {} },
            parser.ExpressionTag.UnquotedElement => |e| interpreter.interpret(e),
        };
    }
};

fn interpretLiteral(interpreter: *Interpreter, expr: *const parser.Expression) LispVal {
    return switch (expr.*) {
        parser.ExpressionTag.Nil => LispVal{ .Nil = {} },
        parser.ExpressionTag.Identifier => |ident| LispVal{ .Symbol = ident },
        parser.ExpressionTag.BoolLiteral => |b| LispVal{ .Bool = b },
        parser.ExpressionTag.CharLiteral => |c| LispVal{ .Char = c },
        parser.ExpressionTag.IntegerLiteral => |i| LispVal{ .Integer = i },
        parser.ExpressionTag.RationalLiteral => |r| LispVal{ .Rational = r },
        parser.ExpressionTag.RealLiteral => |r| LispVal{ .Real = r },
        parser.ExpressionTag.ComplexLiteral => |c| LispVal{ .Complex = c },
        parser.ExpressionTag.StringLiteral => |s| LispVal{ .String = s },
        parser.ExpressionTag.ByteVector => |bv| LispVal{ .ByteVector = bv },
        parser.ExpressionTag.QuotedExpression => |qe| interpretQuoted(interpreter, qe, false),
        else => unreachable,
    };
}

fn interpretVector(interpreter: *Interpreter, v: std.ArrayList(*parser.Expression)) LispVal {
    var va = std.ArrayList(LispVal).init(interpreter.allocator);
    for (v.items) |vexpr| {
        va.append(interpreter.interpret(vexpr)) catch break;
    }
    return LispVal{ .Vector = va };
}

fn interpretQuoted(interpreter: *Interpreter, expr: *const parser.Expression, quasi: bool) LispVal {
    if (expr.* == parser.ExpressionTag.Cons and !quasi) {
        const car = interpreter.allocator.create(LispVal) catch {
            std.debug.print("Runtime Error: Memory allocation failed.", .{});
            return LispVal{ .Nil = {} };
        };
        const cdr = interpreter.allocator.create(LispVal) catch {
            std.debug.print("Runtime Error: Memory allocation failed.", .{});
            return LispVal{ .Nil = {} };
        };
        car.* = interpretQuoted(interpreter, expr.Cons.Car, quasi);
        cdr.* = interpretQuoted(interpreter, expr.Cons.Cdr, quasi);
        return LispVal{ .Cons = ConsStruct{ .Car = car, .Cdr = cdr } };
    }
    return interpretLiteral(interpreter, expr);
}

fn interpretCons(interpreter: *Interpreter, expr: *const parser.Expression) LispVal {
    const car = interpreter.interpret(expr.Cons.Car);
    return apply(interpreter, car, expr.Cons.Cdr);
}

fn apply(interpreter: *Interpreter, funcVal: LispVal, args: *const parser.Expression) LispVal {
    var func = funcVal.Func;
    var arguments = args;
    const empty: ConsStruct = ConsStruct{
        .Car = &NilVal,
        .Cdr = &NilVal,
    };
    var argVals: ConsStruct = empty;
    var current: *ConsStruct = &argVals;
    var argCount: usize = 0;
    var firstArg = true;
    while (true) {
        switch (arguments.*) {
            parser.ExpressionTag.Nil => break,
            parser.ExpressionTag.Cons => |arg| {
                if (!firstArg) {
                    current.Cdr.* = LispVal{ .Cons = empty };
                    current = &current.Cdr.Cons;
                }
                current.Car = interpreter.allocator.create(LispVal) catch {
                    return LispVal{ .Nil = {} };
                };
                current.Car.* = interpreter.interpret(arg.Car);
                current.Cdr = interpreter.allocator.create(LispVal) catch {
                    return LispVal{ .Nil = {} };
                };
                current.Cdr.* = LispVal{ .Nil = {} };
                arguments = arg.Cdr;
                argCount += 1;
                firstArg = false;
            },
            else => unreachable,
        }
    }
    if (func.arity) |arity| {
        if (arity != argCount) {
            std.debug.print("Runtime Error: Trying to evaluate function with arity {d} with {d} arguments.", .{ arity, argCount });
            return LispVal{ .Nil = {} };
        }
    }
    return func.func(argVals);
}
