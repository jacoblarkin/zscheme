const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

pub const TokenTag = enum {
    BoolLiteral,
    CharLiteral,
    ComplexLiteral,
    IntegerLiteral,
    RationalLiteral,
    RealLiteral,
    StringLiteral,
    ByteVectorBegin,
    VecBegin,
    Quote,
    QuasiQuote,
    Identifier,
    Comma,
    CommaAt,
    Cons,
    LParen,
    RParen,
    Comment,
    EndOfFile,
};

pub const TokenValue = union(TokenTag) {
    BoolLiteral: bool,
    CharLiteral: u8,
    ComplexLiteral: [2]f64,
    IntegerLiteral: i64,
    RationalLiteral: [2]i64,
    RealLiteral: f64,
    StringLiteral: []const u8,
    ByteVectorBegin: void,
    VecBegin: void,
    Quote: void,
    QuasiQuote: void,
    Identifier: []const u8,
    Comma: void,
    CommaAt: void,
    Cons: void,
    LParen: void,
    RParen: void,
    Comment: []const u8,
    EndOfFile: void,

    fn negate(self: *TokenValue) void {
        switch (self.*) {
            TokenValue.IntegerLiteral => |v| self.IntegerLiteral = -1 * v,
            TokenValue.RationalLiteral => |v| self.RationalLiteral = [2]i64{ -1 * v[0], v[1] },
            TokenValue.RealLiteral => |v| self.RealLiteral = -1 * v,
            TokenValue.ComplexLiteral => |v| self.ComplexLiteral = [2]f64{ -1 * v[0], -1 * v[1] },
            else => {},
        }
    }
};

pub const Token = struct {
    filename: []const u8,
    contents: []const u8,
    line: usize,
    column: usize,
    position: usize,
    value: TokenValue,

    pub fn default() Token {
        return Token{
            .filename = "",
            .contents = "",
            .line = 0,
            .column = 0,
            .position = 0,
            .value = TokenValue{ .EndOfFile = {} },
        };
    }
};

pub const LexError = error{
    RanOutOfCodepoints,
    ExpectedSuffix,
    ExpectedNumeralAfterDecPt,
    ExpectedNumeralAfterSlash,
    RequestLargerThanPosition,
    ExpectedI,
    ExpectedQuote,
    ExpectedEscapedChar,
    ExpectedHexValue,
    NotValidEscape,
    ExpectedCharacter,
    NotChar,
    NotBool,
    NotIdentifier,
    UnexpectedEndOfFile,
    InvalidToken,
    UnclosedNestedComment,
    ExpectedDelimeter,
};

