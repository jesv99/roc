const std = @import("std");
const RocStr = @import("str.zig").RocStr;
const always_inline = std.builtin.CallOptions.Modifier.always_inline;

// Signals to the host that the program has panicked
extern fn roc_panic(msg: *const RocStr, tag_id: u32) callconv(.C) void;

pub fn panic_help(msg: []const u8, tag_id: u32) void {
    var str = RocStr.init(msg.ptr, msg.len);
    roc_panic(&str, tag_id);
}

// must export this explicitly because right now it is not used from zig code
pub fn panic(msg: *const RocStr, alignment: u32) callconv(.C) void {
    return @call(.{ .modifier = always_inline }, roc_panic, .{ msg, alignment });
}
