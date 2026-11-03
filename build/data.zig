/// The ICU data file selected by build/icu.zig, such as icudt78l.dat.
const bytes = @embedFile("icudata");

/// The embedded data, aligned to 16 bytes as required by ICU's data loader.
const data: @TypeOf(bytes.*) align(16) = bytes.*;

comptime {
    // Export the name ICU expects, such as icudt78_dat for ICU 78.
    @export(&data, .{ .name = @import("data_options").symbol });
}
