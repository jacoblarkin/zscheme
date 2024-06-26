const std = @import("std");
const lex = @import("lexer.zig");

const QuoteTag = enum {
    NoQuote,
    Quote,
    QuasiQuote,
};

pub const ExpressionTag = enum {
    Identifier,
    BoolLiteral,
    CharLiteral,
    IntegerLiteral,
    RationalLiteral,
    RealLiteral,
    ComplexLiteral,
    StringLiteral,
    Vector,
    ByteVector,
    QuotedExpression,
    QuasiQuotedExpression,
    Cons,
    Nil,
    UnquotedElement,
};

pub const Expression = union(ExpressionTag) {
    Identifier: []const u8,
    BoolLiteral: bool,
    CharLiteral: u8,
    IntegerLiteral: i64,
    RationalLiteral: [2]i64,
    RealLiteral: f64,
    ComplexLiteral: [2]f64,
    StringLiteral: []const u8,
    Vector: std.ArrayList(*Expression),
    ByteVector: std.ArrayList(u8),
    QuotedExpression: *Expression,
    QuasiQuotedExpression: *Expression,
    Cons: ConsCell,
    Nil: void,
    UnquotedElement: *Expression,

    pub fn deinit(expr: *Expression, allocator: std.mem.Allocator) void {
        switch (expr.*) {
            ExpressionTag.Vector => |v| {
                for (v.items) |ex| {
                    ex.deinit(allocator);
                }
                v.deinit();
            },
            ExpressionTag.ByteVector => |bv| bv.deinit(),
            ExpressionTag.QuotedExpression => |qe| allocator.destroy(qe),
            ExpressionTag.QuasiQuotedExpression => |qqe| allocator.destroy(qqe),
            ExpressionTag.UnquotedElement => |uqe| allocator.destroy(uqe),
            ExpressionTag.Cons => |c| {
                c.Car.deinit(allocator);
                c.Cdr.deinit(allocator);
            },
            else => {},
        }
        allocator.destroy(expr);
    }
};

pub const ConsCell = struct {
    Car: *Expression,
    Cdr: *Expression,
};

pub const Parser = struct {
    lexer: lex.Lexer,
    allocator: std.mem.Allocator,
    hadError: bool,
    peekedToken: ?lex.Token = null,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Parser {
        const lexer = if (filename.len > 0)
            try lex.Lexer.init(allocator, filename)
        else
            lex.Lexer.initRepl(allocator);
        return Parser{ .lexer = lexer, .allocator = allocator, .hadError = false };
    }

    pub fn deinit(parser: *Parser) void {
        parser.lexer.deinit();
    }

    fn peek(parser: *Parser) lex.Token {
        if (parser.peekedToken) |tok| {
            return tok;
        }
        const tok: lex.Token = while (true) {
            const ret = parser.lexer.getNextToken() catch |err| {
                parser.hadError = true;
                std.debug.print("{s}\n", .{lex.Lexer.errorMsg(err)});
                continue;
            };
            //std.debug.print("{}", .{ret});
            break ret;
        } else lex.Token.default();
        parser.peekedToken = tok;
        return tok;
    }

    fn next(parser: *Parser) lex.Token {
        if (parser.peekedToken) |tok| {
            parser.peekedToken = null;
            return tok;
        }
        while (true) {
            const ret = parser.lexer.getNextToken() catch |err| {
                parser.hadError = true;
                std.debug.print("{s}\n", .{lex.Lexer.errorMsg(err)});
                continue;
            };
            return ret;
        }
    }

    pub fn parse(parser: *Parser) ?*Expression {
        return parseExpr(parser, QuoteTag.NoQuote);
    }

    pub fn parseRepl(parser: *Parser, contents: []const u8) ?*Expression {
        parser.lexer.replLine(contents) catch {
            return null;
        };
        return parseExpr(parser, QuoteTag.NoQuote);
    }

    fn printError(parser: *Parser, msg: []const u8, tok: lex.Token) void {
        parser.hadError = true;
        std.debug.print("Parsing error ({s}:{d}:{d}) {s}", .{ parser.lexer.filename, tok.line, tok.column, msg });
    }
};