pub const Lexer = struct {
    filename: []const u8,
    allocator: std.mem.Allocator,
    contents: []const u8,
    contents_iter: std.unicode.Utf8Iterator,
    repl: bool,
    line: usize,
    column: usize,
    position: usize,
    strings: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Lexer {
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const limit = std.math.maxInt(u32);
        const contents = try file.readToEndAlloc(allocator, limit);

        return Lexer{
            .filename = filename,
            .allocator = allocator,
            .contents = contents,
            .contents_iter = (try std.unicode.Utf8View.init(contents)).iterator(),
            .repl = false,
            .line = 1,
            .column = 1,
            .position = 0,
            .strings = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn initRepl(allocator: std.mem.Allocator) Lexer {
        return Lexer{
            .filename = "",
            .allocator = allocator,
            .contents = "",
            .contents_iter = std.unicode.Utf8View.initUnchecked("").iterator(),
            .repl = true,
            .line = 0,
            .column = 1,
            .position = 0,
            .strings = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn errorMsg(err: anyerror) []const u8 {
        return switch (err) {
            LexError.RanOutOfCodepoints => "Lexing Error: Ran out of codepoints",
            LexError.ExpectedSuffix => "Lexing Error: Expected suffix",
            LexError.ExpectedNumeralAfterDecPt => "Lexing Error: Expected numeral after decimal point",
            LexError.ExpectedNumeralAfterSlash => "Lexing Error: Expected numeral after slash",
            LexError.RequestLargerThanPosition => "Lexing Error: Request larger than position in file",
            LexError.ExpectedI => "Lexing Error: Expected imaginary 'i'",
            LexError.ExpectedQuote => "Lexing Error: Expected quote '\"'",
            LexError.ExpectedEscapedChar => "Lexing Error: Expected escaped char",
            LexError.ExpectedHexValue => "Lexing Error: Expected hexadecimal value",
            LexError.NotValidEscape => "Lexing Error: Not a valid escape sequence",
            LexError.ExpectedCharacter => "Lexing Error: Expected character",
            LexError.NotChar => "Lexing Error: Not a characted",
            LexError.NotBool => "Lexing Error: Not a bool",
            LexError.NotIdentifier => "Lexing Error: Not an identifier",
            LexError.UnexpectedEndOfFile => "Lexing Error: Unexpected end of file",
            LexError.InvalidToken => "Lexing Error: Invalid token",
            LexError.UnclosedNestedComment => "Lexing Error: Unclosed nested comment",
            LexError.ExpectedDelimeter => "Lexing Error: Expected delimeter at the end of token",
            else => "Other error!",
        };
    }

    pub fn replLine(lexer: *Lexer, contents: []const u8) !void {
        lexer.contents = contents;
        lexer.contents_iter = (try std.unicode.Utf8View.init(contents)).iterator();
        lexer.line += 1;
        lexer.column = 1;
        lexer.position = 0;
    }

    pub fn deinit(l: *Lexer) void {
        for (l.strings.items) |s| {
            l.allocator.free(s);
        }
        l.strings.deinit();
        if (!l.repl) {
            l.allocator.free(l.contents);
        }
    }

    fn peek(l: *Lexer, n: usize) []const u8 {
        return l.contents_iter.peek(n);
    }

    fn forward(l: *Lexer, n: usize) !void {
        var count = n;
        while (count > 0) {
            const cp: u21 = l.contents_iter.nextCodepoint() orelse return LexError.RanOutOfCodepoints;
            l.position += 1;
            if (cp == '\n') {
                l.line += 1;
                l.column = 1;
            } else {
                l.column += 1;
            }
            count -= 1;
        }
    }

    fn next(l: *Lexer, n: usize) ![]const u8 {
        const ret: []const u8 = l.peek(n);
        try l.forward(n);
        return ret;
    }

    pub fn nextOpt(l: *Lexer) ?[]const u8 {
        return l.next(1) catch return null;
    }

    fn contents_back(l: *Lexer, n: usize) ![]const u8 {
        if (n > l.position) {
            return LexError.RequestLargerThanPosition;
        }
        const start: usize = l.position - n;
        return l.contents[start..l.position];
    }

    pub fn getNextToken(l: *Lexer) !Token {
        var tok: Token = Token{
            .filename = l.filename,
            .contents = "",
            .line = l.line,
            .column = l.column,
            .position = l.position,
            .value = TokenValue{ .EndOfFile = {} },
        };
        var first: []const u8 = l.peek(1);
        if (first.len == 0) {
            return tok;
        }
        while (whitespace(first[0])) {
            try l.forward(1);
            first = l.peek(1);
            if (first.len == 0) {
                tok.line = l.line;
                tok.column = l.column;
                tok.position = l.position;
                return tok;
            }
        }
        tok.line = l.line;
        tok.column = l.column;
        tok.position = l.position;
        switch (first[0]) {
            '(' => {
                try l.forward(1);
                tok.value = TokenValue{ .LParen = {} };
                tok.contents = first;
                return tok;
            },
            ')' => {
                try l.forward(1);
                tok.value = TokenValue{ .RParen = {} };
                tok.contents = first;
                return tok;
            },
            '\'' => {
                try l.forward(1);
                tok.value = TokenValue{ .Quote = {} };
                tok.contents = first;
                return tok;
            },
            '`' => {
                try l.forward(1);
                tok.value = TokenValue{ .QuasiQuote = {} };
                tok.contents = first;
                return tok;
            },
            '.' => {
                const firstTwo: []const u8 = l.peek(2);
                if (firstTwo.len == 1 or (firstTwo.len == 2 and
                    !(digit(firstTwo[1]) or dot_subsequent(firstTwo[1]))))
                {
                    try l.forward(1);
                    tok.value = TokenValue{ .Cons = {} };
                    tok.contents = first;
                } else if (digit(firstTwo[1])) {
                    tok.value = try number(l);
                    tok.contents = try l.contents_back(l.position - tok.position);
                } else {
                    tok.value = try identifier(l);
                    tok.contents = try l.contents_back(l.position - tok.position);
                }
            },
            ',' => {
                const firstTwo: []const u8 = l.peek(2);
                if (firstTwo.len == 2 and firstTwo[1] == '@') {
                    try l.forward(2);
                    tok.value = TokenValue{ .CommaAt = {} };
                    tok.contents = firstTwo;
                } else {
                    try l.forward(1);
                    tok.value = TokenValue{ .Comma = {} };
                    tok.contents = first;
                }
                return tok;
            },
            ';' => {
                tok.value = try comment(l, false);
                tok.contents = try l.contents_back(l.position - tok.position);
                return tok;
            },
            '#' => {
                const firstTwo: []const u8 = l.peek(2);
                if (firstTwo.len != 2) {
                    return LexError.ExpectedCharacter;
                }
                switch (firstTwo[1]) {
                    '(' => {
                        try l.forward(2);
                        tok.value = TokenValue{ .VecBegin = {} };
                        tok.contents = firstTwo;
                        return tok;
                    },
                    't', 'f' => {
                        tok.value = try boolean(l);
                        tok.contents = try l.contents_back(l.position - tok.position);
                    },
                    '\\' => {
                        tok.value = try character(l);
                        tok.contents = try l.contents_back(l.position - tok.position);
                    },
                    '|' => {
                        tok.value = try comment(l, true);
                        tok.contents = try l.contents_back(l.position - tok.position);
                        return tok;
                    },
                    'u' => {
                        const firstFour: []const u8 = l.peek(4);
                        if (firstFour.len != 4 or !std.mem.eql(u8, firstFour, "#u8(")) {
                            return LexError.InvalidToken;
                        }
                        try l.forward(4);
                        tok.value = TokenValue{ .ByteVectorBegin = {} };
                        tok.contents = firstFour;
                        return tok;
                    },
                    'i', 'e', 'b', 'o', 'd', 'x' => {
                        tok.value = try number(l);
                        tok.contents = try l.contents_back(l.position - tok.position);
                    },
                    else => return LexError.InvalidToken,
                }
            },
            '"' => {
                tok.value = try string(l);
                tok.contents = try l.contents_back(l.position - tok.position);
            },
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                tok.value = try number(l);
                tok.contents = try l.contents_back(l.position - tok.position);
            },
            '+', '-' => {
                const firstTwo: []const u8 = l.peek(2);
                if (firstTwo.len == 2 and digit(firstTwo[1])) {
                    tok.value = try number(l);
                    tok.contents = try l.contents_back(l.position - tok.position);
                } else {
                    tok.value = identifier(l) catch try number(l);
                    tok.contents = try l.contents_back(l.position - tok.position);
                }
            },
            else => {
                tok.value = try identifier(l);
                tok.contents = try l.contents_back(l.position - tok.position);
            },
        }
        const del: []const u8 = l.peek(1);
        if (del.len > 0 and !delimeter(del[0])) {
            std.debug.print("Delimeter: {s}\n", .{del});
            return LexError.ExpectedDelimeter;
        }
        return tok;
    }
};

fn delimeter(c: u8) bool {
    return whitespace(c) or c == ';' or c == '(' or c == '|' or
        c == ')' or c == '"';
}

test "delimeter" {
    try expect(delimeter(' '));
    try expect(delimeter('\n'));
    try expect(delimeter('\r'));
    try expect(delimeter('\t'));
    try expect(delimeter(';'));
    try expect(delimeter('('));
    try expect(delimeter('|'));
    try expect(delimeter(')'));
    try expect(delimeter('"'));

    try expect(!delimeter('a'));
    try expect(!delimeter('B'));
    try expect(!delimeter('.'));
    try expect(!delimeter(','));
    try expect(!delimeter('0'));
    try expect(!delimeter('5'));
    try expect(!delimeter('^'));
    try expect(!delimeter('@'));
    try expect(!delimeter('*'));
    try expect(!delimeter(':'));
    try expect(!delimeter('`'));
    try expect(!delimeter('\''));
}

fn comment(l: *Lexer, nested: bool) !TokenValue {
    if (nested) {
        try l.forward(2);
        var ch = try l.next(1);
        var count: usize = 1;
        if (ch.len < 1) {
            return LexError.UnclosedNestedComment;
        }
        var nesting: usize = 1;
        var state: i2 = if (ch[0] == '|') 1 else if (ch[0] == '#') -1 else 0;
        while (nesting > 0) {
            ch = try l.next(1);
            if (ch.len < 1) return LexError.UnclosedNestedComment;
            if (state > 0 and ch[0] == '#') nesting -= 1;
            if (state < 0 and ch[0] == '|') nesting += 1;
            state += if (ch[0] == '|') 1 else if (ch[0] == '#') -1 else 0;
            count += 1;
        }
        var com: []const u8 = try l.contents_back(count);
        return TokenValue{ .Comment = com[0 .. count - 2] };
    }
    var count: usize = 0;
    var ch: []const u8 = l.peek(1);
    while (ch.len == 1 and ch[0] != '\n') {
        count += 1;
        try l.forward(1);
        ch = l.peek(1);
    }
    var com: []const u8 = try l.contents_back(count);
    return TokenValue{ .Comment = com[1..count] };
}

test "lex comment" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine(";abc def ghi\nabc");
    try expectEqualStrings((try comment(&lex, false)).Comment, "abc def ghi");
    try lex.replLine(";\nabc");
    try expectEqualStrings((try comment(&lex, false)).Comment, "");
    try lex.replLine("#||#");
    try expectEqualStrings((try comment(&lex, true)).Comment, "");
    try lex.replLine("#|#||#|#");
    try expectEqualStrings((try comment(&lex, true)).Comment, "#||#");
    try lex.replLine("#|abc\ndef\nghi\n|#");
    try expectEqualStrings((try comment(&lex, true)).Comment, "abc\ndef\nghi\n");
}

fn identifier(l: *Lexer) !TokenValue {
    const reg_ident: usize = try regular_identifier(l);
    if (reg_ident != 0) {
        const ident = try l.contents_back(reg_ident);
        return TokenValue{ .Identifier = ident };
    }
    const symbol_ident: usize = try symbol_identifier(l);
    if (symbol_ident != 0) {
        const ident = try l.contents_back(symbol_ident);
        return TokenValue{ .Identifier = try parseSymbolIdent(l, ident) };
    }
    const peculiar_ident: usize = try peculiar_identifier(l);
    if (peculiar_ident == 0) {
        return LexError.NotIdentifier;
    }
    const ident = try l.contents_back(peculiar_ident);
    if (actuallyNumber(ident)) {
        return LexError.NotIdentifier;
    }
    return TokenValue{ .Identifier = ident };
}

test "lex identifier" {
    var lex = Lexer.initRepl(std.testing.allocator);
    defer lex.deinit();

    try lex.replLine("abc123");
    try expectEqualStrings((try identifier(&lex)).Identifier, "abc123");
    try lex.replLine("+");
    try expectEqualStrings((try identifier(&lex)).Identifier, "+");
    try lex.replLine("-");
    try expectEqualStrings((try identifier(&lex)).Identifier, "-");
    try lex.replLine("$@?");
    try expectEqualStrings((try identifier(&lex)).Identifier, "$@?");
    try lex.replLine("|abc 123 \\n\\x3b|");
    try expectEqualStrings((try identifier(&lex)).Identifier, "abc 123 \n\x3b");
    try lex.replLine("+.a1");
    try expectEqualStrings((try identifier(&lex)).Identifier, "+.a1");
    try lex.replLine("+ia");
    try expectEqualStrings((try identifier(&lex)).Identifier, "+ia");
    try lex.replLine("nan.0");
    try expectEqualStrings((try identifier(&lex)).Identifier, "nan.0");
    try lex.replLine("+inf.04");
    try expectEqualStrings((try identifier(&lex)).Identifier, "+inf.04");

    try lex.replLine("+i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("-i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("+inf.0");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("+nan.0");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("-inf.0i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("-nan.0");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("+inf.0i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("-inf.0i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("+nan.0i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("-nan.0i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("-nan.0+inf.0i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("+nan.0-inf.0i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("+nan.0-3.4i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
    try lex.replLine("-nan.0+4/3i");
    try expectError(LexError.NotIdentifier, identifier(&lex));
}

fn actuallyNumber(ident: []const u8) bool {
    if (std.mem.eql(u8, ident, "+i") or std.mem.eql(u8, ident, "-i") or
        std.mem.eql(u8, ident, "+inf.0") or std.mem.eql(u8, ident, "-inf.0") or
        std.mem.eql(u8, ident, "+nan.0") or std.mem.eql(u8, ident, "-nan.0") or
        std.mem.eql(u8, ident, "+inf.0i") or std.mem.eql(u8, ident, "-inf.0i") or
        std.mem.eql(u8, ident, "+nan.0i") or std.mem.eql(u8, ident, "-nan.0i"))
    {
        return true;
    }

    if (ident.len > 7 and (std.mem.eql(u8, ident[0..6], "+nan.0") or std.mem.eql(u8, ident[0..6], "-nan.0") or
        std.mem.eql(u8, ident[0..6], "+inf.0") or std.mem.eql(u8, ident[0..6], "-inf.0")) and
        (ident[6] == '+' or ident[6] == '-' or ident[6] == '@'))
    {
        if (std.mem.eql(u8, ident[6..], "+i") or std.mem.eql(u8, ident[6..], "-i") or
            std.mem.eql(u8, ident[6..], "+inf.0i") or std.mem.eql(u8, ident[6..], "-inf.0i") or
            std.mem.eql(u8, ident[6..], "+nan.0i") or std.mem.eql(u8, ident[6..], "-nan.0i") or
            (ident[6] == '@' and (std.mem.eql(u8, ident[7..], "+inf.0") or std.mem.eql(u8, ident[7..], "-inf.0") or
            std.mem.eql(u8, ident[7..], "+nan.0") or std.mem.eql(u8, ident[7..], "-nan.0"))))
        {
            return true;
        }

        var foundDotSlash: bool = false;
        for (ident[7..], 0..) |c, i| {
            if (!digit(c) and ((c != '.' and c != '/') or foundDotSlash) and
                (c != 'i' or i != ident.len - 8) and (c != '-' or i != 0))
            {
                return false;
            }
            if (c == '.' or c == '/') foundDotSlash = true;
        }
        if (ident[6] == '+' or ident[6] == '-') return ident[ident.len - 1] == 'i';
        return true;
    }

    return false;
}

test "actuallyNumber" {
    try expect(actuallyNumber("+i"));
    try expect(actuallyNumber("-i"));
    try expect(actuallyNumber("+nan.0"));
    try expect(actuallyNumber("-nan.0"));
    try expect(actuallyNumber("+inf.0"));
    try expect(actuallyNumber("-inf.0"));
    try expect(actuallyNumber("+nan.0i"));
    try expect(actuallyNumber("-nan.0i"));
    try expect(actuallyNumber("+inf.0i"));
    try expect(actuallyNumber("-inf.0i"));
    try expect(actuallyNumber("+nan.0+i"));
    try expect(actuallyNumber("-nan.0-i"));
    try expect(actuallyNumber("+nan.0+nan.0i"));
    try expect(actuallyNumber("-nan.0-nan.0i"));
    try expect(actuallyNumber("+inf.0+inf.0i"));
    try expect(actuallyNumber("-inf.0-inf.0i"));
    try expect(actuallyNumber("+nan.0-inf.0i"));
    try expect(actuallyNumber("-nan.0+inf.0i"));
    try expect(actuallyNumber("+inf.0-nan.0i"));
    try expect(actuallyNumber("-inf.0+nan.0i"));
    try expect(actuallyNumber("+nan.0+3.2i"));
    try expect(actuallyNumber("-nan.0-47i"));
    try expect(actuallyNumber("+inf.0+3/4i"));
    try expect(actuallyNumber("-inf.0@+inf.0"));
    try expect(actuallyNumber("-inf.0@+nan.0"));
    try expect(actuallyNumber("+nan.0@+inf.0"));
    try expect(actuallyNumber("-inf.0@7.1"));
    try expect(actuallyNumber("-inf.0@3/4"));
    try expect(actuallyNumber("-inf.0@-0.5"));
    try expect(actuallyNumber("-inf.0@-2/3"));

    try expect(!actuallyNumber("+ia"));
    try expect(!actuallyNumber("-i2"));
    try expect(!actuallyNumber("+nan.0w"));
    try expect(!actuallyNumber("-nan.0534"));
    try expect(!actuallyNumber("+inf.0.."));
    try expect(!actuallyNumber("-inf.0/+inf.0"));
    try expect(!actuallyNumber("nan.0"));
    try expect(!actuallyNumber("nan.0"));
    try expect(!actuallyNumber("inf.0"));
    try expect(!actuallyNumber("inf.0"));
    try expect(!actuallyNumber("+nan.0+nan.0"));
    try expect(!actuallyNumber("-nan.0-nan.0"));
    try expect(!actuallyNumber("+inf.0+inf.0"));
    try expect(!actuallyNumber("-inf.0-inf.0"));
    try expect(!actuallyNumber("+nan.0-inf.0"));
    try expect(!actuallyNumber("-nan.0+inf.0"));
    try expect(!actuallyNumber("+inf.0-nan.0"));
    try expect(!actuallyNumber("-inf.0+nan.0"));
    try expect(!actuallyNumber("+nan.0+3.2"));
    try expect(!actuallyNumber("-nan.0-47"));
    try expect(!actuallyNumber("+inf.0+3/4"));
    try expect(!actuallyNumber("-inf.0@inf.0"));
    try expect(!actuallyNumber("-inf.0@nan.0"));
    try expect(!actuallyNumber("+nan.0@inf.0"));
    try expect(!actuallyNumber("-inf.0@.7.1"));
    try expect(!actuallyNumber("-inf.0@3/4.0"));
    try expect(!actuallyNumber("-inf.0@-0.5.1.2"));
    try expect(!actuallyNumber("-inf.0@--2/3"));
}

fn parseSymbolIdent(lex: *Lexer, ident: []const u8) ![]const u8 {
    if (ident.len == 0) return ident;
    var count: usize = 0;
    var i: usize = 0;
    while (i < ident.len) : (i += 1) {
        if (ident[i] == '\\') {
            count += 1;
            switch (ident[i + 1]) {
                '|', 'a', 'b', 'n', 'r', 't' => i += 1,
                'x' => i += 3,
                else => unreachable,
            }
        } else {
            count += if (ident[i] == '|') 0 else 1;
        }
    }
    var newIdent = try lex.allocator.alloc(u8, count);
    errdefer lex.allocator.free(newIdent);

    i = 1;
    var j: usize = 0;
    while (i < ident.len - 1) : (i += 1) {
        if (ident[i] == '\\') {
            i += 1;
            switch (ident[i]) {
                '|' => newIdent[j] = '|',
                'a' => newIdent[j] = '\x07',
                'b' => newIdent[j] = '\x08',
                'n' => newIdent[j] = '\n',
                'r' => newIdent[j] = '\r',
                't' => newIdent[j] = '\t',
                'x' => {
                    i += 1;
                    newIdent[j] = try std.fmt.parseInt(u8, ident[i .. i + 2], 16);
                    i += 1;
                },
                else => unreachable,
            }
            j += 1;
        } else {
            newIdent[j] = ident[i];
            j += 1;
        }
    }

    try lex.strings.append(newIdent);
    return newIdent;
}

test "parseSymbolIdent" {
    var lex = Lexer.initRepl(std.testing.allocator);
    defer lex.deinit();

    try expectEqualStrings("abc def 123 456 *&@#()", try parseSymbolIdent(&lex, "|abc def 123 456 *&@#()|"));
    try expectEqualStrings("|\x0734 \n \x3c", try parseSymbolIdent(&lex, "|\\|\\a34 \\n \\x3c|"));
}

fn peculiar_identifier(l: *Lexer) !usize {
    const init: []const u8 = l.peek(1);
    if (init.len != 1 or (init[0] != '+' and init[0] != '-' and init[0] != '.')) {
        return 0;
    }
    try l.forward(1);
    var count: usize = 1;
    if (init[0] == '+' or init[0] == '-') {
        var next_c = l.peek(1);
        if (next_c.len != 1 or
            (!sign_subsequent(next_c[0]) and next_c[0] != '.'))
        {
            return 1;
        }
        try l.forward(1);
        count += 1;
        if (next_c[0] == '.') {
            next_c = l.peek(1);
            if (next_c.len != 1 or !dot_subsequent(next_c[0])) {
                return LexError.NotIdentifier;
            }
            try l.forward(1);
            count += 1;
        }
    } else {
        const next_c = l.peek(1);
        if (next_c.len != 1 or !dot_subsequent(next_c[0])) {
            return LexError.NotIdentifier;
        }
        try l.forward(1);
        count += 1;
    }
    var next_c = l.peek(1);
    while (next_c.len == 1 and subsequent(next_c[0])) {
        count += 1;
        try l.forward(1);
        next_c = l.peek(1);
    }
    return count;
}

test "lex peculiar_identifier" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine(".+");
    try expectEqual(peculiar_identifier(&lex), 2);
    try lex.replLine("+.+");
    try expectEqual(peculiar_identifier(&lex), 3);
    try lex.replLine("-------");
    try expectEqual(peculiar_identifier(&lex), 7);
    try lex.replLine("+");
    try expectEqual(peculiar_identifier(&lex), 1);
    try lex.replLine("-");
    try expectEqual(peculiar_identifier(&lex), 1);
    try lex.replLine("..");
    try expectEqual(peculiar_identifier(&lex), 2);
    try lex.replLine(".");
    try expectError(LexError.NotIdentifier, peculiar_identifier(&lex));
    try lex.replLine("+.");
    try expectError(LexError.NotIdentifier, peculiar_identifier(&lex));
}

fn dot_subsequent(c: u8) bool {
    return sign_subsequent(c) or c == '.';
}

test "dot_subsequent" {
    try expect(dot_subsequent('a'));
    try expect(dot_subsequent('b'));
    try expect(dot_subsequent('c'));
    try expect(dot_subsequent('X'));
    try expect(dot_subsequent('Y'));
    try expect(dot_subsequent('Z'));
    try expect(dot_subsequent('!'));
    try expect(dot_subsequent('$'));
    try expect(dot_subsequent('%'));
    try expect(dot_subsequent('&'));
    try expect(dot_subsequent('*'));
    try expect(dot_subsequent('/'));
    try expect(dot_subsequent(':'));
    try expect(dot_subsequent('<'));
    try expect(dot_subsequent('='));
    try expect(dot_subsequent('>'));
    try expect(dot_subsequent('?'));
    try expect(dot_subsequent('@'));
    try expect(dot_subsequent('^'));
    try expect(dot_subsequent('_'));
    try expect(dot_subsequent('~'));
    try expect(dot_subsequent('+'));
    try expect(dot_subsequent('-'));
    try expect(dot_subsequent('.'));

    try expect(!dot_subsequent(','));
    try expect(!dot_subsequent('"'));
    try expect(!dot_subsequent('('));
    try expect(!dot_subsequent(')'));
    try expect(!dot_subsequent('\''));
    try expect(!dot_subsequent('`'));
    try expect(!dot_subsequent(';'));
    try expect(!dot_subsequent('1'));
}

fn sign_subsequent(c: u8) bool {
    return initial(c) or c == '+' or c == '-' or c == '@';
}

test "sign_subsequent" {
    try expect(sign_subsequent('a'));
    try expect(sign_subsequent('b'));
    try expect(sign_subsequent('c'));
    try expect(sign_subsequent('X'));
    try expect(sign_subsequent('Y'));
    try expect(sign_subsequent('Z'));
    try expect(sign_subsequent('!'));
    try expect(sign_subsequent('$'));
    try expect(sign_subsequent('%'));
    try expect(sign_subsequent('&'));
    try expect(sign_subsequent('*'));
    try expect(sign_subsequent('/'));
    try expect(sign_subsequent(':'));
    try expect(sign_subsequent('<'));
    try expect(sign_subsequent('='));
    try expect(sign_subsequent('>'));
    try expect(sign_subsequent('?'));
    try expect(sign_subsequent('@'));
    try expect(sign_subsequent('^'));
    try expect(sign_subsequent('_'));
    try expect(sign_subsequent('~'));
    try expect(sign_subsequent('+'));
    try expect(sign_subsequent('-'));

    try expect(!sign_subsequent(','));
    try expect(!sign_subsequent('"'));
    try expect(!sign_subsequent('('));
    try expect(!sign_subsequent(')'));
    try expect(!sign_subsequent('.'));
    try expect(!sign_subsequent('\''));
    try expect(!sign_subsequent('`'));
    try expect(!sign_subsequent(';'));
    try expect(!sign_subsequent('1'));
}

fn symbol_identifier(l: *Lexer) !usize {
    const vert: []const u8 = l.peek(1);
    if (vert.len != 1 or vert[0] != '|') {
        return 0;
    }
    try l.forward(1);
    var count: usize = 1;
    var c: []const u8 = l.peek(1);
    while (c.len > 0 and c[0] != '|') {
        count += c.len;
        try l.forward(1);
        if (c[0] == '\\') {
            c = l.peek(1);
            if (c.len != 1) {
                return LexError.ExpectedEscapedChar;
            }
            switch (c[0]) {
                'a', 'b', 't', 'n', 'r', '|' => {
                    count += 1;
                    try l.forward(1);
                },
                'x' => {
                    count += 1;
                    try l.forward(1);
                    const hexseq = l.peek(2);
                    if (hexseq.len != 2 or !digitN(16, hexseq[0]) or !digitN(16, hexseq[1])) {
                        return LexError.ExpectedHexValue;
                    }
                    count += 2;
                    try l.forward(2);
                },
                else => return LexError.NotValidEscape,
            }
        }
        c = l.peek(1);
    }

    if (c.len < 1) {
        return LexError.UnexpectedEndOfFile;
    }
    count += 1;
    try l.forward(1);
    return count;
}

test "symbol_identifier" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("|abc def 123 456 *&@#()|");
    try expectEqual(symbol_identifier(&lex), 24);
    try lex.replLine("|\\|\\a34 \\n \\x3c|");
    try expectEqual(symbol_identifier(&lex), 16);
}

fn regular_identifier(l: *Lexer) !usize {
    const start: []const u8 = l.peek(1);
    if (start.len < 1) {
        return LexError.ExpectedCharacter;
    }
    if (!initial(start[0])) {
        return 0;
    }
    var count: usize = 1;
    try l.forward(1);
    var c: []const u8 = l.peek(1);
    while (c.len > 0 and subsequent(c[0])) {
        count += 1;
        try l.forward(1);
        c = l.peek(1);
    }
    return count;
}

test "lex regular_identifier" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("abc@123");
    try expectEqual(regular_identifier(&lex), 7);
    try lex.replLine("<X:&7");
    try expectEqual(regular_identifier(&lex), 5);
    try lex.replLine("|abc|");
    try expectEqual(regular_identifier(&lex), 0);
    try lex.replLine(".abc");
    try expectEqual(regular_identifier(&lex), 0);
    try lex.replLine("1z+2r");
    try expectEqual(regular_identifier(&lex), 0);
    try lex.replLine("$$$");
    try expectEqual(regular_identifier(&lex), 3);
    try lex.replLine("a(b)");
    try expectEqual(regular_identifier(&lex), 1);
}

fn subsequent(c: u8) bool {
    return initial(c) or digit(c) or specialSubsequent(c);
}

test "subsequent" {
    try expect(subsequent('a'));
    try expect(subsequent('b'));
    try expect(subsequent('c'));
    try expect(subsequent('X'));
    try expect(subsequent('Y'));
    try expect(subsequent('Z'));
    try expect(subsequent('!'));
    try expect(subsequent('$'));
    try expect(subsequent('%'));
    try expect(subsequent('&'));
    try expect(subsequent('*'));
    try expect(subsequent('/'));
    try expect(subsequent(':'));
    try expect(subsequent('<'));
    try expect(subsequent('='));
    try expect(subsequent('>'));
    try expect(subsequent('?'));
    try expect(subsequent('@'));
    try expect(subsequent('^'));
    try expect(subsequent('_'));
    try expect(subsequent('~'));
    try expect(subsequent('1'));
    try expect(subsequent('+'));
    try expect(subsequent('-'));
    try expect(subsequent('.'));

    try expect(!subsequent(','));
    try expect(!subsequent('"'));
    try expect(!subsequent('('));
    try expect(!subsequent(')'));
    try expect(!subsequent('\''));
    try expect(!subsequent('`'));
    try expect(!subsequent(';'));
}

fn specialSubsequent(c: u8) bool {
    switch (c) {
        '+', '-', '.', '@' => return true,
        else => return false,
    }
}

test "specialSubsequent" {
    try expect(specialSubsequent('+'));
    try expect(specialSubsequent('-'));
    try expect(specialSubsequent('.'));
    try expect(specialSubsequent('@'));

    try expect(!specialSubsequent('('));
    try expect(!specialSubsequent(')'));
    try expect(!specialSubsequent(';'));
    try expect(!specialSubsequent(','));
    try expect(!specialSubsequent('\''));
    try expect(!specialSubsequent('"'));
    try expect(!specialSubsequent('`'));
}

fn initial(c: u8) bool {
    return std.ascii.isAlphabetic(c) or specialInitial(c);
}

test "initial" {
    try expect(initial('a'));
    try expect(initial('b'));
    try expect(initial('c'));
    try expect(initial('X'));
    try expect(initial('Y'));
    try expect(initial('Z'));
    try expect(initial('!'));
    try expect(initial('$'));
    try expect(initial('%'));
    try expect(initial('&'));
    try expect(initial('*'));
    try expect(initial('/'));
    try expect(initial(':'));
    try expect(initial('<'));
    try expect(initial('='));
    try expect(initial('>'));
    try expect(initial('?'));
    try expect(initial('@'));
    try expect(initial('^'));
    try expect(initial('_'));
    try expect(initial('~'));

    try expect(!initial(','));
    try expect(!initial('"'));
    try expect(!initial('('));
    try expect(!initial(')'));
    try expect(!initial('.'));
    try expect(!initial('\''));
    try expect(!initial('`'));
    try expect(!initial(';'));
    try expect(!initial('|'));
    try expect(!initial('1'));
    try expect(!initial('+'));
    try expect(!initial('-'));
}

fn specialInitial(c: u8) bool {
    switch (c) {
        '!', '$', '%', '&', '*', '/', ':', '<', '=', '>', '?', '@', '^', '_', '~' => return true,
        else => return false,
    }
}

test "specialInitial" {
    try expect(specialInitial('!'));
    try expect(specialInitial('$'));
    try expect(specialInitial('%'));
    try expect(specialInitial('&'));
    try expect(specialInitial('*'));
    try expect(specialInitial('/'));
    try expect(specialInitial(':'));
    try expect(specialInitial('<'));
    try expect(specialInitial('='));
    try expect(specialInitial('>'));
    try expect(specialInitial('?'));
    try expect(specialInitial('@'));
    try expect(specialInitial('^'));
    try expect(specialInitial('_'));
    try expect(specialInitial('~'));

    try expect(!specialInitial('a'));
    try expect(!specialInitial('B'));
    try expect(!specialInitial(','));
    try expect(!specialInitial('"'));
    try expect(!specialInitial('('));
    try expect(!specialInitial(')'));
    try expect(!specialInitial('.'));
    try expect(!specialInitial('\''));
    try expect(!specialInitial('`'));
    try expect(!specialInitial(';'));
    try expect(!specialInitial('1'));
    try expect(!specialInitial('+'));
    try expect(!specialInitial('-'));
}

fn boolean(l: *Lexer) !TokenValue {
    var boolCandidate: []const u8 = l.peek(6);
    if (boolCandidate.len < 2 or boolCandidate[0] != '#' or
        (boolCandidate[1] != 't' and boolCandidate[1] != 'f'))
    {
        return LexError.NotBool;
    }
    if (boolCandidate.len >= 5 and std.mem.eql(u8, boolCandidate[1..5], "true")) {
        try l.forward(5);
        return TokenValue{ .BoolLiteral = true };
    }
    if (boolCandidate.len >= 6 and std.mem.eql(u8, boolCandidate[1..6], "false")) {
        try l.forward(6);
        return TokenValue{ .BoolLiteral = false };
    }
    try l.forward(2);
    if (boolCandidate[1] == 't') {
        return TokenValue{ .BoolLiteral = true };
    }
    return TokenValue{ .BoolLiteral = false };
}

test "lex boolean" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("#t");
    try expectEqual(TokenValue{ .BoolLiteral = true }, try boolean(&lex));
    try lex.replLine("#true");
    try expectEqual(TokenValue{ .BoolLiteral = true }, try boolean(&lex));
    try lex.replLine("#f");
    try expectEqual(TokenValue{ .BoolLiteral = false }, try boolean(&lex));
    try lex.replLine("#false");
    try expectEqual(TokenValue{ .BoolLiteral = false }, try boolean(&lex));
    try lex.replLine("#notabool");
    try expectError(LexError.NotBool, boolean(&lex));
}

fn character(l: *Lexer) !TokenValue {
    const hashslash: []const u8 = l.peek(2);
    if (hashslash.len != 2 or !std.mem.eql(u8, hashslash, "#\\")) {
        return LexError.NotChar;
    }
    try l.forward(2);

    const nexttwo: []const u8 = l.peek(2);
    if (nexttwo.len == 0) {
        return LexError.NotChar;
    }
    if (nexttwo.len == 1 or (nexttwo.len == 2 and whitespace(nexttwo[1]))) {
        try l.forward(1);
        return TokenValue{ .CharLiteral = nexttwo[0] };
    }
    if (std.mem.eql(u8, nexttwo, "al")) {
        const alarm = l.peek(5);
        if (std.mem.eql(u8, alarm, "alarm")) {
            try l.forward(5);
            return TokenValue{ .CharLiteral = '\x07' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'a' };
    } else if (std.mem.eql(u8, nexttwo, "ba")) {
        const backspace = l.peek(9);
        if (std.mem.eql(u8, backspace, "backspace")) {
            try l.forward(9);
            return TokenValue{ .CharLiteral = '\x08' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'b' };
    } else if (std.mem.eql(u8, nexttwo, "de")) {
        const delete = l.peek(6);
        if (std.mem.eql(u8, delete, "delete")) {
            try l.forward(6);
            return TokenValue{ .CharLiteral = '\x7F' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'd' };
    } else if (std.mem.eql(u8, nexttwo, "es")) {
        const escape = l.peek(6);
        if (std.mem.eql(u8, escape, "escape")) {
            try l.forward(6);
            return TokenValue{ .CharLiteral = '\x1b' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'e' };
    } else if (std.mem.eql(u8, nexttwo, "ne")) {
        const newline = l.peek(7);
        if (std.mem.eql(u8, newline, "newline")) {
            try l.forward(7);
            return TokenValue{ .CharLiteral = '\n' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'n' };
    } else if (std.mem.eql(u8, nexttwo, "nu")) {
        const null_ = l.peek(4);
        if (std.mem.eql(u8, null_, "null")) {
            try l.forward(4);
            return TokenValue{ .CharLiteral = 0 };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'n' };
    } else if (std.mem.eql(u8, nexttwo, "re")) {
        const return_ = l.peek(6);
        if (std.mem.eql(u8, return_, "return")) {
            try l.forward(6);
            return TokenValue{ .CharLiteral = '\r' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'r' };
    } else if (std.mem.eql(u8, nexttwo, "sp")) {
        const space = l.peek(5);
        if (std.mem.eql(u8, space, "space")) {
            try l.forward(5);
            return TokenValue{ .CharLiteral = ' ' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 's' };
    } else if (std.mem.eql(u8, nexttwo, "ta")) {
        const tab = l.peek(3);
        if (std.mem.eql(u8, tab, "tab")) {
            try l.forward(3);
            return TokenValue{ .CharLiteral = '\t' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 't' };
    } else {
        if (nexttwo[0] == 'x') {
            var hexescape = l.peek(3);
            try l.forward(3);
            const ch: u8 = try std.fmt.parseInt(u8, hexescape[1..3], 16);
            return TokenValue{ .CharLiteral = ch };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = nexttwo[0] };
    }
}

test "lex character" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("#\\a");
    try expectEqual(TokenValue{ .CharLiteral = 'a' }, try character(&lex));

    try lex.replLine("#\\B");
    try expectEqual(TokenValue{ .CharLiteral = 'B' }, try character(&lex));

    try lex.replLine("#\\ ");
    try expectEqual(TokenValue{ .CharLiteral = ' ' }, try character(&lex));

    try lex.replLine("#\\alarm");
    try expectEqual(TokenValue{ .CharLiteral = '\x07' }, try character(&lex));

    try lex.replLine("#\\backspace");
    try expectEqual(TokenValue{ .CharLiteral = '\x08' }, try character(&lex));

    try lex.replLine("#\\delete");
    try expectEqual(TokenValue{ .CharLiteral = '\x7f' }, try character(&lex));

    try lex.replLine("#\\escape");
    try expectEqual(TokenValue{ .CharLiteral = '\x1b' }, try character(&lex));

    try lex.replLine("#\\newline");
    try expectEqual(TokenValue{ .CharLiteral = '\n' }, try character(&lex));

    try lex.replLine("#\\null");
    try expectEqual(TokenValue{ .CharLiteral = 0 }, try character(&lex));

    try lex.replLine("#\\return");
    try expectEqual(TokenValue{ .CharLiteral = '\r' }, try character(&lex));

    try lex.replLine("#\\space");
    try expectEqual(TokenValue{ .CharLiteral = ' ' }, try character(&lex));

    try lex.replLine("#\\tab");
    try expectEqual(TokenValue{ .CharLiteral = '\t' }, try character(&lex));

    try lex.replLine("#\\\\");
    try expectEqual(TokenValue{ .CharLiteral = '\\' }, try character(&lex));

    try lex.replLine("#\\x08");
    try expectEqual(TokenValue{ .CharLiteral = '\x08' }, try character(&lex));
}

fn string(l: *Lexer) !TokenValue {
    var quote: []const u8 = l.peek(1);
    if (quote.len != 1 or quote[0] != '"') {
        return LexError.ExpectedQuote;
    }
    try l.forward(1);

    var str: []u8 = try l.allocator.alloc(u8, 16);
    var count: usize = 0;
    while (true) {
        const ch: u8 = try string_element(l);
        if (ch == 0) {
            break;
        }
        str[count] = ch;
        count += 1;
        if (count >= str.len) {
            str = try l.allocator.realloc(str, str.len * 2);
        }
    }

    str = try l.allocator.realloc(str, count);
    errdefer l.allocator.free(str);
    try l.strings.append(str);

    quote = l.peek(1);
    if (quote.len != 1 or quote[0] != '"') {
        return LexError.ExpectedQuote;
    }
    try l.forward(1);

    return TokenValue{ .StringLiteral = str };
}

test "lex string" {
    var lex = Lexer.initRepl(std.testing.allocator);
    defer lex.deinit();

    try lex.replLine("\"abc def ghi\"");
    try expectEqualStrings((try string(&lex)).StringLiteral, "abc def ghi");

    try lex.replLine("\"\"");
    try expectEqualStrings((try string(&lex)).StringLiteral, "");

    try lex.replLine("\"\\a\\b\\|\"");
    try expectEqualStrings((try string(&lex)).StringLiteral, "\x07\x08|");

    try lex.replLine(
        \\"abc\  
        \\  def
        \\  "
    );
    try expectEqualStrings((try string(&lex)).StringLiteral, "abcdef\n  ");
}

fn string_element(l: *Lexer) !u8 {
    var ch: []const u8 = l.peek(1);
    if (ch.len == 1 and ch[0] == '"') {
        return 0;
    }
    try l.forward(1);
    if (ch.len == 1 and ch[0] != '\\') {
        return ch[0];
    }
    ch = l.peek(1);
    if (ch.len != 1) {
        return LexError.ExpectedEscapedChar;
    }
    switch (ch[0]) {
        'a' => {
            try l.forward(1);
            return '\x07';
        },
        'b' => {
            try l.forward(1);
            return '\x08';
        },
        't' => {
            try l.forward(1);
            return '\t';
        },
        'n' => {
            try l.forward(1);
            return '\n';
        },
        'r' => {
            try l.forward(1);
            return '\r';
        },
        '"' => {
            try l.forward(1);
            return '"';
        },
        '\\' => {
            try l.forward(1);
            return '\\';
        },
        '|' => {
            try l.forward(1);
            return '|';
        },
        'x' => {
            try l.forward(1);
            const he: []const u8 = l.peek(2);
            if (he.len != 2) {
                return LexError.ExpectedHexValue;
            }
            try l.forward(2);
            return std.fmt.parseInt(u8, he, 16);
        },
        ' ', '\t', '\n', '\r' => {
            while (whitespace(ch[0])) {
                try l.forward(1);
                ch = l.peek(1);
                if (ch.len == 0) {
                    return LexError.ExpectedCharacter;
                }
            }
            return string_element(l);
        },
        else => return LexError.NotValidEscape,
    }
}

test "lex string element" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("a");
    try expectEqual(string_element(&lex), 'a');
    try lex.replLine("A");
    try expectEqual(string_element(&lex), 'A');
    try lex.replLine("2");
    try expectEqual(string_element(&lex), '2');
    try lex.replLine(".");
    try expectEqual(string_element(&lex), '.');
    try lex.replLine("\\\\");
    try expectEqual(string_element(&lex), '\\');
    try lex.replLine("\\n");
    try expectEqual(string_element(&lex), '\n');
    try lex.replLine("\\ a");
    try expectEqual(string_element(&lex), 'a');
    try lex.replLine("\\\"");
    try expectEqual(string_element(&lex), '"');
    try lex.replLine("\\x2b");
    try expectEqual(string_element(&lex), '\x2b');
    try lex.replLine("\\");
    try expectError(LexError.ExpectedEscapedChar, string_element(&lex));
    try lex.replLine("\\x");
    try expectError(LexError.ExpectedHexValue, string_element(&lex));
    try lex.replLine("\\l");
    try expectError(LexError.NotValidEscape, string_element(&lex));
}

fn whitespace(c: u8) bool {
    switch (c) {
        ' ', '\t', '\n', '\r' => return true,
        else => return false,
    }
}

test "lex whitespace" {
    try expect(whitespace(' '));
    try expect(whitespace('\t'));
    try expect(whitespace('\n'));
    try expect(whitespace('\r'));
    try expect(!whitespace('a'));
    try expect(!whitespace('b'));
    try expect(!whitespace('3'));
    try expect(!whitespace('N'));
    try expect(!whitespace(':'));
    try expect(!whitespace('.'));
    try expect(!whitespace('\x07'));
    try expect(!whitespace('\x1b'));
}

fn number(l: *Lexer) !TokenValue {
    // TODO: Reinterpret literals based on exactness prefix
    const bases = [4]i8{ 2, 8, 16, 10 }; // 10 should be last here
    inline for (bases) |n| {
        const pre: usize = try prefix(n, l);
        if (pre != 0) return complex(n, l);
    }
    return complex(10, l);
}

test "lex number" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("#b10110");
    try expectEqual(number(&lex), TokenValue{ .IntegerLiteral = 22 });
    try lex.replLine("#o#I3324");
    try expectEqual(number(&lex), TokenValue{ .IntegerLiteral = 4 + 2 * 8 + 3 * 64 + 3 * 512 });
    try lex.replLine("#E1234");
    try expectEqual(number(&lex), TokenValue{ .IntegerLiteral = 1234 });
    try lex.replLine("#E1234/5678");
    try expectEqual(number(&lex), TokenValue{ .RationalLiteral = [2]i64{ 1234, 5678 } });
    try lex.replLine("12.34-567.1i");
    try expectEqual(number(&lex), TokenValue{ .ComplexLiteral = [2]f64{ 12.34, -567.1 } });
    try lex.replLine("#X1a2B/C28a");
    try expectEqual(number(&lex), TokenValue{ .RationalLiteral = [2]i64{ 0x1a2b, 0xc28a } });
}

fn complex(comptime n: i8, l: *Lexer) !TokenValue {
    const imag_only = l.peek(3);
    if (imag_only.len >= 2) {
        if ((imag_only[0] == '+' or imag_only[0] == '-') and imag_only[1] == 'i' and (imag_only.len == 2 or (imag_only.len == 3 and imag_only[2] != 'n'))) {
            try l.forward(2);
            var sign_f: f64 = 1.0;
            if (imag_only[0] == '-') {
                sign_f = -1.0;
            }
            return TokenValue{ .ComplexLiteral = [2]f64{
                0,
                sign_f,
            } };
        }
    }
    const tok_real: TokenValue = try realN(n, l);
    const next_c: []const u8 = l.peek(1);
    if (next_c.len != 1) {
        return tok_real;
    }
    switch (next_c[0]) {
        '@' => {
            try l.forward(1);
            const tok_exp: TokenValue = try realN(n, l);
            const coeff: f64 = switch (tok_real) {
                TokenTag.IntegerLiteral => |val| @as(f64, @floatFromInt(val)),
                TokenTag.RationalLiteral => |vals| @as(f64, @floatFromInt(vals[0])) / @as(f64, @floatFromInt(vals[1])),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            const angle: f64 = switch (tok_exp) {
                TokenTag.IntegerLiteral => |val| @as(f64, @floatFromInt(val)),
                TokenTag.RationalLiteral => |vals| @as(f64, @floatFromInt(vals[0])) / @as(f64, @floatFromInt(vals[1])),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                coeff * std.math.cos(angle),
                coeff * std.math.sin(angle),
            } };
        },
        '+', '-' => {
            var i_: []const u8 = l.peek(2);
            if (i_.len < 2) {
                return LexError.ExpectedI;
            }
            const tok_imag: TokenValue = if (i_[1] != 'i') try realN(n, l) else TokenValue{ .RealLiteral = if (i_[0] == '+') 1 else -1 };
            if (i_[1] == 'i') try l.forward(1);
            i_ = l.peek(1);
            if (i_.len != 1 or i_[0] != 'i') {
                return LexError.ExpectedI;
            }
            try l.forward(1);
            const real: f64 = switch (tok_real) {
                TokenTag.IntegerLiteral => |val| @as(f64, @floatFromInt(val)),
                TokenTag.RationalLiteral => |vals| @as(f64, @floatFromInt(vals[0])) / @as(f64, @floatFromInt(vals[1])),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            const imag: f64 = switch (tok_imag) {
                TokenTag.IntegerLiteral => |val| @as(f64, @floatFromInt(val)),
                TokenTag.RationalLiteral => |vals| @as(f64, @floatFromInt(vals[0])) / @as(f64, @floatFromInt(vals[1])),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                real, imag,
            } };
        },
        'i' => {
            try l.forward(1);
            const imag: f64 = switch (tok_real) {
                TokenTag.IntegerLiteral => |val| @as(f64, @floatFromInt(val)),
                TokenTag.RationalLiteral => |vals| @as(f64, @floatFromInt(vals[0])) / @as(f64, @floatFromInt(vals[1])),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                0.0,
                imag,
            } };
        },
        else => return tok_real,
    }
}

test "lex complex" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("+i");
    try expectEqual(complex(2, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, 1 } });
    try lex.replLine("+i");
    try expectEqual(complex(8, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, 1 } });
    try lex.replLine("+i");
    try expectEqual(complex(10, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, 1 } });
    try lex.replLine("+i");
    try expectEqual(complex(16, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, 1 } });

    try lex.replLine("-i");
    try expectEqual(complex(2, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, -1 } });
    try lex.replLine("-i");
    try expectEqual(complex(8, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, -1 } });
    try lex.replLine("-i");
    try expectEqual(complex(10, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, -1 } });
    try lex.replLine("-i");
    try expectEqual(complex(16, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, -1 } });

    try lex.replLine("11-i");
    try expectEqual(complex(2, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 3, -1 } });
    try lex.replLine("11-i");
    try expectEqual(complex(8, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 9, -1 } });
    try lex.replLine("11-i");
    try expectEqual(complex(10, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 11, -1 } });
    try lex.replLine("11-i");
    try expectEqual(complex(16, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 17, -1 } });

    try lex.replLine("10+10i");
    try expectEqual(complex(2, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 2, 2 } });
    try lex.replLine("10+10i");
    try expectEqual(complex(8, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 8, 8 } });
    try lex.replLine("10+10i");
    try expectEqual(complex(10, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 10, 10 } });
    try lex.replLine("10+10i");
    try expectEqual(complex(16, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 16, 16 } });

    try lex.replLine("+inf.0i");
    try expectEqual(complex(2, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, std.math.inf(f64) } });
    try lex.replLine("+inf.0i");
    try expectEqual(complex(8, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, std.math.inf(f64) } });
    try lex.replLine("+inf.0i");
    try expectEqual(complex(10, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, std.math.inf(f64) } });
    try lex.replLine("+inf.0i");
    try expectEqual(complex(16, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 0, std.math.inf(f64) } });

    try lex.replLine("10@10");
    try expectEqual(complex(2, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 2 * std.math.cos(2.0), 2 * std.math.sin(2.0) } });
    try lex.replLine("10@10");
    try expectEqual(complex(8, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 8 * std.math.cos(8.0), 8 * std.math.sin(8.0) } });
    try lex.replLine("10@10");
    try expectEqual(complex(10, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 10 * std.math.cos(10.0), 10 * std.math.sin(10.0) } });
    try lex.replLine("10@10");
    try expectEqual(complex(16, &lex), TokenValue{ .ComplexLiteral = [2]f64{ 16 * std.math.cos(16.0), 16 * std.math.sin(16.0) } });

    try lex.replLine("+nan.0@0.5");
    try expect(std.math.isNan((try complex(10, &lex)).ComplexLiteral[0]));
    try lex.replLine("+nan.0@0.5");
    try expect(std.math.isNan((try complex(10, &lex)).ComplexLiteral[1]));
}

