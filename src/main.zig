pub const raw = @import("c");
pub const Idna = @import("Idna.zig");
pub const BreakIterator = @import("BreakIterator.zig");
pub const Collator = @import("Collator.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
