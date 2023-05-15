const std = @import("std");

pub const TokenTag = enum {
    BinaryIntLiteral,
    BinaryRatLiteral,
    BoolLiteral,
    CharLiteral,
    ComplexLiteral,
    HexIntLiteral,
    HexRatLiteral,
    IntegerLiteral,
    OctIntLiteral,
    OctRatLiteral,
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
    BinaryIntLiteral: i64,
    BinaryRatLiteral: [2]i64,
    BoolLiteral: bool,
    CharLiteral: u8,
    ComplexLiteral: [2]f64,
    HexIntLiteral: i64,
    HexRatLiteral: [2]i64,
    IntegerLiteral: i64,
    OctIntLiteral: i64,
    OctRatLiteral: [2]i64,
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
            TokenValue.BinaryIntLiteral => |v| self.BinaryIntLiteral = -1 * v,
            TokenValue.BinaryRatLiteral => |v| self.BinaryRatLiteral = [2]i64{ -1 * v[0], v[1] },
            TokenValue.OctIntLiteral => |v| self.OctIntLiteral = -1 * v,
            TokenValue.OctRatLiteral => |v| self.OctRatLiteral = [2]i64{ -1 * v[0], v[1] },
            TokenValue.HexIntLiteral => |v| self.HexIntLiteral = -1 * v,
            TokenValue.HexRatLiteral => |v| self.HexRatLiteral = [2]i64{ -1 * v[0], v[1] },
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
};

pub const Lexer = struct {
    filename: []const u8,
    allocator: std.mem.Allocator,
    contents: []const u8,
    contents_iter: std.unicode.Utf8Iterator,
    line: usize,
    column: usize,
    position: usize,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Lexer {
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const limit = std.math.maxInt(u32);
        var contents = try file.readToEndAlloc(allocator, limit);

        return Lexer{
            .filename = filename,
            .allocator = allocator,
            .contents = contents,
            .contents_iter = (try std.unicode.Utf8View.init(contents)).iterator(),
            .line = 1,
            .column = 1,
            .position = 0,
        };
    }

    pub fn initRepl(allocator: std.mem.Allocator) Lexer {
        return Lexer{
            .filename = "",
            .allocator = allocator,
            .contents = "",
            .contents_iter = std.unicode.Utf8View.initUnchecked("").iterator(),
            .line = 0,
            .column = 1,
            .position = 0,
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
        l.allocator.free(l.contents);
    }

    fn peek(l: *Lexer, n: usize) []const u8 {
        return l.contents_iter.peek(n);
    }

    fn forward(l: *Lexer, n: usize) !void {
        var count = n;
        while (count > 0) {
            var cp: u21 = l.contents_iter.nextCodepoint() orelse return LexError.RanOutOfCodepoints;
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
        var ret: []const u8 = l.peek(n);
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
        var start: usize = l.position - n;
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
                var firstTwo: []const u8 = l.peek(2);
                if (firstTwo.len == 1 or (firstTwo.len == 2 and
                    !(digit(firstTwo[1]) or dot_subsequent(firstTwo[1]))))
                {
                    try l.forward(1);
                    tok.value = TokenValue{ .Cons = {} };
                    tok.contents = first;
                    return tok;
                } else if (digit(firstTwo[1])) {
                    tok.value = try number(l);
                    tok.contents = try l.contents_back(l.position - tok.position);
                    return tok;
                }
                tok.value = try identifier(l);
                tok.contents = try l.contents_back(l.position - tok.position);
                return tok;
            },
            ',' => {
                var firstTwo: []const u8 = l.peek(2);
                if (firstTwo.len == 2 and firstTwo[1] == '@') {
                    try l.forward(2);
                    tok.value = TokenValue{ .CommaAt = {} };
                    tok.contents = firstTwo;
                    return tok;
                }
                try l.forward(1);
                tok.value = TokenValue{ .Comma = {} };
                tok.contents = first;
                return tok;
            },
            ';' => {
                tok.value = try comment(l, false);
                tok.contents = try l.contents_back(l.position - tok.position);
                return tok;
            },
            '#' => {
                var firstTwo: []const u8 = l.peek(2);
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
                        return tok;
                    },
                    '\\' => {
                        tok.value = try character(l);
                        tok.contents = try l.contents_back(l.position - tok.position);
                        return tok;
                    },
                    '|' => {
                        tok.value = try comment(l, true);
                        tok.contents = try l.contents_back(l.position - tok.position);
                        return tok;
                    },
                    'u' => {
                        var firstFour: []const u8 = l.peek(4);
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
                        return tok;
                    },
                    else => return LexError.InvalidToken,
                }
            },
            '"' => {
                tok.value = try string(l);
                tok.contents = try l.contents_back(l.position - tok.position);
                return tok;
            },
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                tok.value = try number(l);
                tok.contents = try l.contents_back(l.position - tok.position);
                return tok;
            },
            '+', '-' => {
                var firstTwo: []const u8 = l.peek(2);
                if (firstTwo.len == 2 and digit(firstTwo[1])) {
                    tok.value = try number(l);
                    tok.contents = try l.contents_back(l.position - tok.position);
                    return tok;
                }
                tok.value = identifier(l) catch try number(l);
                tok.contents = try l.contents_back(l.position - tok.position);
                return tok;
            },
            else => {
                tok.value = try identifier(l);
                tok.contents = try l.contents_back(l.position - tok.position);
                return tok;
            },
        }
        return LexError.InvalidToken;
    }
};

