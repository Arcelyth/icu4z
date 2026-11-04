//! A wrapper for ICU's UCollator type.
//! Compares UTF-8 text using a locale's sorting rules.
const Collator = @This();
const std = @import("std");
const c = @import("c");
const errors = @import("error.zig");

ref: *c.UCollator,

/// Opens the locale's sorting rules. Call `deinit` when finished.
/// A null locale uses ICU's default locale; "" uses the root locale.
pub fn init(locale: ?[:0]const u8) !Collator {
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const ref = c.ucol_open(if (locale) |value| value.ptr else null, &status);
    errdefer if (ref) |value| c.ucol_close(value);
    try errors.check(status);
    return .{ .ref = ref orelse return error.UnexpectedResult };
}

/// Frees the collator.
pub fn deinit(self: Collator) void {
    c.ucol_close(self.ref);
}

/// Compares two UTF-8 strings. Invalid UTF-8 is treated as U+FFFD by ICU.
pub fn compare(self: *const Collator, first: []const u8, second: []const u8) !std.math.Order {
    const first_length = try errors.length(first.len);
    const second_length = try errors.length(second.len);
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const result = c.ucol_strcollUTF8(self.ref, first.ptr, first_length, second.ptr, second_length, &status);
    try errors.check(status);
    return switch (result) {
        c.UCOL_LESS => .lt,
        c.UCOL_EQUAL => .eq,
        c.UCOL_GREATER => .gt,
        else => unreachable,
    };
}

test "icu4z Collator: follows locale sorting rules" {
    const german = try Collator.init("de");
    defer german.deinit();
    const swedish = try Collator.init("sv");
    defer swedish.deinit();

    try std.testing.expectEqual(.lt, try german.compare("ä", "z"));
    try std.testing.expectEqual(.gt, try swedish.compare("ä", "z"));
    try std.testing.expectEqual(.eq, try german.compare("é", "e\u{301}"));
}

test "icu4z Collator: empty and invalid UTF-8 strings" {
    const collator = try Collator.init("");
    defer collator.deinit();

    try std.testing.expectEqual(.eq, try collator.compare("", ""));
    try std.testing.expectEqual(.lt, try collator.compare("", "a"));
    try std.testing.expectEqual(.eq, try collator.compare("\xff", "\u{fffd}"));
    try std.testing.expectEqual(.lt, try collator.compare("a\x00b", "a\x00c"));
}
