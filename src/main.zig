const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const io = std.io;
const os = std.os;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const File = fs.File;
const Reader = io.Reader(File, File.ReadError, File.read);
const TTY_ = @import("tty.zig");
const TTY = TTY_.TTY;
const tty_codes = TTY_.OpCodes;

const TokenType = enum(u8) {
    Unknown,
    String,
};

const Token = struct {
    raw: []const u8,
    type: TokenType = TokenType.Unknown,
};

const Tokenizer = struct {
    alloc: Allocator,
    raw: ArrayList(u8),
    tokens: ArrayList(Token),

    pub const TokenError = error{
        None,
        Unknown,
        LineTooLong,
        ParseError,
    };

    const Builtin = [_][]const u8{
        "alias",
        "which",
        "echo",
    };

    pub fn init(a: Allocator) Tokenizer {
        return Tokenizer{
            .alloc = a,
            .raw = ArrayList(u8).init(a),
            .tokens = ArrayList(Token).init(a),
        };
    }

    pub fn raze(self: Tokenizer) void {
        self.alloc.deinit();
    }

    pub fn parse_string(self: *Tokenizer, src: []const u8) TokenError!Token {
        _ = self;
        var end: usize = 0;
        for (src, 0..) |s, i| {
            end = i;
            if (s == ' ') {
                break;
            }
        } else end += 1;
        return Token{
            .raw = src[0..end],
            .type = TokenType.String,
        };
    }

    pub fn parse(self: *Tokenizer) TokenError!void {
        self.tokens.clearAndFree();
        var start: usize = 0;
        while (start < self.raw.items.len) {
            const t = self.parse_string(self.raw.items[start..]);
            if (t) |tt| {
                if (tt.raw.len > 0) {
                    self.tokens.append(tt) catch unreachable;
                    start += tt.raw.len;
                } else {
                    start += 1;
                }
            } else |_| {
                return TokenError.ParseError;
            }
        }
    }

    pub fn dump_parsed(self: Tokenizer) !void {
        std.debug.print("\n\n", .{});
        for (self.tokens.items) |i| {
            std.debug.print("{}\n", .{i});
            std.debug.print("{s}\n", .{i.raw});
        }
    }

    pub fn tab(self: Tokenizer) !bool {
        _ = self;
        return true;
    }

    pub fn pop(self: *Tokenizer) TokenError!void {
        _ = self.raw.popOrNull();
    }
    pub fn consumec(self: *Tokenizer, c: u8) TokenError!void {
        self.raw.append(c) catch return TokenError.Unknown;
    }

    pub fn clear(self: *Tokenizer) void {
        self.raw.clearAndFree();
        self.tokens.clearAndFree();
    }

    pub fn consumes(self: *Tokenizer, r: Reader) TokenError!void {
        var buf: [2 ^ 8]u8 = undefined;
        var line = r.readUntilDelimiterOrEof(&buf, '\n') catch |e| {
            if (e == error.StreamTooLong) {
                return TokenError.LineTooLong;
            }
            return TokenError.Unknown;
        };
        self.raw.appendSlice(line.?) catch return TokenError.Unknown;
    }
};

fn prompt(tty: *TTY, tkn: *Tokenizer) !void {
    try tty.prompt("\r{s}@{s}({})({}) # {s}", .{
        "username",
        "host",
        tkn.raw.items.len,
        tkn.tokens.items.len,
        tkn.raw.items,
    });
}

pub fn csi(tty: *TTY) !void {
    var buffer: [1]u8 = undefined;
    _ = try os.read(tty.tty, &buffer);
    if (buffer[0] == 'D') {
        tty.chadj += 1;
    } else if (buffer[0] == 'C') {
        tty.chadj -= 1;
    } else {
        try tty.print("\r\nCSI next: \r\n", .{});
        try tty.printAfter("    {x} {s}", .{ buffer[0], buffer });
    }
}

pub fn loop(tty: *TTY, tkn: *Tokenizer) !bool {
    while (true) {
        try prompt(tty, tkn);
        var buffer: [1]u8 = undefined;
        _ = try os.read(tty.tty, &buffer);
        switch (buffer[0]) {
            '\x1B' => {
                _ = try os.read(tty.tty, &buffer);
                if (buffer[0] == '[') {
                    try csi(tty);
                } else {
                    try tty.print("\r\ninput: escape {s} {}\n", .{ buffer, buffer[0] });
                }
            },
            '\x08' => try tty.print("\r\ninput: backspace\r\n", .{}),
            '\x09' => {
                if (tkn.tab()) |tab| {
                    if (tab) {} else {}
                } else |err| {
                    _ = err;
                    unreachable;
                }
            },
            '\x7F' => try tkn.pop(),
            '\x17' => try tty.print("\r\ninput: ^w\r\n", .{}),
            '\x03' => {
                if (tkn.raw.items.len >= 0) {
                    try tty.print("^C\r\n", .{});
                    tkn.clear();
                } else {
                    try tty.print("\r\nExit caught... Bye ()\r\n", .{});
                    return false;
                }
            },
            '\x04' => |b| {
                try tty.print("\r\nExit caught... Bye ({})\r\n", .{b});
                return false;
            },
            '\n', '\r' => {
                try tty.print("\r\n", .{});
                try tkn.parse();
                try tkn.dump_parsed();
                if (tkn.tokens.items.len > 0) {
                    return true;
                }
            },
            else => |b| {
                try tkn.consumec(b);
                try tty.printAfter("    {} {s}", .{ b, buffer });
            },
        }
    }
}

