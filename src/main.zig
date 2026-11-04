pub const raw = @import("c");
pub const Idna = @import("Idna.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
