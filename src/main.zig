const std = @import("std");
const Parser = @import("parser.zig");
const Interpreter = @import("twi.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    std.log.info("All your codebase are belong to us.", .{});

    var parser = try Parser.Parser.init(allocator, "");
    defer parser.deinit();

    var interpreter = try Interpreter.Interpreter.init(allocator);
    defer interpreter.deinit();

    std.log.info("Created parser", .{});

    //while (parser.parse()) |expr| {
    //std.debug.print("{s}\n", .{interpreter.interpret(expr)});
    //    interpreter.interpret(expr).print();
    //    allocator.destroy(expr);
    //}

    const stdin = std.io.getStdIn().reader();
    var buf: [4096]u8 = undefined;
    while (true) {
        try stdout.print("> ", .{});
        const bytes = try stdin.read(&buf);
        if (bytes == 0) break;
        var expr = parser.parseRepl(buf[0..bytes]) orelse {
            std.log.info("Error!", .{});
            continue;
        };
        interpreter.interpret(expr).print();
        expr.deinit(allocator);
        try stdout.print("\n", .{});
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
