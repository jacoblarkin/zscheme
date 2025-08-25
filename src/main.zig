const std = @import("std");
const Parser = @import("parser.zig");
const Interpreter = @import("twi.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    //const stdout = std.io.getStdOut().writer();
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

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

    //const stdin = std.io.getStdIn().reader();
    var buf: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&buf);
    const stdin = &stdin_reader.interface;
    while (true) {
        try stdout.print("> ", .{});
        try stdout.flush();
        //const bytes = try stdin.read(&buf);
        //const bytes = try stdin.read(&buf);
        const line = try stdin.takeDelimiterExclusive('\n');
        if (line.len == 0) break;
        var expr = parser.parseRepl(line) orelse {
            std.log.info("Error!", .{});
            continue;
        };
        interpreter.interpret(expr).print();
        expr.deinit(allocator);
        try stdout.print("\n", .{});
        try stdout.flush();
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