fn parseExpr(parser: *Parser, quoted: QuoteTag) ?*Expression {
    var expr: *Expression = parser.allocator.create(Expression) catch {
        parser.hadError = true;
        return null;
    };
    const tok: lex.Token = parser.next();
    switch (tok.value) {
        lex.TokenTag.BoolLiteral => |b| expr.* = Expression{ .BoolLiteral = b },
        lex.TokenTag.CharLiteral => |c| expr.* = Expression{ .CharLiteral = c },
        lex.TokenTag.StringLiteral => |s| expr.* = Expression{ .StringLiteral = s },
        lex.TokenTag.IntegerLiteral => |num| expr.* = Expression{ .IntegerLiteral = num },
        lex.TokenTag.RationalLiteral => |num| expr.* = Expression{ .RationalLiteral = [2]i64{ num[0], num[1] } },
        lex.TokenTag.RealLiteral => |num| expr.* = Expression{ .RealLiteral = num },
        lex.TokenTag.ComplexLiteral => |num| expr.* = Expression{ .ComplexLiteral = [2]f64{ num[0], num[1] } },
        lex.TokenTag.Identifier => |ident| {
            expr.* = Expression{ .Identifier = ident };
        },
        lex.TokenTag.Comma, lex.TokenTag.CommaAt => {
            if (quoted != QuoteTag.QuasiQuote) {
                parser.printError("Found unquote expression not in a quasi-quote", tok);
                parser.allocator.destroy(expr);
                return null;
            }
            expr.* = Expression{ .UnquotedElement = parseExpr(parser, QuoteTag.NoQuote) orelse {
                parser.allocator.destroy(expr);
                return null;
            } };
        },
        lex.TokenTag.Quote => expr.* = Expression{ .QuotedExpression = parseExpr(parser, QuoteTag.Quote) orelse {
            parser.allocator.destroy(expr);
            return null;
        } },
        lex.TokenTag.QuasiQuote => expr.* = Expression{ .QuasiQuotedExpression = parseExpr(parser, QuoteTag.QuasiQuote) orelse {
            parser.hadError = true;
            parser.allocator.destroy(expr);
            return null;
        } },
        lex.TokenTag.LParen => {
            if (parser.peek().value == lex.TokenTag.RParen) {
                if (quoted != QuoteTag.NoQuote) {
                    expr.* = Expression{ .Nil = {} };
                } else {
                    parser.allocator.destroy(expr);
                    parser.printError("Empty list without quote.", parser.peek());
                    return null;
                }
            } else {
                const car: *Expression = parseExpr(parser, quoted) orelse {
                    parser.allocator.destroy(expr);
                    return null;
                };
                parser.allocator.destroy(expr);
                expr = parseList(parser, car, quoted) catch {
                    return null;
                };
            }
        },
        lex.TokenTag.VecBegin => {
            var vec: std.ArrayList(*Expression) = std.ArrayList(*Expression).init(parser.allocator);
            while (parser.peek().value != lex.TokenTag.RParen) {
                const val: *Expression = parseExpr(parser, quoted) orelse {
                    vec.deinit();
                    parser.allocator.destroy(expr);
                    return null;
                };
                vec.append(val) catch {
                    vec.deinit();
                    parser.allocator.destroy(expr);
                    parser.allocator.destroy(val);
                    parser.hadError = true;
                    return null;
                };
            }
            _ = parser.next();
            expr.* = Expression{ .Vector = vec };
        },
        lex.TokenTag.ByteVectorBegin => {
            var bv: std.ArrayList(u8) = std.ArrayList(u8).init(parser.allocator);
            while (parser.peek().value != lex.TokenTag.RParen) {
                const val: *Expression = parseExpr(parser, quoted) orelse {
                    bv.deinit();
                    parser.allocator.destroy(expr);
                    return null;
                };
                switch (val.*) {
                    ExpressionTag.IntegerLiteral => |num| {
                        parser.allocator.destroy(val);
                        if (num < 0 or num > 255) {
                            bv.deinit();
                            parser.allocator.destroy(expr);
                            // TODO: wrong token being passed here
                            // should pass non-integer token, not '#u8(' token
                            parser.printError("Invalid element in byte vector", tok);
                            return null;
                        }
                        bv.append(@intCast(num)) catch {
                            bv.deinit();
                            parser.allocator.destroy(expr);
                            parser.hadError = true;
                            return null;
                        };
                    },
                    else => {
                        bv.deinit();
                        parser.allocator.destroy(expr);
                        // TODO: wrong token being passed here
                        // should pass non-integer token, not '#u8(' token
                        parser.printError("Non-integer element in byte vector", tok);
                        parser.allocator.destroy(val);
                        return null;
                    },
                }
            }
            _ = parser.next();
            expr.* = Expression{ .ByteVector = bv };
        },
        lex.TokenTag.RParen => {
            parser.allocator.destroy(expr);
            parser.printError("Found ')' in unexpected location", tok);
            return null;
        },
        lex.TokenTag.Cons => {
            parser.allocator.destroy(expr);
            parser.printError("Found '.' in unexpected location", tok);
            return null;
        },
        lex.TokenTag.Comment => {
            parser.allocator.destroy(expr);
            return parseExpr(parser, quoted);
        },
        lex.TokenTag.EndOfFile => {
            parser.allocator.destroy(expr);
            return null;
        },
    }

    return expr;
}

fn parseList(parser: *Parser, car: *Expression, quoted: QuoteTag) std.mem.Allocator.Error!*Expression {
    const cc = try parser.allocator.create(Expression);
    errdefer parser.allocator.destroy(cc);
    if (parser.peek().value == lex.TokenTag.RParen) {
        _ = parser.next();
        const nilExpr: *Expression = try parser.allocator.create(Expression);
        nilExpr.* = Expression{ .Nil = {} };
        cc.* = Expression{ .Cons = ConsCell{ .Car = car, .Cdr = nilExpr } };
        return cc;
    }
    if (parser.peek().value == lex.TokenTag.Cons) {
        // TODO: What to do with '.'?
        const cons = parser.next();
        const cdr = parseExpr(parser, quoted) orelse {
            parser.allocator.destroy(cc);
            parser.printError("Expected cdr after cons.", cons);
            return car;
        };
        while (parser.peek().value == lex.TokenTag.Comment) {
            _ = parser.next();
        }
        if (parser.peek().value != lex.TokenTag.RParen) {
            parser.printError("Ill formed list. Expected ')' after cdr", parser.peek());
            while (parser.peek().value != lex.TokenTag.RParen) {
                _ = parser.next();
            }
            _ = parser.next();
        }
        cc.* = Expression{ .Cons = ConsCell{ .Car = car, .Cdr = cdr } };
        return cc;
    }
    const cdr = parseExpr(parser, quoted) orelse {
        parser.allocator.destroy(cc);
        return car;
    };
    cc.* = Expression{ .Cons = ConsCell{ .Car = car, .Cdr = try parseList(parser, cdr, quoted) } };
    return cc;
}
