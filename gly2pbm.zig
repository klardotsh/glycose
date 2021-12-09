const std = @import("std");
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const BitList = ArrayList(bool);
const BitListList = ArrayList(BitList);

const ASCII_0 = '0';
const ASCII_1 = '1';
const ASCII_NL = '\n';

// 0x0a is an inclusive-to-encoding termination byte
const GTFO = 0x0a;

/// on-disk format as documented at
/// https://wiki.xxiivv.com/site/gly_format.html
//
// this implementation reflects what worked on my big-endian machine. patches
// welcome if anyone gets a chance to test on little-endian and finds that
// it's broken
const GlyByte = packed struct {
    y3: bool,
    y2: bool,
    y1: bool,
    y0: bool,
    y_multiple: u2,

    // whether to move the draw head +1 on x axis **after** drawing the bits
    // defined in this byte
    x_inc: bool,

    ascii_barf: bool,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const Glyph = struct {
    /// actually bounded by format to 64, check at runtime
    overall_height: u8 = 0,

    overall_width: usize = 0,

    /// gly, by nature of being an inline glyph protocol, isn't *especially*
    /// friendly to converting to formats that require image dimensions to be
    /// known upfront: notably, nothing in the on-disk spec prohibits each row
    /// of an image being of a different, arbitrary width, meaning we need to
    /// always track the maximum width yet seen (overall_width), and then
    /// tail-pad each row to that width when spitting out the PBM. thus, data
    /// is a list of lists that will require post-processing. outer list is a
    /// row, containing an inner list of column bits
    data: BitListList,

    fn to_string(self: @This(), allocator: *std.mem.Allocator) ![]u8 {
        const p1_fmt =
            \\P1
            \\{d} {d}{s}
        ;

        var imgdata = try gpa.allocator.alloc(u8, self.overall_height * (self.overall_width + 1));
        defer gpa.allocator.free(imgdata);

        var idx: usize = 0;
        for (self.data.items) |row| {
            imgdata[idx] = ASCII_NL;
            idx += 1;

            for (row.items) |col| {
                imgdata[idx] = if (col) ASCII_1 else ASCII_0;
                idx += 1;
            }
        }

        return std.fmt.allocPrint(allocator, p1_fmt, .{ self.overall_width, self.overall_width, imgdata });
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

// don't confuse this with a proper immutable struct from FP languages; I'm far
// too lazy to implement immutable datastructures in this low-level of language
// tonight. this application does not have rewind capabilities, this struct
// solely exists to hold "global state" in a test- (and just general
// readability-) friendly way
const State = struct {
    // it's worth noting that a flipped first bit is almost certainly
    // ambiguous: while left et. al. use it to flip into graphics mode, this
    // works only in an ASCII-only world. quoth xxiivv: "The format resides
    // entirely in the second half of the ascii table, or above $80". this
    // broadly means non-english documents probably aren't suited to embed
    // these graphics, but thankfully gly2pbm is not concerned with documents,
    // just images.
    in_seq: bool,

    x_idx: usize = 0,
    rows_read: usize = 0,

    /// seen y levels in a given column
    seen_ys: usize = 0,

    glyph: Glyph,
};

fn get_arena_allocator() ArenaAllocator {
    return ArenaAllocator.init(&gpa.allocator);
}

pub fn main() anyerror!void {
    var GPArenaAllocator = get_arena_allocator();
    defer GPArenaAllocator.deinit();
    var initial_state = make_initial_state(&GPArenaAllocator.allocator);
}

fn make_initial_state(allocator: *std.mem.Allocator) !State {
    return State{
        .in_seq = false,
        .glyph = Glyph{
            .data = try BitListList.initCapacity(allocator, 16),
        },
    };
}

fn next(allocator: *std.mem.Allocator, state: State, byte: u8) !State {
    var ret = state;
    if (state.in_seq and byte == GTFO) {
        ret.in_seq = false;
        ret.x_idx = 0;
        ret.rows_read += 1;
        ret.seen_ys = 0;
        return ret;
    }

    ret.in_seq = true;

    const packed_byte = @bitCast(GlyByte, byte);

    if (!packed_byte.ascii_barf) {
        // making sure we end on 0x0a is the caller's problem. we're an image
        // parser, not a document parser.
        return error.MalformedSequence;
    }

    if (ret.x_idx == 0 and ret.seen_ys == 0) {
        var i: usize = 0;
        // in theory the spec may allow writing, say, 4 bits of the vertical
        // space rather than all 16, and this is undefined behavior. this
        // implementation treats the remaining 12 bits as existent but "off" (0
        // bit) pixels, even though the image author likely intended the image
        // to be truncated to 4px tall.
        ret.glyph.overall_height += 16;
        while (i < 16) {
            // the spec also theoretically allows holes at x=0 since x-inc is a
            // bit that can be set without any other bound checks. holes at any
            // other index are implicitly guarded against.
            var ilist = try BitList.initCapacity(allocator, 1);
            if (packed_byte.x_inc) {
                try ilist.append(false);
            }

            try ret.glyph.data.append(ilist);

            i += 1;
        }
    }

    if (ret.seen_ys > 3) {
        return error.TooManyRowsInColumn;
    }

    var tgt: usize = (16 * ret.rows_read) + (4 * @as(usize, packed_byte.y_multiple));
    var end: usize = tgt + 4;
    while (tgt < end) {
        try ret.glyph.data.items[tgt].append(switch (end - tgt - 1) {
            0 => packed_byte.y0,
            1 => packed_byte.y1,
            2 => packed_byte.y2,
            3 => packed_byte.y3,
            else => unreachable,
        });

        tgt += 1;
    }

    ret.seen_ys += 1;

    if (packed_byte.x_inc) {
        ret.x_idx += 1;
        ret.seen_ys = 0;

        if (ret.x_idx > ret.glyph.overall_width) {
            ret.glyph.overall_width = ret.x_idx;
        }

        var filler_idx: usize = 0;
        while (filler_idx < ret.glyph.data.items.len) {
            // gly files are inherently dynamic-width, and pbm files are...
            // not. thus, we need to forcibly pad all rows to the maximum width
            // ever seen to be encodable in the end. we may as well do it here,
            // because there's no real philosophically-purer place to do it, so
            // far
            while (ret.glyph.data.items[filler_idx].items.len < ret.x_idx) {
                try ret.glyph.data.items[filler_idx].append(false);
            }
            filler_idx += 1;
        }
    }

    return ret;
}

// this verifies that we can parse the gly data as provided in
// https://web.archive.org/web/20211207025937/https://wiki.xxiivv.com/site/gly_format.html
// into a PBM that is equivalent to one generated by pumping the example PNG
// through convert(1)
test "boxgly" {
    const gly_data: [178]u8 = .{
        0x9f, 0xaf, 0xff, 0x88, 0xe3, 0x84, 0x98, 0xe2, 0x82, 0x94, 0xe2, 0x81, 0x96, 0xa2, 0xfe, 0x8f,
        0x97, 0xe2, 0x97, 0xa2, 0xfc, 0x88, 0x95, 0xa2, 0xf2, 0x84, 0x95, 0xa2, 0xfc, 0x82, 0x95, 0xe2,
        0x81, 0x95, 0xa2, 0xfe, 0x81, 0x95, 0xe2, 0x81, 0x95, 0xa2, 0xfe, 0x81, 0x95, 0xe2, 0x81, 0x95,
        0xa2, 0xfc, 0x81, 0x95, 0xa2, 0xf2, 0x81, 0x95, 0xa2, 0xfc, 0x81, 0x95, 0xe2, 0x81, 0x95, 0xa2,
        0xfe, 0x81, 0x95, 0xe2, 0x81, 0x95, 0xe2, 0x81, 0x95, 0xe2, 0x81, 0x95, 0xae, 0xff, 0x81, 0x95,
        0xe5, 0x81, 0x9d, 0xe8, 0x81, 0x95, 0xf1, 0x81, 0x93, 0xf2, 0x81, 0x91, 0xf1, 0x89, 0x92, 0xe8,
        0x85, 0x94, 0xac, 0xff, 0x83, 0x98, 0xe2, 0x81, 0xe1, 0x0a, 0x8f, 0x9f, 0xaf, 0xff, 0xf8, 0xf8,
        0xf8, 0x89, 0x97, 0xac, 0xf8, 0xa2, 0xf9, 0x88, 0x97, 0xac, 0xf8, 0x81, 0xf8, 0x93, 0xae, 0xf9,
        0x88, 0x94, 0xf8, 0x81, 0x93, 0xac, 0xf8, 0xa2, 0xf9, 0x89, 0x97, 0xac, 0xf8, 0xf8, 0x88, 0x97,
        0xac, 0xf8, 0x81, 0xa2, 0xf9, 0x93, 0xac, 0xf8, 0x88, 0x94, 0xf8, 0x81, 0x93, 0xae, 0xf9, 0xf8,
        0xf8, 0xf8, 0x8f, 0x9f, 0xaf, 0xff, 0xf4, 0xf2, 0xf1, 0xe8, 0xe4, 0xe2, 0x8f, 0x9f, 0xe1, 0xc0,
        0xc0, 0x0a,
    };

    // convert ~/Downloads/boxgly.png -compress none pbm:- | sed -e '3,$s/\s//g'
    //
    //
    // N.B. without -compress none imagemagick will generate a P4 (compressed
    // monochrome bitmap) rather than a P1 (ascii monochrome bitmap), and
    // frankly, I'm a lazy test author... and human in general
    const pbm_exp =
        \\P1
        \\32 32
        \\00001100001111111111111111111111
        \\00010100010000000000000000000010
        \\00100100100000000000000000000100
        \\01000101000000000000000000001000
        \\10000111111111111111111111110000
        \\10001110000000000000000000101000
        \\10011111111111111111111111000100
        \\10100000000000000000000010000010
        \\11000000000000000000000100000001
        \\11111111111111111111111000000010
        \\10000000000000000000001100000100
        \\10000000000000000000001010001100
        \\10000000000000000000001001010100
        \\10001001001010010010001000100100
        \\10001010101010101010001000000100
        \\10001010101010101010001000000100
        \\10001001001010010010001000000100
        \\10000000000000000000001000000100
        \\10000000000000000000001000000100
        \\10001010010010100100001000000100
        \\10001010101010101010001000000100
        \\10001010101010101010001000000100
        \\10001010010010100100001000000100
        \\10000000000000000000001000000100
        \\10000000000000000000001000000100
        \\10000100100100010010001000001000
        \\10001010101010101010001000010000
        \\10001010101010101010001000100000
        \\10000100100100010010001001000000
        \\10000000000000000000001010000000
        \\10000000000000000000001100000000
        \\11111111111111111111111000000000
    ;

    var GPArenaAllocator = get_arena_allocator();
    defer GPArenaAllocator.deinit();
    var state = try make_initial_state(&GPArenaAllocator.allocator);

    for (gly_data) |it| {
        state = try next(&GPArenaAllocator.allocator, state, it);
    }

    var generated_pbm = try state.glyph.to_string(&GPArenaAllocator.allocator);

    try std.testing.expectEqualStrings(pbm_exp, generated_pbm);
}

comptime {
    std.testing.refAllDecls(@This());
}