fn realN(comptime n: i8, l: *Lexer) !TokenValue {
    const infnan_: usize = try infnan(l);
    if (infnan_ != 0) {
        const infnan_str = try l.contents_back(infnan_);
        const minus: bool = infnan_str[0] == '-';
        const inf: bool = infnan_str[1] == 'i';
        var val: f64 = 0;
        if (inf) {
            val = std.math.inf(f64);
        } else {
            val = std.math.nan(f64);
        }
        if (minus) {
            val *= -1;
        }
        return TokenValue{ .RealLiteral = val };
    }
    const sign_: []const u8 = l.peek(1);
    if (sign_.len == 0) {
        return LexError.ExpectedCharacter;
    }
    const minus: bool = sign_[0] == '-';
    if (sign(sign_[0])) {
        try l.forward(1);
    }
    var ureal_tok = try ureal(n, l);
    if (minus) {
        ureal_tok.negate();
    }
    return ureal_tok;
}

test "lex real" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("+inf.0");
    try expectEqual(realN(2, &lex), TokenValue{ .RealLiteral = std.math.inf(f64) });
    try lex.replLine("+inf.0");
    try expectEqual(realN(8, &lex), TokenValue{ .RealLiteral = std.math.inf(f64) });
    try lex.replLine("+inf.0");
    try expectEqual(realN(10, &lex), TokenValue{ .RealLiteral = std.math.inf(f64) });
    try lex.replLine("+inf.0");
    try expectEqual(realN(16, &lex), TokenValue{ .RealLiteral = std.math.inf(f64) });

    try lex.replLine("-inf.0");
    try expectEqual(realN(2, &lex), TokenValue{ .RealLiteral = -1 * std.math.inf(f64) });
    try lex.replLine("-inf.0");
    try expectEqual(realN(8, &lex), TokenValue{ .RealLiteral = -1 * std.math.inf(f64) });
    try lex.replLine("-inf.0");
    try expectEqual(realN(10, &lex), TokenValue{ .RealLiteral = -1 * std.math.inf(f64) });
    try lex.replLine("-inf.0");
    try expectEqual(realN(16, &lex), TokenValue{ .RealLiteral = -1 * std.math.inf(f64) });

    try lex.replLine("+nan.0");
    try expect(std.math.isNan((try realN(2, &lex)).RealLiteral));
    try lex.replLine("+nan.0");
    try expect(std.math.isNan((try realN(8, &lex)).RealLiteral));
    try lex.replLine("+nan.0");
    try expect(std.math.isNan((try realN(10, &lex)).RealLiteral));
    try lex.replLine("+nan.0");
    try expect(std.math.isNan((try realN(16, &lex)).RealLiteral));

    try lex.replLine("-nan.0");
    try expect(std.math.isNan((try realN(2, &lex)).RealLiteral));
    try lex.replLine("-nan.0");
    try expect(std.math.isNan((try realN(8, &lex)).RealLiteral));
    try lex.replLine("-nan.0");
    try expect(std.math.isNan((try realN(10, &lex)).RealLiteral));
    try lex.replLine("-nan.0");
    try expect(std.math.isNan((try realN(16, &lex)).RealLiteral));

    try lex.replLine("10.23");
    try expectEqual(realN(10, &lex), TokenValue{ .RealLiteral = 10.23 });
    try lex.replLine("-10.23");
    try expectEqual(realN(10, &lex), TokenValue{ .RealLiteral = -10.23 });
    try lex.replLine("+10.23");
    try expectEqual(realN(10, &lex), TokenValue{ .RealLiteral = 10.23 });
}

