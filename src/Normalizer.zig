//! A wrapper for ICU's UNormalizer2 type.
//! https://unicode-org.github.io/icu-docs/apidoc/released/icu4c/unorm2_8h.html
//!
//! Normalizes Unicode text using NFC, NFD, NFKC, or NFKD.
//! For example, NFC combines `e` and a combining acute accent into `é`.
const Normalizer = @This();
const std = @import("std");
const c = @import("c");
const errors = @import("error.zig");
const strings = @import("strings.zig");

/// ICU shares this normalizer. It does not need deinit.
ref: *const c.UNormalizer2,

/// Unicode Normalization Forms.
pub const Form = enum {
    /// Canonical decomposition, then composition.
    nfc,
    /// Canonical decomposition.
    nfd,
    /// Compatibility decomposition, then composition.
    nfkc,
    /// Compatibility decomposition.
    nfkd,
};

/// Gets ICU's normalizer for a Unicode normalization form.
pub fn init(form: Form) !Normalizer {
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const ref = switch (form) {
        .nfc => c.unorm2_getNFCInstance(&status),
        .nfd => c.unorm2_getNFDInstance(&status),
        .nfkc => c.unorm2_getNFKCInstance(&status),
        .nfkd => c.unorm2_getNFKDInstance(&status),
    };
    try errors.check(status);
    return .{
        .ref = ref orelse return error.UnexpectedResult,
    };
}

/// Normalizes UTF-8 text. Free the result with allocator.free.
pub fn normalize(self: *const Normalizer, allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    const utf16 = try strings.toUtf16(allocator, text);
    defer allocator.free(utf16);
    const normalized = try self.normalizeUtf16(allocator, utf16);
    defer allocator.free(normalized);
    return strings.toUtf8(allocator, normalized);
}

/// Normalizes UTF-16 text. Free the result with allocator.free.
pub fn normalizeUtf16(self: *const Normalizer, allocator: std.mem.Allocator, text: []const u16) ![]u16 {
    const length = try errors.length(text.len);
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const required = c.unorm2_normalize(self.ref, text.ptr, length, null, 0, &status);
    if (status != c.U_BUFFER_OVERFLOW_ERROR) try errors.check(status);
    if (required < 0) return error.UnexpectedResult;

    const result = try allocator.alloc(u16, @intCast(required));
    errdefer allocator.free(result);
    if (required == 0) return result;

    status = c.U_ZERO_ERROR;
    const written = c.unorm2_normalize(self.ref, text.ptr, length, result.ptr, required, &status);
    try errors.check(status);
    if (written != required) return error.UnexpectedResult;
    return result;
}

/// Returns whether UTF-8 text is already in this normalization form.
pub fn isNormalized(self: *const Normalizer, allocator: std.mem.Allocator, text: []const u8) !bool {
    const utf16 = try strings.toUtf16(allocator, text);
    defer allocator.free(utf16);
    return self.isNormalizedUtf16(utf16);
}

/// Returns whether UTF-16 text is already in this normalization form.
pub fn isNormalizedUtf16(self: *const Normalizer, text: []const u16) !bool {
    const length = try errors.length(text.len);
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const result = c.unorm2_isNormalized(self.ref, text.ptr, length, &status);
    try errors.check(status);
    return result != 0;
}

test "icu4z Normalizer: normalization forms" {
    const allocator = std.testing.allocator;
    const Case = struct { form: Form, input: []const u8, expected: []const u8 };
    const cases = [_]Case{
        .{ .form = .nfc, .input = "Cafe\u{301}", .expected = "Café" },
        .{ .form = .nfd, .input = "Café", .expected = "Cafe\u{301}" },
        .{ .form = .nfkc, .input = "\u{FB03} \u{FF21}", .expected = "ffi A" },
        .{ .form = .nfkd, .input = "\u{FB03} \u{212B}", .expected = "ffi A\u{30A}" },
        .{ .form = .nfd, .input = "a\u{301}\u{323}", .expected = "a\u{323}\u{301}" },
        .{ .form = .nfc, .input = "\u{1100}\u{1161}\u{11A8}", .expected = "각" },
        .{ .form = .nfd, .input = "각", .expected = "\u{1100}\u{1161}\u{11A8}" },
    };
    for (cases) |case| {
        const normalizer = try Normalizer.init(case.form);
        const result = try normalizer.normalize(allocator, case.input);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(case.expected, result);
        try std.testing.expect(try normalizer.isNormalized(allocator, result));
        try std.testing.expect(!try normalizer.isNormalized(allocator, case.input));
    }
}

test "icu4z Normalizer: empty text and UTF-16" {
    const allocator = std.testing.allocator;
    const normalizer = try Normalizer.init(.nfd);
    const empty = try normalizer.normalize(allocator, "");
    defer allocator.free(empty);
    try std.testing.expectEqualStrings("", empty);
    try std.testing.expect(try normalizer.isNormalized(allocator, ""));

    const input = [_]u16{ 0xE9, 0, 0xD83D, 0xDE00 };
    const result = try normalizer.normalizeUtf16(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u16, &.{ 'e', 0x301, 0, 0xD83D, 0xDE00 }, result);
    try std.testing.expect(!try normalizer.isNormalizedUtf16(&input));
    try std.testing.expect(try normalizer.isNormalizedUtf16(result));

    const utf8 = try normalizer.normalize(allocator, "é\x00😀");
    defer allocator.free(utf8);
    try std.testing.expectEqualStrings("e\u{301}\x00😀", utf8);
}

test "icu4z Normalizer: invalid UTF-8" {
    const normalizer = try Normalizer.init(.nfc);
    try std.testing.expectError(error.InvalidUtf8, normalizer.normalize(std.testing.allocator, "\xC3\x28"));
    try std.testing.expectError(error.InvalidUtf8, normalizer.isNormalized(std.testing.allocator, "\xC3\x28"));
}
