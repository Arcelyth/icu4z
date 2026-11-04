const std = @import("std");
const c = @import("c");

pub const Error = error{
    IllegalArgument,
    MissingResource,
    InvalidFormat,
    FileAccess,
    InternalProgram,
    MessageParse,
    OutOfMemory,
    IndexOutOfBounds,
    Parse,
    InvalidCharacter,
    TruncatedCharacter,
    IllegalCharacter,
    InvalidTableFormat,
    InvalidTableFile,
    BufferOverflow,
    Unsupported,
    ResourceTypeMismatch,
    IllegalEscapeSequence,
    UnsupportedEscapeSequence,
    NoSpaceAvailable,
    CollationElementNotFound,
    PrimaryTooLong,
    StateTooOld,
    TooManyAliases,
    EnumerationOutOfSync,
    InvariantConversion,
    InvalidState,
    CollatorVersionMismatch,
    UselessCollator,
    NoWritePermission,
    InputTooLong,
    /// ICU returned a service-specific error outside the standard error set.
    UnexpectedIcuError,
    /// ICU returned success but an invalid pointer or output length.
    UnexpectedResult,
};

/// Converts ICU's standard failures to Zig errors. Warnings are successful results.
/// Use the raw API when the exact UErrorCode or a warning must be retained.
pub fn check(status: c.UErrorCode) Error!void {
    if (status <= c.U_ZERO_ERROR) return;
    return switch (status) {
        c.U_ILLEGAL_ARGUMENT_ERROR => error.IllegalArgument,
        c.U_MISSING_RESOURCE_ERROR => error.MissingResource,
        c.U_INVALID_FORMAT_ERROR => error.InvalidFormat,
        c.U_FILE_ACCESS_ERROR => error.FileAccess,
        c.U_INTERNAL_PROGRAM_ERROR => error.InternalProgram,
        c.U_MESSAGE_PARSE_ERROR => error.MessageParse,
        c.U_MEMORY_ALLOCATION_ERROR => error.OutOfMemory,
        c.U_INDEX_OUTOFBOUNDS_ERROR => error.IndexOutOfBounds,
        c.U_PARSE_ERROR => error.Parse,
        c.U_INVALID_CHAR_FOUND => error.InvalidCharacter,
        c.U_TRUNCATED_CHAR_FOUND => error.TruncatedCharacter,
        c.U_ILLEGAL_CHAR_FOUND => error.IllegalCharacter,
        c.U_INVALID_TABLE_FORMAT => error.InvalidTableFormat,
        c.U_INVALID_TABLE_FILE => error.InvalidTableFile,
        c.U_BUFFER_OVERFLOW_ERROR => error.BufferOverflow,
        c.U_UNSUPPORTED_ERROR => error.Unsupported,
        c.U_RESOURCE_TYPE_MISMATCH => error.ResourceTypeMismatch,
        c.U_ILLEGAL_ESCAPE_SEQUENCE => error.IllegalEscapeSequence,
        c.U_UNSUPPORTED_ESCAPE_SEQUENCE => error.UnsupportedEscapeSequence,
        c.U_NO_SPACE_AVAILABLE => error.NoSpaceAvailable,
        c.U_CE_NOT_FOUND_ERROR => error.CollationElementNotFound,
        c.U_PRIMARY_TOO_LONG_ERROR => error.PrimaryTooLong,
        c.U_STATE_TOO_OLD_ERROR => error.StateTooOld,
        c.U_TOO_MANY_ALIASES_ERROR => error.TooManyAliases,
        c.U_ENUM_OUT_OF_SYNC_ERROR => error.EnumerationOutOfSync,
        c.U_INVARIANT_CONVERSION_ERROR => error.InvariantConversion,
        c.U_INVALID_STATE_ERROR => error.InvalidState,
        c.U_COLLATOR_VERSION_MISMATCH => error.CollatorVersionMismatch,
        c.U_USELESS_COLLATOR_ERROR => error.UselessCollator,
        c.U_NO_WRITE_PERMISSION => error.NoWritePermission,
        c.U_INPUT_TOO_LONG_ERROR => error.InputTooLong,
        else => error.UnexpectedIcuError,
    };
}

/// Checks a slice length before passing it to ICU's int32_t APIs.
pub fn length(size: usize) error{InputTooLong}!i32 {
    return std.math.cast(i32, size) orelse error.InputTooLong;
}