fn ureal(comptime n: i8, l: *Lexer) !TokenValue {
    const int_part: usize = try uinteger(n, l);
    const slashdec: []const u8 = l.peek(1);
    var den_count: usize = 0;
    var slash: bool = false;
    if (slashdec.len == 1 and slashdec[0] == '/') {
        try l.forward(1);
        den_count += 1;
        slash = true;
        den_count += try uinteger(n, l);
        if (den_count == 1) {
            return LexError.ExpectedNumeralAfterSlash;
        }
    } else if (n == 10 and slashdec.len == 1 and slashdec[0] == '.') {
        den_count += 1;
        try l.forward(1);
        if (int_part == 0) {
            den_count += try uinteger(n, l);
            if (den_count == 1) {
                return LexError.ExpectedNumeralAfterDecPt;
            }
        } else {
            var dig: []const u8 = l.peek(1);
            while (dig.len == 1 and digitN(n, dig[0])) {
                try l.forward(1);
                den_count += 1;
                dig = l.peek(1);
            }
        }
    }
    var suffix_part: usize = 0;
    if (!slash and n == 10) {
        suffix_part += try suffix(l);
    }
    var lit_val: []const u8 = try l.contents_back(int_part + den_count + suffix_part);
    if (slash) {
        return TokenValue{ .RationalLiteral = [2]i64{
            try std.fmt.parseInt(i64, lit_val[0..int_part], n),
            try std.fmt.parseInt(i64, lit_val[(int_part + 1)..lit_val.len], n),
        } };
    }
    if (den_count != 0 or suffix_part != 0) {
        return TokenValue{ .RealLiteral = try std.fmt.parseFloat(f64, lit_val) };
    }
    return TokenValue{ .IntegerLiteral = try std.fmt.parseInt(i64, lit_val, n) };
}

