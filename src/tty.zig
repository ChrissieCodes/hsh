const std = @import("std");
const os = std.os;
const mem = std.mem;
const fs = std.fs;
const File = fs.File;
const io = std.io;
const Reader = fs.File.Reader;
const Writer = fs.File.Writer;

const Point = struct {
    x: usize,
    y: usize,
};

pub const OpCodes = enum {
    EraseInLine,
    CurPosGet,
    CurPosSet,
    CurMvUp,
    CurMvDn,
    CurMvLe,
    CurMvRi,
    CurHorzAbs,
};

pub var current_tty: ?TTY = undefined;

pub const TTY = struct {
    tty: i32,
    in: Reader,
    out: Writer,
    orig: os.termios,

    cpos: Point,
    size: Point,
    chadj: i32 = 0,
    cvadj: i32 = 0,

    /// Calling init multiple times is UB
    pub fn init() !TTY {
        // TODO figure out how to handle multiple calls to current_tty?
        const tty = try os.open("/dev/tty", os.linux.O.RDWR, 0);
        const orig = try os.tcgetattr(tty);

        try push_tty(tty, orig);
        current_tty = TTY{
            .tty = tty,
            .in = std.io.getStdIn().reader(),
            .out = std.io.getStdOut().writer(),
            .orig = orig,
            .cpos = cpos(tty) catch unreachable,
            .size = geom(tty) catch unreachable,
        };
        return current_tty.?;
    }

    fn push_tty(tty: i32, tos: os.termios) !void {
        var raw = tos;
        raw.lflag &= ~@as(
            os.linux.tcflag_t,
            os.linux.ECHO | os.linux.ICANON | os.linux.ISIG | os.linux.IEXTEN,
        );
        raw.iflag &= ~@as(
            os.linux.tcflag_t,
            os.linux.IXON | os.linux.ICRNL | os.linux.BRKINT | os.linux.INPCK | os.linux.ISTRIP,
        );
        raw.cc[os.system.V.TIME] = 0;
        raw.cc[os.system.V.MIN] = 1;
        try os.tcsetattr(tty, .FLUSH, raw);
    }

    pub fn write(tty: TTY, string: []const u8) !usize {
        return try tty.out.write(string);
    }

    pub fn writeAll(tty: TTY, string: []const u8) !void {
        try tty.out.writeAll(string);
    }

    pub fn prompt(tty: TTY, comptime fmt: []const u8, args: anytype) !void {
        try tty.print(fmt, args);
        try tty.opcode(OpCodes.EraseInLine, null);
        var move = tty.chadj;
        while (move > 0) : (move -= 1) {
            try tty.opcode(OpCodes.CurMvLe, null);
        }
    }

    pub fn print(tty: TTY, comptime fmt: []const u8, args: anytype) !void {
        try tty.out.print(fmt, args);
    }

    pub fn printAfter(tty: TTY, comptime fmt: []const u8, args: anytype) !void {
        // TODO count cursor moves
        // or TODO save and restore tty screen?

        //try tty.opcode(OpCodes.CurHorzAbs, null);
        //try tty.opcode(OpCodes.CurMvDn, null);
        _ = try tty.write("\r\n");
        try tty.print(fmt, args);
        try tty.opcode(OpCodes.EraseInLine, null);
        try tty.opcode(OpCodes.CurMvUp, null);
    }

    pub fn opcode(tty: TTY, comptime code: OpCodes, args: anytype) !void {
        // TODO fetch info back out :/
        _ = args;
        switch (code) {
            OpCodes.EraseInLine => try tty.writeAll("\x1B[K"),
            OpCodes.CurPosGet => try tty.print("\x1B[6n"),
            OpCodes.CurMvUp => try tty.writeAll("\x1B[A"),
            OpCodes.CurMvDn => try tty.writeAll("\x1B[B"),
            OpCodes.CurMvLe => try tty.writeAll("\x1B[D"),
            OpCodes.CurMvRi => try tty.writeAll("\x1B[C"),
            OpCodes.CurHorzAbs => try tty.writeAll("\x1B[G"),
            else => unreachable,
        }
    }

    fn cpos(tty: i32) !Point {
        std.debug.print("\x1B[6n", .{});
        var buffer: [10]u8 = undefined;
        const len = try os.read(tty, &buffer);
        var splits = mem.split(u8, buffer[2..], ";");
        var x: usize = std.fmt.parseInt(usize, splits.next().?, 10) catch 0;
        var y: usize = 0;
        if (splits.next()) |thing| {
            y = std.fmt.parseInt(usize, thing[0 .. len - 3], 10) catch 0;
        }
        return Point{
            .x = x,
            .y = y,
        };
    }

    pub fn geom(tty: i32) !Point {
        var size = mem.zeroes(os.linux.winsize);
        const err = os.system.ioctl(tty, os.linux.T.IOCGWINSZ, @ptrToInt(&size));
        if (os.errno(err) != .SUCCESS) {
            return os.unexpectedErrno(@intToEnum(os.system.E, err));
        }
        return Point{
            .x = size.ws_row,
            .y = size.ws_col,
        };
    }

    pub fn raze(tty: TTY) void {
        os.tcsetattr(tty.tty, .FLUSH, tty.orig) catch |err| {
            std.debug.print(
                "\r\n\nTTY ERROR RAZE encountered, {} when attempting to raze.\r\n\n",
                .{err},
            );
        };
    }
};

const expect = std.testing.expect;
test "split" {
    var s = "\x1B[86;1R";
    var splits = std.mem.split(u8, s[2..], ";");
    var x: usize = std.fmt.parseInt(usize, splits.next().?, 10) catch 0;
    var y: usize = 0;
    if (splits.next()) |thing| {
        y = std.fmt.parseInt(usize, thing[0 .. thing.len - 1], 10) catch unreachable;
    }
    try expect(x == 86);
    try expect(y == 1);
}

test "CSI format" {
    // For Control Sequence Introducer, or CSI, commands, the ESC [ (written as
    // \e[ or \033[ in several programming and scripting languages) is followed
    // by any number (including none) of "parameter bytes" in the range
    // 0x30–0x3F (ASCII 0–9:;<=>?), then by any number of "intermediate bytes"
    // in the range 0x20–0x2F (ASCII space and !"#$%&'()*+,-./), then finally by
    // a single "final byte" in the range 0x40–0x7E (ASCII
    // @A–Z[\]^_`a–z{|}~).[5]: 5.4 
}
