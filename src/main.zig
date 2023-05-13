const std = @import("std");
const Parser = @import("parser.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    //const stdout = std.io.getStdOut().writer();

    std.log.info("All your codebase are belong to us.", .{});

    var parser = try Parser.Parser.init(allocator, "test.scm");
    defer parser.deinit();

    std.log.info("Created parser", .{});

    while (parser.parse()) |expr| {
        std.debug.print("{s}\n", .{expr});
        allocator.destroy(expr);
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