test "c memory" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tkn = Tokenizer.init(a);
    for ("ls -la") |c| {
        try tkn.consumec(c);
    }
    try tkn.parse();

    var argv: [:null]?[*:0]u8 = undefined;
    var list = ArrayList(?[*:0]u8).init(a);
    try std.testing.expect(tkn.tokens.items.len == 2);
    try std.testing.expect(mem.eql(u8, tkn.tokens.items[0].raw, "ls"));
    for (tkn.tokens.items) |token| {
        var arg = a.alloc(u8, token.raw.len + 1) catch unreachable;
        mem.copy(u8, arg, token.raw);
        arg[token.raw.len] = 0;
        try list.append(@ptrCast(?[*:0]u8, arg.ptr));
    }
    try std.testing.expect(list.items.len == 2);
    argv = list.toOwnedSliceSentinel(null) catch unreachable;

    try std.testing.expect(mem.eql(u8, argv[0].?[0..2 :0], "ls"));
    try std.testing.expect(mem.eql(u8, argv[1].?[0..3 :0], "-la"));
    try std.testing.expect(argv[2] == null);
}

pub fn exec(tty: *TTY, tkn: *Tokenizer) !void {
    _ = tty;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var argv: [:null]?[*:0]u8 = undefined;
    var list = ArrayList(?[*:0]u8).init(a);
    for (tkn.tokens.items) |token| {
        var arg = a.alloc(u8, token.raw.len + 1) catch unreachable;
        mem.copy(u8, arg, token.raw);
        arg[token.raw.len] = 0;
        try list.append(@ptrCast(?[*:0]u8, arg.ptr));
    }
    argv = list.toOwnedSliceSentinel(null) catch unreachable;

    const fork_pid = try std.os.fork();
    if (fork_pid == 0) {
        // TODO manage env
        const res = std.os.execvpeZ(argv[0].?, argv, @ptrCast([*:null]?[*:0]u8, std.os.environ));
        std.debug.print("exec error {}", .{res});
        unreachable;
    } else {
        const res = std.os.waitpid(fork_pid, 0);
        std.debug.print("fork res {}", .{res.status});
    }
}

pub fn sig_cb(sig: c_int, info: *const os.siginfo_t, uctx: ?*const anyopaque) callconv(.C) void {
    if (sig != os.SIG.WINCH) unreachable;
    _ = info;
    _ = uctx; // TODO maybe install uctx and drop TTY.current_tty?
    var curr = TTY_.current_tty.?;
    curr.size = TTY.geom(curr.tty) catch unreachable;
}

pub fn signals() !void {
    try os.sigaction(os.SIG.WINCH, &os.Sigaction{
        .handler = .{ .sigaction = sig_cb },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null);
}

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n\n", .{"codebase"});
    var tty = TTY.init() catch unreachable;
    defer tty.raze();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var t = Tokenizer.init(arena.allocator());

    try signals();

    while (true) {
        if (loop(&tty, &t)) |l| {
            if (l) {
                try exec(&tty, &t);
                t.clear();
            } else {
                break;
            }
        } else |err| {
            std.debug.print("unexpected error {}\n", .{err});
            unreachable;
        }
    }
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, retaddr: ?usize) noreturn {
    @setCold(true);
    TTY_.current_tty.?.raze();
    std.builtin.default_panic(msg, trace, retaddr);
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "alloc" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var t = Tokenizer.init(a);
    try expect(std.mem.eql(u8, t.raw.items, ""));
}

test "tokens" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = Tokenizer.init(a);
    for ("token") |c| {
        try parsed.consumec(c);
    }
    try parsed.parse();
    try expect(std.mem.eql(u8, parsed.raw.items, "token"));
}

test "parse string" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var t = Tokenizer.init(a);
    var tkn = t.parse_string("string is true");
    if (tkn) |tk| {
        try expect(std.mem.eql(u8, tk.raw, "string"));
        try expect(tk.raw.len == 6);
    } else |_| {}
}