test "lex ureal" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("10");
    try expectEqual(ureal(2, &lex), TokenValue{ .IntegerLiteral = 2 });
    try lex.replLine("10");
    try expectEqual(ureal(8, &lex), TokenValue{ .IntegerLiteral = 8 });
    try lex.replLine("10");
    try expectEqual(ureal(10, &lex), TokenValue{ .IntegerLiteral = 10 });
    try lex.replLine("10");
    try expectEqual(ureal(16, &lex), TokenValue{ .IntegerLiteral = 16 });

    try lex.replLine("10e2");
    try expectEqual(ureal(2, &lex), TokenValue{ .IntegerLiteral = 2 });
    try lex.replLine("10e2");
    try expectEqual(ureal(8, &lex), TokenValue{ .IntegerLiteral = 8 });
    try lex.replLine("10e2");
    try expectEqual(ureal(10, &lex), TokenValue{ .RealLiteral = 1000.0 });
    try lex.replLine("10e2");
    try expectEqual(ureal(16, &lex), TokenValue{ .IntegerLiteral = 4322 });

    try lex.replLine("11/111");
    try expectEqual(ureal(2, &lex), TokenValue{ .RationalLiteral = [2]i64{ 3, 7 } });
    try lex.replLine("11/111");
    try expectEqual(ureal(8, &lex), TokenValue{ .RationalLiteral = [2]i64{ 9, 73 } });
    try lex.replLine("11/111");
    try expectEqual(ureal(10, &lex), TokenValue{ .RationalLiteral = [2]i64{ 11, 111 } });
    try lex.replLine("11/111");
    try expectEqual(ureal(16, &lex), TokenValue{ .RationalLiteral = [2]i64{ 17, 273 } });

    try lex.replLine("10.23");
    try expectEqual(ureal(2, &lex), TokenValue{ .IntegerLiteral = 2 });
    try lex.replLine("10.23");
    try expectEqual(ureal(8, &lex), TokenValue{ .IntegerLiteral = 8 });
    try lex.replLine("10.23");
    try expectEqual(ureal(10, &lex), TokenValue{ .RealLiteral = 10.23 });
    try lex.replLine("10.23");
    try expectEqual(ureal(16, &lex), TokenValue{ .IntegerLiteral = 16 });

    try lex.replLine("10.e2");
    try expectEqual(ureal(2, &lex), TokenValue{ .IntegerLiteral = 2 });
    try lex.replLine("10.e2");
    try expectEqual(ureal(8, &lex), TokenValue{ .IntegerLiteral = 8 });
    try lex.replLine("10.e2");
    try expectEqual(ureal(10, &lex), TokenValue{ .RealLiteral = 1000.0 });
    try lex.replLine("10.e2");
    try expectEqual(ureal(16, &lex), TokenValue{ .IntegerLiteral = 16 });

    try lex.replLine(".4");
    try expectError(error.InvalidCharacter, ureal(2, &lex));
    try lex.replLine(".4");
    try expectError(error.InvalidCharacter, ureal(2, &lex));
    try lex.replLine(".4");
    try expectEqual(ureal(10, &lex), TokenValue{ .RealLiteral = 0.4 });
    try lex.replLine(".4e3");
    try expectEqual(ureal(10, &lex), TokenValue{ .RealLiteral = 400 });
    try lex.replLine(".4");
    try expectError(error.InvalidCharacter, ureal(2, &lex));

    try lex.replLine("1234/5678");
    try expectEqual(ureal(10, &lex), TokenValue{ .RationalLiteral = [2]i64{ 1234, 5678 } });
}