fn comment(l: *Lexer, nested: bool) !TokenValue {
    if (nested) {
        try l.forward(2);
        var ch = try l.next(1);
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
            state = if (ch[0] == '|') 1 else if (ch[0] == '#') -1 else 0;
        }
        return LexError.InvalidToken;
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

fn identifier(l: *Lexer) !TokenValue {
    var reg_ident: usize = try regular_identifier(l);
    if (reg_ident != 0) {
        var ident = try l.contents_back(reg_ident);
        return TokenValue{ .Identifier = ident };
    }
    var symbol_ident: usize = try symbol_identifier(l);
    if (symbol_ident != 0) {
        var ident = try l.contents_back(reg_ident);
        return TokenValue{ .Identifier = ident };
    }
    var peculiar_ident: usize = try peculiar_identifier(l);
    if (peculiar_ident == 0) {
        return LexError.NotIdentifier;
    }
    var ident = try l.contents_back(peculiar_ident);
    if (std.mem.eql(u8, ident, "+i") or std.mem.eql(u8, ident, "-i") or
        std.mem.eql(u8, ident, "+inf.0") or std.mem.eql(u8, ident, "-inf.0") or
        std.mem.eql(u8, ident, "+nan.0") or std.mem.eql(u8, ident, "-nan.0") or
        std.mem.eql(u8, ident, "+inf.0i") or std.mem.eql(u8, ident, "-inf.0i") or
        std.mem.eql(u8, ident, "+nan.0i") or std.mem.eql(u8, ident, "-nan.0i"))
    {
        return LexError.NotIdentifier;
    }
    return TokenValue{ .Identifier = ident };
}

fn peculiar_identifier(l: *Lexer) !usize {
    var init: []const u8 = l.peek(1);
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
        var next_c = l.peek(1);
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

fn dot_subsequent(c: u8) bool {
    return sign_subsequent(c) or c == '.';
}

fn sign_subsequent(c: u8) bool {
    return initial(c) or c == '+' or c == '-' or c == '@';
}

fn symbol_identifier(l: *Lexer) !usize {
    var vert: []const u8 = l.peek(1);
    if (vert.len != 1 or vert[0] != '|') {
        return 0;
    }
    try l.forward(1);
    var count: usize = 0;
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
                    var hexseq = l.peek(2);
                    if (hexseq.len != 2 or !digit16(hexseq[0]) or !digit16(hexseq[1])) {
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

fn regular_identifier(l: *Lexer) !usize {
    var start: []const u8 = l.peek(1);
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

fn subsequent(c: u8) bool {
    return initial(c) or digit(c) or specialSubsequent(c);
}

fn specialSubsequent(c: u8) bool {
    switch (c) {
        '+', '-', '.', '@' => return true,
        else => return false,
    }
}

fn initial(c: u8) bool {
    return std.ascii.isAlpha(c) or specialInitial(c);
}

fn specialInitial(c: u8) bool {
    switch (c) {
        '!', '$', '%', '&', '*', '/', ':', '<', '=', '>', '?', '@', '^', '_', '~' => return true,
        else => return false,
    }
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

fn character(l: *Lexer) !TokenValue {
    var hashslash: []const u8 = l.peek(2);
    if (hashslash.len != 2 or std.mem.eql(u8, hashslash, "#\\")) {
        return LexError.NotChar;
    }
    try l.forward(2);

    var nexttwo: []const u8 = l.peek(2);
    if (nexttwo.len == 0) {
        return LexError.NotChar;
    }
    if (nexttwo.len == 1 or (nexttwo.len == 2 and whitespace(nexttwo[1]))) {
        try l.forward(1);
        return TokenValue{ .CharLiteral = nexttwo[0] };
    }
    if (std.mem.eql(u8, nexttwo, "al")) {
        var alarm = l.peek(5);
        if (std.mem.eql(u8, alarm, "alarm")) {
            try l.forward(5);
            return TokenValue{ .CharLiteral = '\x07' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'a' };
    } else if (std.mem.eql(u8, nexttwo, "ba")) {
        var backspace = l.peek(9);
        if (std.mem.eql(u8, backspace, "backspace")) {
            try l.forward(9);
            return TokenValue{ .CharLiteral = '\x08' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'b' };
    } else if (std.mem.eql(u8, nexttwo, "de")) {
        var delete = l.peek(6);
        if (std.mem.eql(u8, delete, "delete")) {
            try l.forward(6);
            return TokenValue{ .CharLiteral = '\x7F' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'd' };
    } else if (std.mem.eql(u8, nexttwo, "es")) {
        var escape = l.peek(6);
        if (std.mem.eql(u8, escape, "escape")) {
            try l.forward(6);
            return TokenValue{ .CharLiteral = '\x1b' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'e' };
    } else if (std.mem.eql(u8, nexttwo, "ne")) {
        var newline = l.peek(7);
        if (std.mem.eql(u8, newline, "newline")) {
            try l.forward(7);
            return TokenValue{ .CharLiteral = '\n' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'n' };
    } else if (std.mem.eql(u8, nexttwo, "nu")) {
        var null_ = l.peek(4);
        if (std.mem.eql(u8, null_, "null")) {
            try l.forward(4);
            return TokenValue{ .CharLiteral = 0 };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'n' };
    } else if (std.mem.eql(u8, nexttwo, "re")) {
        var return_ = l.peek(6);
        if (std.mem.eql(u8, return_, "return")) {
            try l.forward(6);
            return TokenValue{ .CharLiteral = '\r' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 'r' };
    } else if (std.mem.eql(u8, nexttwo, "sp")) {
        var space = l.peek(5);
        if (std.mem.eql(u8, space, "space")) {
            try l.forward(5);
            return TokenValue{ .CharLiteral = ' ' };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = 's' };
    } else if (std.mem.eql(u8, nexttwo, "ta")) {
        var tab = l.peek(3);
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
            var ch: u8 = try std.fmt.parseInt(u8, hexescape[1..3], 16);
            return TokenValue{ .CharLiteral = ch };
        }
        try l.forward(1);
        return TokenValue{ .CharLiteral = nexttwo[0] };
    }
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
        var ch: u8 = try string_element(l);
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

    quote = l.peek(1);
    if (quote.len != 1 or quote[0] != '"') {
        return LexError.ExpectedQuote;
    }
    try l.forward(1);

    return TokenValue{ .StringLiteral = str };
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
            var he: []const u8 = l.peek(2);
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

fn whitespace(c: u8) bool {
    switch (c) {
        ' ', '\t', '\n', '\r' => return true,
        else => return false,
    }
}

fn number(l: *Lexer) !TokenValue {
    // TODO: Reinterpret literals based on exactness prefix
    var pre: usize = try prefix2(l);
    if (pre != 0) {
        return complex2(l);
    }
    pre = try prefix8(l);
    if (pre != 0) {
        return complex8(l);
    }
    pre = try prefix16(l);
    if (pre != 0) {
        return complex16(l);
    }
    // Ignore prefix10 for now (See TODO above)
    _ = try prefix10(l);
    return complex10(l);
}

fn complex2(l: *Lexer) !TokenValue {
    var imag_only = l.peek(2);
    if (imag_only.len == 2) {
        if ((imag_only[0] == '+' or imag_only[0] == '-') and imag_only[1] == 'i') {
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
    var tok_real: TokenValue = try real2(l);
    var next_c: []const u8 = l.peek(1);
    if (next_c.len != 1) {
        return tok_real;
    }
    switch (next_c[0]) {
        '@' => {
            try l.forward(1);
            var tok_exp: TokenValue = try real2(l);
            var coeff: f64 = switch (tok_real) {
                TokenTag.BinaryIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.BinaryRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            var angle: f64 = switch (tok_exp) {
                TokenTag.BinaryIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.BinaryRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                coeff * std.math.cos(angle),
                coeff * std.math.sin(angle),
            } };
        },
        '+', '-' => {
            var tok_imag: TokenValue = try real2(l);
            var i_: []const u8 = l.peek(1);
            if (i_.len != 1 or i_[0] != 'i') {
                return LexError.ExpectedI;
            }
            try l.forward(1);
            var real: f64 = switch (tok_real) {
                TokenTag.BinaryIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.BinaryRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            var imag: f64 = switch (tok_imag) {
                TokenTag.BinaryIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.BinaryRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                real, imag,
            } };
        },
        'i' => {
            try l.forward(1);
            var imag: f64 = switch (tok_real) {
                TokenTag.BinaryIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.BinaryRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
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

fn complex8(l: *Lexer) !TokenValue {
    var imag_only = l.peek(2);
    if (imag_only.len == 2) {
        if ((imag_only[0] == '+' or imag_only[0] == '-') and imag_only[1] == 'i') {
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
    var tok_real: TokenValue = try real8(l);
    var next_c: []const u8 = l.peek(1);
    if (next_c.len != 1) {
        return tok_real;
    }
    switch (next_c[0]) {
        '@' => {
            try l.forward(1);
            var tok_exp: TokenValue = try real8(l);
            var coeff: f64 = switch (tok_real) {
                TokenTag.OctIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.OctRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            var angle: f64 = switch (tok_exp) {
                TokenTag.OctIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.OctRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                coeff * std.math.cos(angle),
                coeff * std.math.sin(angle),
            } };
        },
        '+', '-' => {
            var tok_imag: TokenValue = try real8(l);
            var i_: []const u8 = l.peek(1);
            if (i_.len != 1 or i_[0] != 'i') {
                return LexError.ExpectedI;
            }
            try l.forward(1);
            var real: f64 = switch (tok_real) {
                TokenTag.OctIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.OctRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            var imag: f64 = switch (tok_imag) {
                TokenTag.OctIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.OctRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                real, imag,
            } };
        },
        'i' => {
            try l.forward(1);
            var imag: f64 = switch (tok_real) {
                TokenTag.OctIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.OctRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
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

fn complex10(l: *Lexer) !TokenValue {
    var imag_only = l.peek(2);
    if (imag_only.len == 2) {
        if ((imag_only[0] == '+' or imag_only[0] == '-') and imag_only[1] == 'i') {
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
    var tok_real: TokenValue = try real10(l);
    var next_c: []const u8 = l.peek(1);
    if (next_c.len != 1) {
        return tok_real;
    }
    switch (next_c[0]) {
        '@' => {
            try l.forward(1);
            var tok_exp: TokenValue = try real10(l);
            var coeff: f64 = switch (tok_real) {
                TokenTag.IntegerLiteral => |val| @intToFloat(f64, val),
                TokenTag.RationalLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            var angle: f64 = switch (tok_exp) {
                TokenTag.IntegerLiteral => |val| @intToFloat(f64, val),
                TokenTag.RationalLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                coeff * std.math.cos(angle),
                coeff * std.math.sin(angle),
            } };
        },
        '+', '-' => {
            var tok_imag: TokenValue = try real10(l);
            var i_: []const u8 = l.peek(1);
            if (i_.len != 1 or i_[0] != 'i') {
                return LexError.ExpectedI;
            }
            try l.forward(1);
            var real: f64 = switch (tok_real) {
                TokenTag.IntegerLiteral => |val| @intToFloat(f64, val),
                TokenTag.RationalLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            var imag: f64 = switch (tok_imag) {
                TokenTag.IntegerLiteral => |val| @intToFloat(f64, val),
                TokenTag.RationalLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                real, imag,
            } };
        },
        'i' => {
            try l.forward(1);
            var imag: f64 = switch (tok_real) {
                TokenTag.IntegerLiteral => |val| @intToFloat(f64, val),
                TokenTag.RationalLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
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

fn complex16(l: *Lexer) !TokenValue {
    var imag_only = l.peek(2);
    if (imag_only.len == 2) {
        if ((imag_only[0] == '+' or imag_only[0] == '-') and imag_only[1] == 'i') {
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
    var tok_real: TokenValue = try real16(l);
    var next_c: []const u8 = l.peek(1);
    if (next_c.len != 1) {
        return tok_real;
    }
    switch (next_c[0]) {
        '@' => {
            try l.forward(1);
            var tok_exp: TokenValue = try real16(l);
            var coeff: f64 = switch (tok_real) {
                TokenTag.HexIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.HexRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            var angle: f64 = switch (tok_exp) {
                TokenTag.HexIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.HexRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                coeff * std.math.cos(angle),
                coeff * std.math.sin(angle),
            } };
        },
        '+', '-' => {
            var tok_imag: TokenValue = try real16(l);
            var i_: []const u8 = l.peek(1);
            if (i_.len != 1 or i_[0] != 'i') {
                return LexError.ExpectedI;
            }
            try l.forward(1);
            var real: f64 = switch (tok_real) {
                TokenTag.HexIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.HexRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            var imag: f64 = switch (tok_imag) {
                TokenTag.HexIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.HexRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
                TokenTag.RealLiteral => |val| val,
                else => unreachable,
            };
            return TokenValue{ .ComplexLiteral = [2]f64{
                real, imag,
            } };
        },
        'i' => {
            try l.forward(1);
            var imag: f64 = switch (tok_real) {
                TokenTag.HexIntLiteral => |val| @intToFloat(f64, val),
                TokenTag.HexRatLiteral => |vals| @intToFloat(f64, vals[0]) / @intToFloat(f64, vals[1]),
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

fn real2(l: *Lexer) !TokenValue {
    var infnan_: usize = try infnan(l);
    if (infnan_ != 0) {
        var infnan_str = try l.contents_back(infnan_);
        var minus: bool = infnan_str[0] == '-';
        var inf: bool = infnan_str[1] == 'i';
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
    var sign_: []const u8 = l.peek(1);
    if (sign_.len == 0) {
        return LexError.ExpectedCharacter;
    }
    var minus: bool = sign_[0] == '-';
    if (sign(sign_[0])) {
        try l.forward(1);
    }
    var ureal_tok = try ureal2(l);
    if (minus) {
        ureal_tok.negate();
    }
    return ureal_tok;
}

fn real8(l: *Lexer) !TokenValue {
    var infnan_: usize = try infnan(l);
    if (infnan_ != 0) {
        var infnan_str = try l.contents_back(infnan_);
        var minus: bool = infnan_str[0] == '-';
        var inf: bool = infnan_str[1] == 'i';
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
    var sign_: []const u8 = l.peek(1);
    if (sign_.len == 0) {
        return LexError.ExpectedCharacter;
    }
    var minus: bool = sign_[0] == '-';
    if (sign(sign_[0])) {
        try l.forward(1);
    }
    var ureal_tok = try ureal8(l);
    if (minus) {
        ureal_tok.negate();
    }
    return ureal_tok;
}

fn real10(l: *Lexer) !TokenValue {
    var infnan_: usize = try infnan(l);
    if (infnan_ != 0) {
        var infnan_str = try l.contents_back(infnan_);
        var minus: bool = infnan_str[0] == '-';
        var inf: bool = infnan_str[1] == 'i';
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
    var sign_: []const u8 = l.peek(1);
    if (sign_.len == 0) {
        return LexError.ExpectedCharacter;
    }
    var minus: bool = sign_[0] == '-';
    if (sign(sign_[0])) {
        try l.forward(1);
    }
    var ureal_tok = try ureal10(l);
    if (minus) {
        ureal_tok.negate();
    }
    return ureal_tok;
}

fn real16(l: *Lexer) !TokenValue {
    var infnan_: usize = try infnan(l);
    if (infnan_ != 0) {
        var infnan_str = try l.contents_back(infnan_);
        var minus: bool = infnan_str[0] == '-';
        var inf: bool = infnan_str[1] == 'i';
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
    var sign_: []const u8 = l.peek(1);
    if (sign_.len == 0) {
        return LexError.ExpectedCharacter;
    }
    var minus: bool = sign_[0] == '-';
    if (sign(sign_[0])) {
        try l.forward(1);
    }
    var ureal_tok = try ureal16(l);
    if (minus) {
        ureal_tok.negate();
    }
    return ureal_tok;
}

fn ureal2(l: *Lexer) !TokenValue {
    var int_part: usize = try uinteger2(l);
    var slash: []const u8 = l.peek(1);
    var found_slash: bool = false;
    var den_count: usize = 0;
    if (slash.len == 1 and slash[0] == '/') {
        found_slash = true;
        try l.forward(1);
        den_count += 1;
        den_count += try uinteger2(l);
        if (den_count == 1) {
            return LexError.ExpectedNumeralAfterSlash;
        }
    }
    var lit_val: []const u8 = try l.contents_back(int_part + den_count);
    if (found_slash) {
        return TokenValue{ .BinaryRatLiteral = [2]i64{
            try std.fmt.parseInt(i64, lit_val[0..int_part], 2),
            try std.fmt.parseInt(i64, lit_val[(int_part + 1)..lit_val.len], 2),
        } };
    }
    return TokenValue{ .BinaryIntLiteral = try std.fmt.parseInt(i64, lit_val, 2) };
}

fn ureal8(l: *Lexer) !TokenValue {
    var int_part: usize = try uinteger8(l);
    var slash: []const u8 = l.peek(1);
    var found_slash: bool = false;
    var den_count: usize = 0;
    if (slash.len == 1 and slash[0] == '/') {
        found_slash = true;
        try l.forward(1);
        den_count += 1;
        den_count += try uinteger8(l);
        if (den_count == 1) {
            return LexError.ExpectedNumeralAfterSlash;
        }
    }
    var lit_val: []const u8 = try l.contents_back(int_part + den_count);
    if (found_slash) {
        return TokenValue{ .OctRatLiteral = [2]i64{
            try std.fmt.parseInt(i64, lit_val[0..int_part], 8),
            try std.fmt.parseInt(i64, lit_val[(int_part + 1)..lit_val.len], 8),
        } };
    }
    return TokenValue{ .OctIntLiteral = try std.fmt.parseInt(i64, lit_val, 8) };
}

fn ureal10(l: *Lexer) !TokenValue {
    var int_part: usize = try uinteger10(l);
    var slashdec: []const u8 = l.peek(1);
    var den_count: usize = 0;
    var slash: bool = false;
    if (slashdec.len == 1 and slashdec[0] == '/') {
        try l.forward(1);
        den_count += 1;
        slash = true;
        den_count += try uinteger10(l);
        if (den_count == 1) {
            return LexError.ExpectedNumeralAfterSlash;
        }
    } else if (slashdec.len == 1 and slashdec[0] == '.') {
        den_count += 1;
        try l.forward(1);
        if (int_part == 0) {
            den_count += try uinteger10(l);
            if (den_count == 1) {
                return LexError.ExpectedNumeralAfterDecPt;
            }
        } else {
            var dig: []const u8 = l.peek(1);
            while (dig.len == 1 and digit10(dig[0])) {
                try l.forward(1);
                den_count += 1;
                dig = l.peek(1);
            }
        }
    }
    var suffix_part: usize = 0;
    if (!slash) {
        suffix_part += try suffix(l);
    }
    var lit_val: []const u8 = try l.contents_back(int_part + den_count + suffix_part);
    if (slash) {
        return TokenValue{ .RationalLiteral = [2]i64{
            try std.fmt.parseInt(i64, lit_val[0..int_part], 10),
            try std.fmt.parseInt(i64, lit_val[(int_part + 1)..lit_val.len], 10),
        } };
    }
    if (den_count != 0 or suffix_part != 0) {
        return TokenValue{ .RealLiteral = try std.fmt.parseFloat(f64, lit_val) };
    }
    return TokenValue{ .IntegerLiteral = try std.fmt.parseInt(i64, lit_val, 10) };
}

fn ureal16(l: *Lexer) !TokenValue {
    var int_part: usize = try uinteger16(l);
    var slash: []const u8 = l.peek(1);
    var found_slash: bool = false;
    var den_count: usize = 0;
    if (slash.len == 1 and slash[0] == '/') {
        found_slash = true;
        try l.forward(1);
        den_count += 1;
        den_count += try uinteger16(l);
        if (den_count == 1) {
            return LexError.ExpectedNumeralAfterSlash;
        }
    }
    var lit_val: []const u8 = try l.contents_back(int_part + den_count);
    if (found_slash) {
        return TokenValue{ .HexRatLiteral = [2]i64{
            try std.fmt.parseInt(i64, lit_val[0..int_part], 16),
            try std.fmt.parseInt(i64, lit_val[(int_part + 1)..lit_val.len], 16),
        } };
    }
    return TokenValue{ .HexIntLiteral = try std.fmt.parseInt(i64, lit_val, 16) };
}

fn uinteger2(l: *Lexer) !usize {
    var count: usize = 0;
    var first: []const u8 = l.peek(1);
    if (first.len != 1 or !digit2(first[0])) {
        return 0;
    }
    try l.forward(1);
    count += 1;
    first = l.peek(1);
    while (first.len == 1 and digit2(first[0])) {
        try l.forward(1);
        count += 1;
        first = l.peek(1);
    }
    return count;
}

fn uinteger8(l: *Lexer) !usize {
    var count: usize = 0;
    var first: []const u8 = l.peek(1);
    if (first.len != 1 or !digit8(first[0])) {
        return 0;
    }
    try l.forward(1);
    count += 1;
    first = l.peek(1);
    while (first.len == 1 and digit8(first[0])) {
        try l.forward(1);
        count += 1;
        first = l.peek(1);
    }
    return count;
}

fn uinteger10(l: *Lexer) !usize {
    var count: usize = 0;
    var first: []const u8 = l.peek(1);
    if (first.len != 1 or !digit10(first[0])) {
        return 0;
    }
    try l.forward(1);
    count += 1;
    first = l.peek(1);
    while (first.len == 1 and digit10(first[0])) {
        try l.forward(1);
        count += 1;
        first = l.peek(1);
    }
    return count;
}

fn uinteger16(l: *Lexer) !usize {
    var count: usize = 0;
    var first: []const u8 = l.peek(1);
    if (first.len != 1 or !digit16(first[0])) {
        return 0;
    }
    try l.forward(1);
    count += 1;
    first = l.peek(1);
    while (first.len == 1 and digit16(first[0])) {
        try l.forward(1);
        count += 1;
        first = l.peek(1);
    }
    return count;
}

fn prefix2(l: *Lexer) !usize {
    var first2: []const u8 = l.peek(2);
    if (first2.len != 2) {
        return 0;
    }
    if (exactness(first2)) {
        var next2: []const u8 = l.peek(4);
        if (next2.len == 4 and radix2(next2[2..4])) {
            try l.forward(4);
            return 4;
        }
        return 0;
    } else if (radix2(first2)) {
        try l.forward(2);
        var next2: []const u8 = l.peek(2);
        if (next2.len == 2 and exactness(next2)) {
            try l.forward(2);
            return 4;
        }
        return 2;
    }
    return 0;
}

fn prefix8(l: *Lexer) !usize {
    var first2: []const u8 = l.peek(2);
    if (first2.len != 2) {
        return 0;
    }
    if (exactness(first2)) {
        var next2: []const u8 = l.peek(4);
        if (next2.len == 4 and radix8(next2[2..4])) {
            try l.forward(4);
            return 4;
        }
        return 0;
    } else if (radix8(first2)) {
        try l.forward(2);
        var next2: []const u8 = l.peek(2);
        if (next2.len == 2 and exactness(next2)) {
            try l.forward(2);
            return 4;
        }
        return 2;
    }
    return 0;
}

fn prefix10(l: *Lexer) !usize {
    var first2: []const u8 = l.peek(2);
    if (first2.len != 2) {
        return 0;
    }
    if (exactness(first2)) {
        var next2: []const u8 = l.peek(4);
        if (next2.len == 4 and radix10(next2[2..4])) {
            try l.forward(4);
            return 4;
        }
        try l.forward(2);
        return 2;
    } else if (radix10(first2)) {
        try l.forward(2);
        var next2: []const u8 = l.peek(2);
        if (next2.len == 2 and exactness(next2)) {
            try l.forward(2);
            return 4;
        }
        return 2;
    }
    return 0;
}

fn prefix16(l: *Lexer) !usize {
    var first2: []const u8 = l.peek(2);
    if (first2.len != 2) {
        return 0;
    }
    if (exactness(first2)) {
        var next2: []const u8 = l.peek(4);
        if (next2.len == 4 and radix16(next2[2..4])) {
            try l.forward(4);
            return 4;
        }
        return 0;
    } else if (radix16(first2)) {
        try l.forward(2);
        var next2: []const u8 = l.peek(2);
        if (next2.len == 2 and exactness(next2)) {
            try l.forward(2);
            return 4;
        }
        return 2;
    }
    return 0;
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

fn suffix(l: *Lexer) !usize {
    var count: usize = 0;
    var first: []const u8 = l.peek(1);
    if (first.len == 1 and exponent_marker(first[0])) {
        try l.forward(1);
        count += 1;
        var suff_sign: []const u8 = l.peek(1);
        if (suff_sign.len == 1 and sign(suff_sign[0])) {
            try l.forward(1);
            count += 1;
        }
        var first_dig: []const u8 = l.peek(1);
        if (first_dig.len != 1 or !digit10(first_dig[0])) {
            return LexError.ExpectedSuffix;
        }
        try l.forward(1);
        count += 1;
        first_dig = l.peek(1);
        while (first_dig.len == 1 and digit10(first_dig[0])) {
            try l.forward(1);
            count += 1;
            first_dig = l.peek(1);
        }
    }
    return count;
}

fn exponent_marker(c: u8) bool {
    return c == 'e';
}

fn sign(c: u8) bool {
    return c == '+' or c == '-';
}

fn exactness(s: []const u8) bool {
    return s[0] == '#' and (s[1] == 'i' or s[1] == 'e');
}

fn radix2(s: []const u8) bool {
    return s[0] == '#' and s[1] == 'b';
}

fn radix8(s: []const u8) bool {
    return s[0] == '#' and s[1] == 'o';
}

fn radix10(s: []const u8) bool {
    return s[0] == '#' and s[1] == 'd';
}

fn radix16(s: []const u8) bool {
    return s[0] == '#' and s[1] == 'x';
}

fn digit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn digit2(c: u8) bool {
    return c == '0' or c == '1';
}

fn digit8(c: u8) bool {
    return c >= '0' and c <= '7';
}

fn digit10(c: u8) bool {
    return digit(c);
}

fn digit16(c: u8) bool {
    return digit10(c) or (c >= 'a' and c <= 'f');
}
