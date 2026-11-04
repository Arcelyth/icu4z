//! A wrapper for ICU's UBreakIterator type.
//! Finds character, word, line, and sentence boundaries in UTF-8 text.
//! Positions are byte offsets.
const BreakIterator = @This();
const std = @import("std");
const c = @import("c");
const errors = @import("error.zig");

ref: *c.UBreakIterator,
allocator: std.mem.Allocator,
text: []const u8,

pub const Kind = enum(c_uint) {
    /// Extended grapheme clusters, such as a letter and its combining marks.
    character = c.UBRK_CHARACTER,
    word = c.UBRK_WORD,
    line = c.UBRK_LINE,
    sentence = c.UBRK_SENTENCE,
};

pub fn init(allocator: std.mem.Allocator, kind: Kind, locale: ?[:0]const u8, text: []const u8) !BreakIterator {
    const text_length = try errors.length(text.len);
    const bytes = try allocator.dupe(u8, text);
    errdefer allocator.free(bytes);

    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const ref = c.ubrk_open(@backingInt(kind), if (locale) |value| value.ptr else null, null, 0, &status);
    errdefer if (ref) |value| c.ubrk_close(value);
    try errors.check(status);
    const iterator = ref orelse return error.UnexpectedResult;

    const utext = c.utext_openUTF8(null, bytes.ptr, text_length, &status);
    defer if (utext != null) {
        _ = c.utext_close(utext);
    };
    try errors.check(status);
    if (utext == null) return error.UnexpectedResult;

    c.ubrk_setUText(iterator, utext, &status);
    try errors.check(status);
    return .{
        .ref = iterator,
        .allocator = allocator,
        .text = bytes,
    };
}

/// Frees the iterator and its text.
pub fn deinit(self: BreakIterator) void {
    c.ubrk_close(self.ref);
    self.allocator.free(self.text);
}

/// Moves to the start of the text and returns zero.
pub fn first(self: *BreakIterator) usize {
    return @intCast(c.ubrk_first(self.ref));
}

/// Moves to the end of the text and returns its byte length.
pub fn last(self: *BreakIterator) usize {
    return @intCast(c.ubrk_last(self.ref));
}

/// Moves to the next boundary, or returns null at the end.
pub fn next(self: *BreakIterator) ?usize {
    return position(c.ubrk_next(self.ref));
}

/// Moves to the previous boundary, or returns null at the start.
pub fn previous(self: *BreakIterator) ?usize {
    return position(c.ubrk_previous(self.ref));
}

/// Moves to the first boundary strictly after this byte offset.
pub fn following(self: *BreakIterator, offset: usize) !?usize {
    return position(c.ubrk_following(self.ref, try errors.length(offset)));
}

/// Moves to the first boundary strictly before this byte offset.
pub fn preceding(self: *BreakIterator, offset: usize) !?usize {
    return position(c.ubrk_preceding(self.ref, try errors.length(offset)));
}

/// Returns the rule status of the last boundary, such as `raw.UBRK_WORD_LETTER`.
pub fn ruleStatus(self: *const BreakIterator) i32 {
    return c.ubrk_getRuleStatus(self.ref);
}

fn position(offset: i32) ?usize {
    return if (offset == c.UBRK_DONE) null else @intCast(offset);
}

test "icu4z BreakIterator: character boundaries use UTF-8 byte offsets" {
    var iterator = try BreakIterator.init(std.testing.allocator, .character, "", "Ae\u{301}😀B");
    defer iterator.deinit();

    try std.testing.expectEqual(@as(usize, 0), iterator.first());
    for ([_]usize{ 1, 4, 8, 9 }) |expected| {
        try std.testing.expectEqual(@as(?usize, expected), iterator.next());
    }
    try std.testing.expectEqual(@as(?usize, null), iterator.next());
    try std.testing.expectEqual(@as(usize, 9), iterator.last());
    try std.testing.expectEqual(@as(?usize, 8), iterator.previous());
    try std.testing.expectEqual(@as(?usize, 4), try iterator.preceding(8));
    try std.testing.expectEqual(@as(?usize, 8), try iterator.following(4));
    try std.testing.expectEqual(@as(?usize, null), try iterator.preceding(0));
    try std.testing.expectEqual(@as(?usize, null), try iterator.following(9));
}

test "icu4z BreakIterator: word boundaries retain their text" {
    var input = [_]u8{ 'a', ' ', 'b' };
    var iterator = try BreakIterator.init(std.testing.allocator, .word, "en", &input);
    defer iterator.deinit();
    @memset(&input, ' ');

    try std.testing.expectEqual(@as(?usize, 1), iterator.next());
    try std.testing.expect(iterator.ruleStatus() >= c.UBRK_WORD_LETTER);
    try std.testing.expect(iterator.ruleStatus() < c.UBRK_WORD_LETTER_LIMIT);
    try std.testing.expectEqual(@as(?usize, 2), iterator.next());
    try std.testing.expectEqual(c.UBRK_WORD_NONE, iterator.ruleStatus());
    try std.testing.expectEqual(@as(?usize, 3), iterator.next());
    try std.testing.expectEqual(@as(?usize, null), iterator.next());
}

test "icu4z BreakIterator: empty and invalid UTF-8 boundaries" {
    var empty = try BreakIterator.init(std.testing.allocator, .character, "", "");
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.first());
    try std.testing.expectEqual(@as(usize, 0), empty.last());
    try std.testing.expectEqual(@as(?usize, null), empty.next());

    var invalid = try BreakIterator.init(std.testing.allocator, .character, "", "\xffa");
    defer invalid.deinit();
    try std.testing.expectEqual(@as(?usize, 1), invalid.next());
    try std.testing.expectEqual(@as(?usize, 2), invalid.next());
    try std.testing.expectEqual(@as(?usize, null), invalid.next());
}

test "icu4z BreakIterator: line and sentence boundaries" {
    var lines = try BreakIterator.init(std.testing.allocator, .line, "en", "a b\n");
    defer lines.deinit();
    try std.testing.expectEqual(@as(?usize, 2), lines.next());
    try std.testing.expectEqual(@as(?usize, 4), lines.next());
    try std.testing.expectEqual(@as(?usize, null), lines.next());

    var sentences = try BreakIterator.init(std.testing.allocator, .sentence, "en", "One. Two.");
    defer sentences.deinit();
    try std.testing.expectEqual(@as(?usize, 5), sentences.next());
    try std.testing.expectEqual(@as(?usize, 9), sentences.next());
    try std.testing.expectEqual(@as(?usize, null), sentences.next());
    try std.testing.expectError(error.OutOfMemory, BreakIterator.init(std.testing.failing_allocator, .word, "", "text"));
}