fn uinteger(comptime n: i8, l: *Lexer) !usize {
    var count: usize = 0;
    var first: []const u8 = l.peek(1);
    if (first.len != 1 or !digitN(n, first[0])) {
        return 0;
    }
    try l.forward(1);
    count += 1;
    first = l.peek(1);
    while (first.len == 1 and digitN(n, first[0])) {
        try l.forward(1);
        count += 1;
        first = l.peek(1);
    }
    return count;
}

test "lex uinteger" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("1101");
    try expectEqual(uinteger(2, &lex), 4);
    try lex.replLine("1101");
    try expectEqual(uinteger(8, &lex), 4);
    try lex.replLine("1101");
    try expectEqual(uinteger(10, &lex), 4);
    try lex.replLine("1101");
    try expectEqual(uinteger(16, &lex), 4);

    try lex.replLine("60431");
    try expectEqual(uinteger(2, &lex), 0);
    try lex.replLine("60431");
    try expectEqual(uinteger(8, &lex), 5);
    try lex.replLine("60431");
    try expectEqual(uinteger(10, &lex), 5);
    try lex.replLine("60431");
    try expectEqual(uinteger(16, &lex), 5);

    try lex.replLine("997321");
    try expectEqual(uinteger(2, &lex), 0);
    try lex.replLine("997321");
    try expectEqual(uinteger(8, &lex), 0);
    try lex.replLine("997321");
    try expectEqual(uinteger(10, &lex), 6);
    try lex.replLine("997321");
    try expectEqual(uinteger(16, &lex), 6);

    try lex.replLine("aB29fC03");
    try expectEqual(uinteger(2, &lex), 0);
    try lex.replLine("aB29fC03");
    try expectEqual(uinteger(8, &lex), 0);
    try lex.replLine("aB29fC03");
    try expectEqual(uinteger(10, &lex), 0);
    try lex.replLine("aB29fC03");
    try expectEqual(uinteger(16, &lex), 8);

    try lex.replLine("");
    try expectEqual(uinteger(2, &lex), 0);
    try lex.replLine("");
    try expectEqual(uinteger(8, &lex), 0);
    try lex.replLine("");
    try expectEqual(uinteger(10, &lex), 0);
    try lex.replLine("");
    try expectEqual(uinteger(16, &lex), 0);

    try lex.replLine("22.33");
    try expectEqual(uinteger(2, &lex), 0);
    try lex.replLine("22.33");
    try expectEqual(uinteger(8, &lex), 2);
    try lex.replLine("22.33");
    try expectEqual(uinteger(10, &lex), 2);
    try lex.replLine("22.33");
    try expectEqual(uinteger(16, &lex), 2);
}

