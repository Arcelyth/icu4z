//! UTF-8 and UTF-16 conversion. Invalid text returns an error.
//! Embedded NULs are preserved. Returned slices are not sentinel-terminated.
const std = @import("std");
const c = @import("c");
const errors = @import("error.zig");

/// Converts UTF-8 to UTF-16. Free the result with allocator.free.
pub fn toUtf16(allocator: std.mem.Allocator, text: []const u8) ![]u16 {
    const length = try errors.length(text.len);
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    var required: i32 = 0;
    _ = c.u_strFromUTF8(null, 0, &required, text.ptr, length, &status);
    if (status != c.U_BUFFER_OVERFLOW_ERROR) try checkEncoding(status, error.InvalidUtf8);
    if (required < 0) return error.UnexpectedResult;

    const result = try allocator.alloc(u16, @intCast(required));
    errdefer allocator.free(result);
    if (required == 0) return result;
    status = c.U_ZERO_ERROR;
    var written: i32 = 0;
    _ = c.u_strFromUTF8(result.ptr, required, &written, text.ptr, length, &status);
    try checkEncoding(status, error.InvalidUtf8);
    if (written != required) return error.UnexpectedResult;

    return result;
}

/// Converts UTF-16 to UTF-8. Unpaired surrogates return InvalidUtf16.
/// Free the result with allocator.free.
pub fn toUtf8(allocator: std.mem.Allocator, text: []const u16) ![]u8 {
    const length = try errors.length(text.len);
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    var required: i32 = 0;
    _ = c.u_strToUTF8(null, 0, &required, text.ptr, length, &status);
    if (status != c.U_BUFFER_OVERFLOW_ERROR) try checkEncoding(status, error.InvalidUtf16);
    if (required < 0) return error.UnexpectedResult;

    const result = try allocator.alloc(u8, @intCast(required));
    errdefer allocator.free(result);
    if (required == 0) return result;
    status = c.U_ZERO_ERROR;
    var written: i32 = 0;
    _ = c.u_strToUTF8(result.ptr, required, &written, text.ptr, length, &status);
    try checkEncoding(status, error.InvalidUtf16);
    if (written != required) return error.UnexpectedResult;

    return result;
}

fn checkEncoding(status: c.UErrorCode, comptime invalid: anyerror) !void {
    switch (status) {
        c.U_INVALID_CHAR_FOUND, c.U_ILLEGAL_CHAR_FOUND, c.U_TRUNCATED_CHAR_FOUND => return invalid,
        else => try errors.check(status),
    }
}

test "icu4z strings: UTF-8 and UTF-16" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "", "hello", "Café\x00مرحبا 😀" }) |text| {
        const utf16 = try toUtf16(allocator, text);
        defer allocator.free(utf16);
        const utf8 = try toUtf8(allocator, utf16);
        defer allocator.free(utf8);
        try std.testing.expectEqualStrings(text, utf8);
    }
    const emoji = try toUtf16(allocator, "😀");
    defer allocator.free(emoji);
    try std.testing.expectEqualSlices(u16, &.{ 0xD83D, 0xDE00 }, emoji);
}

test "icu4z strings: invalid text and allocation failure" {
    for ([_][]const u8{ "\xFF", "\xE2\x82", "\xC0\xAF", "\xED\xA0\x80" }) |text|
        try std.testing.expectError(error.InvalidUtf8, toUtf16(std.testing.allocator, text));
    try std.testing.expectError(error.InvalidUtf16, toUtf8(std.testing.allocator, &.{0xD800}));
    try std.testing.expectError(error.InvalidUtf16, toUtf8(std.testing.allocator, &.{0xDC00}));
    try std.testing.expectError(error.OutOfMemory, toUtf16(std.testing.failing_allocator, "abc"));
    try std.testing.expectError(error.OutOfMemory, toUtf8(std.testing.failing_allocator, &.{'a'}));
}
