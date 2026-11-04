//! A wrapper for ICU's IDNA API.
//! https://unicode-org.github.io/icu-docs/apidoc/released/icu4c/uidna_8h.html
const Idna = @This();
const std = @import("std");
const c = @import("c");
const errors = @import("error.zig");

ref: *c.UIDNA,

/// ICU's IDNA validation flags. Several flags may be set together.
pub const IdnaErrors = packed struct(u32) {
    empty_label: bool = false,
    label_too_long: bool = false,
    domain_name_too_long: bool = false,
    leading_hyphen: bool = false,
    trailing_hyphen: bool = false,
    hyphen_3_4: bool = false,
    leading_combining_mark: bool = false,
    disallowed: bool = false,
    punycode: bool = false,
    label_has_dot: bool = false,
    invalid_ace_label: bool = false,
    bidi: bool = false,
    contextj: bool = false,
    contexto_punctuation: bool = false,
    contexto_digits: bool = false,
    reserved: u17 = 0,

    /// Returns whether any validation error is set.
    pub fn any(self: IdnaErrors) bool {
        return @as(u32, @bitCast(self)) != 0;
    }
};

pub const Result = struct {
    /// Converted UTF-8 text. Release it with `deinit`.
    text: []u8,
    /// ICU's UIDNA_ERROR_* bits. Zero means the name passed validation.
    errors: IdnaErrors,
    /// Whether transitional and nontransitional processing produce different text.
    ///
    /// For example, it's true for `faß.de`:
    /// - Transitional: fass.de
    /// - Nontransitional: xn--fa-hia.de
    is_transitional_different: bool,

    pub fn deinit(self: Result, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

/// Creates a reusable converter. Pass ICU's UIDNA_* option bits.
/// Close it with `deinit` after all conversions have finished.
pub fn init(options: u32) !Idna {
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const ref = c.uidna_openUTS46(options, &status);
    errdefer if (ref) |value| c.uidna_close(value);
    try errors.check(status);
    return .{
        .ref = ref orelse return error.UnexpectedResult,
    };
}

pub fn deinit(self: Idna) void {
    c.uidna_close(self.ref);
}

/// Converts a complete domain name to ASCII, for example `bücher.de` to `xn--bcher-kva.de`.
pub fn nameToAscii(self: Idna, allocator: std.mem.Allocator, input: []const u8) !Result {
    return self.convert(allocator, input, c.uidna_nameToASCII_UTF8);
}

/// Converts a complete domain name to UTF-8, for example `xn--bcher-kva.de` to `bücher.de`.
pub fn nameToUnicode(self: Idna, allocator: std.mem.Allocator, input: []const u8) !Result {
    return self.convert(allocator, input, c.uidna_nameToUnicodeUTF8);
}

/// Converts one label to ASCII, for example `bücher` to `xn--bcher-kva`.
pub fn labelToAscii(self: Idna, allocator: std.mem.Allocator, input: []const u8) !Result {
    return self.convert(allocator, input, c.uidna_labelToASCII_UTF8);
}

/// Converts one label to UTF-8, for example `xn--bcher-kva` to `bücher`.
pub fn labelToUnicode(self: Idna, allocator: std.mem.Allocator, input: []const u8) !Result {
    return self.convert(allocator, input, c.uidna_labelToUnicodeUTF8);
}

// uidna_nameToASCII_UTF8 (
//     const UIDNA *idna,
//     const UChar *name,
//     int32_t length,
//     UChar *dest,
//     int32_t capacity,
//     UIDNAInfo *pInfo,
//     UErrorCode *pErrorCode,
// )
const Operation = @TypeOf(c.uidna_nameToASCII_UTF8);

// Runs a ICU operation on the UTF-8 input.
fn convert(
    self: Idna,
    allocator: std.mem.Allocator,
    input: []const u8,
    comptime operation: Operation,
) !Result {
    const input_length = try errors.length(input.len);
    var info = initialInfo();
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const capacity = operation(self.ref, input.ptr, input_length, null, 0, &info, &status);
    if (status != c.U_BUFFER_OVERFLOW_ERROR) try errors.check(status);
    if (capacity < 0) return error.UnexpectedResult;

    const text = try allocator.alloc(u8, @intCast(capacity));
    errdefer allocator.free(text);
    info = initialInfo();
    status = c.U_ZERO_ERROR;
    const written = operation(self.ref, input.ptr, input_length, text.ptr, capacity, &info, &status);
    // ICU may warn that an exact-size buffer has no room for a trailing NUL.
    try errors.check(status);
    if (written != capacity) return error.UnexpectedResult;

    return .{
        .text = text,
        .errors = @bitCast(info.errors),
        .is_transitional_different = info.isTransitionalDifferent != 0,
    };
}

fn initialInfo() c.UIDNAInfo {
    var info = std.mem.zeroes(c.UIDNAInfo);
    info.size = @intCast(@sizeOf(c.UIDNAInfo));
    return info;
}

test "icu4z Idna: domain names and labels" {
    const allocator = std.testing.allocator;
    const idna = try Idna.init(c.UIDNA_NONTRANSITIONAL_TO_ASCII | c.UIDNA_NONTRANSITIONAL_TO_UNICODE);
    defer idna.deinit();

    const ascii = try idna.nameToAscii(allocator, "BÜCHER.de");
    defer ascii.deinit(allocator);
    try std.testing.expectEqualStrings("xn--bcher-kva.de", ascii.text);
    try std.testing.expect(!ascii.errors.any());

    const unicode = try idna.nameToUnicode(allocator, ascii.text);
    defer unicode.deinit(allocator);
    try std.testing.expectEqualStrings("bücher.de", unicode.text);
    try std.testing.expect(!unicode.errors.any());

    const label_ascii = try idna.labelToAscii(allocator, "bücher");
    defer label_ascii.deinit(allocator);
    try std.testing.expectEqualStrings("xn--bcher-kva", label_ascii.text);
    try std.testing.expect(!label_ascii.errors.any());

    const label_unicode = try idna.labelToUnicode(allocator, label_ascii.text);
    defer label_unicode.deinit(allocator);
    try std.testing.expectEqualStrings("bücher", label_unicode.text);
    try std.testing.expect(!label_unicode.errors.any());
}

test "icu4z Idna: validation errors and output" {
    const allocator = std.testing.allocator;
    const idna = try Idna.init(c.UIDNA_NONTRANSITIONAL_TO_ASCII | c.UIDNA_USE_STD3_RULES);
    defer idna.deinit();

    const empty = try idna.nameToAscii(allocator, "");
    defer empty.deinit(allocator);
    try std.testing.expectEqualStrings("", empty.text);
    try std.testing.expect(empty.errors.empty_label);

    const dotted = try idna.labelToAscii(allocator, "a.b");
    defer dotted.deinit(allocator);
    try std.testing.expect(dotted.errors.label_has_dot);

    const malformed = try idna.nameToAscii(allocator, "a\xffb.test");
    defer malformed.deinit(allocator);
    try std.testing.expectEqualStrings("a\u{fffd}b.test", malformed.text);
    try std.testing.expect(malformed.errors.disallowed);

    const nul = try idna.nameToAscii(allocator, "a\x00b.test");
    defer nul.deinit(allocator);
    try std.testing.expectEqualStrings("a\u{fffd}b.test", nul.text);
    try std.testing.expect(nul.errors.disallowed);

    const hyphens = try idna.labelToAscii(allocator, "-a-");
    defer hyphens.deinit(allocator);
    try std.testing.expect(hyphens.errors.leading_hyphen);
    try std.testing.expect(hyphens.errors.trailing_hyphen);
    try std.testing.expect(hyphens.errors.any());

    const flags: IdnaErrors = .{
        .empty_label = true,
        .contexto_digits = true,
    };
    try std.testing.expectEqual(@as(u32, c.UIDNA_ERROR_EMPTY_LABEL | c.UIDNA_ERROR_CONTEXTO_DIGITS), @as(u32, @bitCast(flags)));
}

test "icu4z Idna: options and transitional differences" {
    const allocator = std.testing.allocator;
    const nontransitional = try Idna.init(c.UIDNA_NONTRANSITIONAL_TO_ASCII | c.UIDNA_NONTRANSITIONAL_TO_UNICODE);
    defer nontransitional.deinit();
    const transitional = try Idna.init(0);
    defer transitional.deinit();

    const first = try nontransitional.nameToAscii(allocator, "faß.de");
    defer first.deinit(allocator);
    try std.testing.expectEqualStrings("xn--fa-hia.de", first.text);
    try std.testing.expect(first.is_transitional_different);

    const second = try transitional.nameToAscii(allocator, "faß.de");
    defer second.deinit(allocator);
    try std.testing.expectEqualStrings("fass.de", second.text);
    try std.testing.expect(second.is_transitional_different);
}