fn prefix(comptime n: i8, l: *Lexer) !usize {
    const first2: []const u8 = l.peek(2);
    if (first2.len != 2) {
        return 0;
    }
    if (exactness(first2)) {
        var next2: []const u8 = l.peek(4);
        if (next2.len == 4 and radix(n, next2[2..4])) {
            try l.forward(4);
            return 4;
        }
        if (n == 10) {
            try l.forward(2);
            return 2;
        }
        return 0;
    } else if (radix(n, first2)) {
        try l.forward(2);
        const next2: []const u8 = l.peek(2);
        if (next2.len == 2 and exactness(next2)) {
            try l.forward(2);
            return 4;
        }
        return 2;
    }
    return 0;
}

test "lex prefix" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("#b#e");
    try expectEqual(prefix(2, &lex), 4);

    try lex.replLine("#i#B");
    try expectEqual(prefix(2, &lex), 4);

    try lex.replLine("");
    try expectEqual(prefix(2, &lex), 0);
    try lex.replLine("");
    try expectEqual(prefix(8, &lex), 0);
    try lex.replLine("");
    try expectEqual(prefix(10, &lex), 0);
    try lex.replLine("");
    try expectEqual(prefix(16, &lex), 0);

    try lex.replLine("#E");
    try expectEqual(prefix(2, &lex), 0);
    try lex.replLine("#E");
    try expectEqual(prefix(8, &lex), 0);
    try lex.replLine("#E");
    try expectEqual(prefix(10, &lex), 2);
    try lex.replLine("#E");
    try expectEqual(prefix(16, &lex), 0);

    try lex.replLine("1234");
    try expectEqual(prefix(2, &lex), 0);
    try lex.replLine("1234");
    try expectEqual(prefix(8, &lex), 0);
    try lex.replLine("1234");
    try expectEqual(prefix(10, &lex), 0);
    try lex.replLine("1234");
    try expectEqual(prefix(16, &lex), 0);
}

