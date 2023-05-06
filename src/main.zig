const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    std.log.info("All your codebase are belong to us.", .{});

    var lex = try lexer.Lexer.init(allocator, "test.scm");
    defer lex.deinit();

    std.log.info("Created lexer", .{});

    try stdout.print("{s}\n", .{lex.contents});

    while (true) {
        var tok = try lex.getNextToken();
        std.debug.print("{s}\n", .{tok});
        if (tok.value == lexer.TokenValue.EndOfFile) {
            break;
        }
    }
    //    var file = try std.fs.cwd().openFile("test.scm", .{});
    //    defer file.close();
    //
    //    const limit = std.math.maxInt(u32); // Use 4GiB limit for now
    //    const contents = try file.readToEndAlloc(allocator, limit);
    //    defer allocator.free(contents);
    //
    //    try stdout.print("{s}\n", .{contents});
    //
    //    var contents_iter = (try std.unicode.Utf8View.init(contents)).iterator();
    //    while (contents_iter.nextCodepointSlice()) |codepoint| {
    //        std.debug.print("{s}\n", .{codepoint});
    //    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