fn infnan(l: *Lexer) !usize {
    var possible: []const u8 = l.peek(6);
    if (possible.len != 6 or !sign(possible[0])) {
        return 0;
    }
    if (!std.mem.eql(u8, possible[1..4], "inf") and !std.mem.eql(u8, possible[1..4], "nan")) {
        return 0;
    }
    if (!std.mem.eql(u8, possible[4..6], ".0")) {
        return 0;
    }
    try l.forward(6);
    return 6;
}

test "lex infnan" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("+inf.0");
    try expectEqual(infnan(&lex), 6);

    try lex.replLine("-inf.0");
    try expectEqual(infnan(&lex), 6);

    try lex.replLine("+nan.0");
    try expectEqual(infnan(&lex), 6);

    try lex.replLine("-nan.0");
    try expectEqual(infnan(&lex), 6);

    try lex.replLine("nan.0");
    try expectEqual(infnan(&lex), 0);

    try lex.replLine("+20.0");
    try expectEqual(infnan(&lex), 0);

    try lex.replLine("inf");
    try expectEqual(infnan(&lex), 0);
}

fn suffix(l: *Lexer) !usize {
    var count: usize = 0;
    const first: []const u8 = l.peek(1);
    if (first.len == 1 and exponentMarker(first[0])) {
        try l.forward(1);
        count += 1;
        const suff_sign: []const u8 = l.peek(1);
        if (suff_sign.len == 1 and sign(suff_sign[0])) {
            try l.forward(1);
            count += 1;
        }
        var first_dig: []const u8 = l.peek(1);
        if (first_dig.len != 1 or !digit(first_dig[0])) {
            return LexError.ExpectedSuffix;
        }
        try l.forward(1);
        count += 1;
        first_dig = l.peek(1);
        while (first_dig.len == 1 and digit(first_dig[0])) {
            try l.forward(1);
            count += 1;
            first_dig = l.peek(1);
        }
    }
    return count;
}

test "lex suffix" {
    var lex = Lexer.initRepl(std.testing.allocator);

    try lex.replLine("e+10");
    try expectEqual(suffix(&lex), 4);

    try lex.replLine("E-8");
    try expectEqual(suffix(&lex), 3);

    try lex.replLine("");
    try expectEqual(suffix(&lex), 0);

    // Error comes later when lexer does not find delimeter
    // TODO: Is this ok? Or should it throw and error here?
    try lex.replLine("e+10.2");
    try expectEqual(suffix(&lex), 4);

    try lex.replLine("efg");
    try expectError(LexError.ExpectedSuffix, suffix(&lex));
}

fn exponentMarker(c: u8) bool {
    return c == 'e' or c == 'E';
}

test "lex exponentMarker" {
    try expect(exponentMarker('e'));
    try expect(exponentMarker('E'));
    try expect(!exponentMarker('1'));
    try expect(!exponentMarker('a'));
    try expect(!exponentMarker('b'));
    try expect(!exponentMarker('i'));
    try expect(!exponentMarker('I'));
    try expect(!exponentMarker('#'));
}

fn sign(c: u8) bool {
    return c == '+' or c == '-';
}

test "lex sign" {
    try expect(sign('+'));
    try expect(sign('-'));
    try expect(!sign('*'));
    try expect(!sign('/'));
    try expect(!sign('p'));
}

fn exactness(s: []const u8) bool {
    return s[0] == '#' and
        (s[1] == 'i' or s[1] == 'e' or
        s[1] == 'I' or s[1] == 'E');
}

test "lex exactness" {
    try expect(exactness("#e"));
    try expect(exactness("#E"));
    try expect(exactness("#i"));
    try expect(exactness("#I"));

    try expect(!exactness("#d"));
    try expect(!exactness("ee"));
    try expect(!exactness("II"));
}

fn radix(comptime n: i8, s: []const u8) bool {
    return s[0] == '#' and (s[1] == switch (n) {
        2 => 'b',
        8 => 'o',
        10 => 'd',
        16 => 'x',
        else => unreachable,
    } or s[1] == switch (n) {
        2 => 'B',
        8 => 'O',
        10 => 'D',
        16 => 'X',
        else => unreachable,
    });
}

test "lex radix" {
    try expect(radix(2, "#b"));
    try expect(radix(2, "#B"));
    try expect(!radix(2, "#o"));
    try expect(!radix(2, "#O"));
    try expect(!radix(2, "#d"));
    try expect(!radix(2, "#D"));
    try expect(!radix(2, "#x"));
    try expect(!radix(2, "#X"));
    try expect(!radix(2, "#a"));
    try expect(!radix(2, "#P"));
    try expect(!radix(2, "#i"));
    try expect(!radix(2, "#E"));

    try expect(!radix(8, "#b"));
    try expect(!radix(8, "#B"));
    try expect(radix(8, "#o"));
    try expect(radix(8, "#O"));
    try expect(!radix(8, "#d"));
    try expect(!radix(8, "#D"));
    try expect(!radix(8, "#x"));
    try expect(!radix(8, "#X"));
    try expect(!radix(8, "#a"));
    try expect(!radix(8, "#P"));
    try expect(!radix(8, "#i"));
    try expect(!radix(8, "#E"));

    try expect(!radix(10, "#b"));
    try expect(!radix(10, "#B"));
    try expect(!radix(10, "#o"));
    try expect(!radix(10, "#O"));
    try expect(radix(10, "#d"));
    try expect(radix(10, "#D"));
    try expect(!radix(10, "#x"));
    try expect(!radix(10, "#X"));
    try expect(!radix(10, "#a"));
    try expect(!radix(10, "#P"));
    try expect(!radix(10, "#i"));
    try expect(!radix(10, "#E"));

    try expect(!radix(16, "#b"));
    try expect(!radix(16, "#B"));
    try expect(!radix(16, "#o"));
    try expect(!radix(16, "#O"));
    try expect(!radix(16, "#d"));
    try expect(!radix(16, "#D"));
    try expect(radix(16, "#x"));
    try expect(radix(16, "#X"));
    try expect(!radix(16, "#a"));
    try expect(!radix(16, "#P"));
    try expect(!radix(16, "#i"));
    try expect(!radix(16, "#E"));

    try expect(!radix(2, "bb"));
    try expect(!radix(2, "bB"));
    try expect(!radix(2, "bD"));
}

fn digit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn digitN(comptime n: i8, c: u8) bool {
    return (c >= '0' and c <= switch (n) {
        2 => '1',
        8 => '7',
        10, 16 => '9',
        else => unreachable,
    }) or (n == 16 and ((c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')));
}

test "lex digit" {
    try expect(digitN(2, '0'));
    try expect(digitN(2, '1'));
    try expect(!digitN(2, '2'));
    try expect(!digitN(2, 'A'));
    try expect(!digitN(2, 0));
    try expect(!digitN(2, 1));

    try expect(digitN(8, '0'));
    try expect(digitN(8, '1'));
    try expect(digitN(8, '2'));
    try expect(digitN(8, '3'));
    try expect(digitN(8, '4'));
    try expect(digitN(8, '5'));
    try expect(digitN(8, '6'));
    try expect(digitN(8, '7'));
    try expect(!digitN(8, '8'));
    try expect(!digitN(8, '9'));
    try expect(!digitN(8, 'A'));
    try expect(!digitN(8, 0));
    try expect(!digitN(8, 1));

    try expect(digitN(10, '0'));
    try expect(digitN(10, '1'));
    try expect(digitN(10, '2'));
    try expect(digitN(10, '3'));
    try expect(digitN(10, '4'));
    try expect(digitN(10, '5'));
    try expect(digitN(10, '6'));
    try expect(digitN(10, '7'));
    try expect(digitN(10, '8'));
    try expect(digitN(10, '9'));
    try expect(!digitN(10, 'A'));
    try expect(!digitN(10, 0));
    try expect(!digitN(10, 1));
    try expect(digit('0'));
    try expect(digit('1'));
    try expect(digit('2'));
    try expect(digit('3'));
    try expect(digit('4'));
    try expect(digit('5'));
    try expect(digit('6'));
    try expect(digit('7'));
    try expect(digit('8'));
    try expect(digit('9'));
    try expect(!digit('A'));
    try expect(!digit(0));
    try expect(!digit(1));

    try expect(digitN(16, '0'));
    try expect(digitN(16, '1'));
    try expect(digitN(16, '2'));
    try expect(digitN(16, '3'));
    try expect(digitN(16, '4'));
    try expect(digitN(16, '5'));
    try expect(digitN(16, '6'));
    try expect(digitN(16, '7'));
    try expect(digitN(16, '8'));
    try expect(digitN(16, '9'));
    try expect(digitN(16, 'A'));
    try expect(digitN(16, 'B'));
    try expect(digitN(16, 'C'));
    try expect(digitN(16, 'D'));
    try expect(digitN(16, 'E'));
    try expect(digitN(16, 'F'));
    try expect(digitN(16, 'a'));
    try expect(digitN(16, 'b'));
    try expect(digitN(16, 'c'));
    try expect(digitN(16, 'd'));
    try expect(digitN(16, 'e'));
    try expect(digitN(16, 'f'));
    try expect(!digitN(16, 0));
    try expect(!digitN(16, 1));
}
