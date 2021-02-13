const std = @import("std");
const testing = std.testing;
const expectEqual = testing.expectEqual;
const mem = std.mem;
const Allocator = mem.Allocator;

const level_size = 32;

const INITIAL_SEED = 0xc70f6907;

const InPlace = packed enum(u8) {
    InPlace,
    Clone,
};

const Slot = packed enum(u8) {
    Empty,
    Filled,
    PreviouslyFilled,
};

const MaybeIndexTag = enum {
    index, not_found
};

const MaybeIndex = union(MaybeIndexTag) {
    index: usize, not_found: void
};

fn nextSeed(seed: u64) u64 {
    return seed + 1;
}

// aligmnent of elements. The number (16 or 8) indicates the maximum
// alignment of the key and value. The tag furthermore indicates
// which has the biggest aligmnent. If both are the same, we put
// the key first
const Alignment = packed enum(u8) {
    Align16KeyFirst,
    Align16ValueFirst,
    Align8KeyFirst,
    Align8ValueFirst,

    fn toUsize(self: Alignment) usize {
        switch (self) {
            .Align16KeyFirst => return 16,
            .Align16ValueFirst => return 16,
            .Align8KeyFirst => return 8,
            .Align8ValueFirst => return 8,
        }
    }

    fn keyFirst(self: Alignment) bool {
        switch (self) {
            .Align16KeyFirst => return true,
            .Align16ValueFirst => return false,
            .Align8KeyFirst => return true,
            .Align8ValueFirst => return false,
        }
    }
};

pub const RocDict = extern struct {
    dict_bytes: ?[*]u8,
    dict_entries_len: usize,
    dict_slot_len: usize,

    pub fn empty() RocDict {
        return RocDict{
            .dict_entries_len = 0,
            .dict_slot_len = 0,
            .dict_bytes = null,
        };
    }

    pub fn init(allocator: *Allocator, bytes_ptr: [*]const u8, number_of_slots: usize, number_of_entries: usize, key_size: usize, value_size: usize) RocDict {
        var result = RocDict.allocate(
            allocator,
            InPlace.Clone,
            number_of_slots,
            number_of_entries,
            8,
            key_size,
            value_size,
        );

        @memcpy(result.asU8ptr(), bytes_ptr, number_of_slots);

        return result;
    }

    pub fn deinit(self: RocDict, allocator: *Allocator, key_size: usize, value_size: usize) void {
        if (!self.isEmpty()) {
            const slot_size = slotSize(key_size, value_size);

            const dict_bytes_ptr: [*]u8 = self.dict_bytes orelse unreachable;

            const dict_bytes: []u8 = dict_bytes_ptr[0..(self.dict_slot_len)];
            allocator.free(dict_bytes);
        }
    }

    pub fn allocate(
        allocator: *Allocator,
        result_in_place: InPlace,
        number_of_slots: usize,
        number_of_entries: usize,
        alignment: usize,
        key_size: usize,
        value_size: usize,
    ) RocDict {
        const first_slot = switch (alignment) {
            8 => blk: {
                const slot_size = slotSize(key_size, value_size);

                const length = @sizeOf(usize) + (number_of_slots * slot_size);

                var new_bytes: []align(8) u8 = allocator.alignedAlloc(u8, 8, length) catch unreachable;

                var as_usize_array = @ptrCast([*]usize, new_bytes);
                if (result_in_place == InPlace.InPlace) {
                    as_usize_array[0] = @intCast(usize, number_of_slots);
                } else {
                    const v: isize = std.math.minInt(isize);
                    as_usize_array[0] = @bitCast(usize, v);
                }

                var as_u8_array = @ptrCast([*]u8, new_bytes);
                const first_slot = as_u8_array + @sizeOf(usize);

                break :blk first_slot;
            },
            16 => blk: {
                const slot_size = slotSize(key_size, value_size);

                const length = 2 * @sizeOf(usize) + (number_of_slots * slot_size);

                var new_bytes: []align(16) u8 = allocator.alignedAlloc(u8, 16, length) catch unreachable;

                var as_usize_array = @ptrCast([*]usize, new_bytes);
                if (result_in_place == InPlace.InPlace) {
                    as_usize_array[0] = 0;
                    as_usize_array[1] = @intCast(usize, number_of_slots);
                } else {
                    const v: isize = std.math.minInt(isize);
                    as_usize_array[0] = 0;
                    as_usize_array[1] = @bitCast(usize, v);
                }

                var as_u8_array = @ptrCast([*]u8, new_bytes);
                const first_slot = as_u8_array + 2 * @sizeOf(usize);

                break :blk first_slot;
            },
            else => unreachable,
        };

        return RocDict{
            .dict_bytes = first_slot,
            .dict_slot_len = number_of_slots,
            .dict_entries_len = number_of_entries,
        };
    }

    pub fn reallocate(
        self: RocDict,
        allocator: *Allocator,
        for_level: usize,
        alignment: usize,
        key_width: usize,
        value_width: usize,
    ) RocDict {
        const first_slot = switch (alignment) {
            8 => blk: {
                const slot_size = slotSize(key_width, value_width);
                const number_of_slots = 8 + 16;

                const length = @sizeOf(usize) + (number_of_slots * slot_size);

                var new_bytes: []align(8) u8 = allocator.alignedAlloc(u8, 8, length) catch unreachable;

                var as_usize_array = @ptrCast([*]usize, new_bytes);
                const v: isize = std.math.minInt(isize);
                as_usize_array[0] = @bitCast(usize, v);

                var as_u8_array = @ptrCast([*]u8, new_bytes);
                const first_slot = as_u8_array + @sizeOf(usize);

                break :blk first_slot;
            },
            else => unreachable,
        };

        // transfer the memory

        // number of slots we currently have (before reallocating)
        const number_of_elements = 8;
        const next_number_of_elements = 2 * number_of_elements;

        var source_ptr = self.dict_bytes orelse unreachable;
        var dest_ptr = first_slot;

        var source_offset: usize = 0;
        var dest_offset: usize = 0;
        @memcpy(dest_ptr + dest_offset, source_ptr + source_offset, number_of_elements * key_width);

        source_offset += number_of_elements * key_width;
        dest_offset += number_of_elements * key_width + (next_number_of_elements * key_width);
        @memcpy(dest_ptr + dest_offset, source_ptr + source_offset, number_of_elements * value_width);

        source_offset += number_of_elements * value_width;
        dest_offset += number_of_elements * value_width + (next_number_of_elements * value_width);
        @memcpy(dest_ptr + dest_offset, source_ptr + source_offset, number_of_elements * @sizeOf(Slot));

        var i: usize = 0;
        while (i < next_number_of_elements) : (i += 1) {
            (dest_ptr + dest_offset + number_of_elements * @sizeOf(Slot))[i] = @enumToInt(Slot.Empty);
        }

        return RocDict{
            .dict_bytes = first_slot,
            .dict_slot_len = 8 + 16,
            .dict_entries_len = self.dict_entries_len,
        };
    }

    pub fn asU8ptr(self: RocDict) [*]u8 {
        return @ptrCast([*]u8, self.dict_bytes);
    }

    pub fn contains(self: RocDict, key_size: usize, key_ptr: *const c_void, hash_code: u64) bool {
        return false;
    }

    pub fn len(self: RocDict) usize {
        return self.dict_entries_len;
    }

    pub fn isEmpty(self: RocDict) bool {
        return self.len() == 0;
    }

    pub fn refcountIsOne(self: RocDict) bool {
        return false;
    }

    pub fn makeUnique(self: RocDict, allocator: *Allocator, in_place: InPlace, alignment: Alignment, key_width: usize, value_width: usize, inc_key: Inc, inc_value: Inc) RocDict {
        if (self.isEmpty()) {
            return self;
        }

        if (self.refcountIsOne()) {
            return self;
        }

        // unfortunately, we have to clone

        var new_dict = RocDict.allocate(allocator, in_place, 8, self.dict_entries_len, alignment.toUsize(), key_width, value_width);

        var old_bytes: [*]u8 = @ptrCast([*]u8, self.dict_bytes);
        var new_bytes: [*]u8 = @ptrCast([*]u8, new_dict.dict_bytes);

        const number_of_bytes = 8 * (@sizeOf(Slot) + key_width + value_width);
        @memcpy(new_bytes, old_bytes, number_of_bytes);

        // we copied potentially-refcounted values; make sure to increment
        const size = new_dict.dict_entries_len;
        const n = new_dict.dict_slot_len;
        var i: usize = 0;

        i = 0;
        while (i < size) : (i += 1) {
            inc_key(new_dict.getKey(n, i, alignment, key_width, value_width));
        }

        i = 0;
        while (i < size) : (i += 1) {
            inc_value(new_dict.getValue(n, i, alignment, key_width, value_width));
        }

        return new_dict;
    }

    fn getSlot(self: *const RocDict, capacity: usize, index: usize, key_width: usize, value_width: usize) Slot {
        const offset = capacity * (key_width + value_width) + index * @sizeOf(Slot);

        if (self.dict_bytes) |u8_ptr| {
            return @intToEnum(Slot, u8_ptr[offset]);
        } else {
            unreachable;
        }
    }

    fn setSlot(self: *RocDict, capacity: usize, index: usize, key_width: usize, value_width: usize, slot: Slot) void {
        const offset = capacity * (key_width + value_width) + index * @sizeOf(Slot);

        if (self.dict_bytes) |u8_ptr| {
            u8_ptr[offset] = @enumToInt(slot);
        } else {
            unreachable;
        }
    }

    fn setKey(self: *RocDict, capacity: usize, index: usize, alignment: Alignment, key_width: usize, value_width: usize, data: Opaque) void {
        const offset = blk: {
            if (alignment.keyFirst()) {
                break :blk (index * key_width);
            } else {
                break :blk (capacity * value_width) + (index * key_width);
            }
        };

        if (self.dict_bytes) |u8_ptr| {
            const source = data orelse unreachable;
            @memcpy(u8_ptr + offset, source, key_width);
        } else {
            unreachable;
        }
    }

    fn getKey(self: *const RocDict, capacity: usize, index: usize, alignment: Alignment, key_width: usize, value_width: usize) Opaque {
        const offset = blk: {
            if (alignment.keyFirst()) {
                break :blk (index * key_width);
            } else {
                break :blk (capacity * value_width) + (index * key_width);
            }
        };

        if (self.dict_bytes) |u8_ptr| {
            return u8_ptr + offset;
        } else {
            unreachable;
        }
    }

    fn setValue(self: *RocDict, capacity: usize, index: usize, alignment: Alignment, key_width: usize, value_width: usize, data: Opaque) void {
        const offset = blk: {
            if (alignment.keyFirst()) {
                break :blk (capacity * key_width) + (index * value_width);
            } else {
                break :blk (index * value_width);
            }
        };

        if (self.dict_bytes) |u8_ptr| {
            const source = data orelse unreachable;
            @memcpy(u8_ptr + offset, source, key_width);
        } else {
            unreachable;
        }
    }

    fn getValue(self: *const RocDict, capacity: usize, index: usize, alignment: Alignment, key_width: usize, value_width: usize) Opaque {
        const offset = blk: {
            if (alignment.keyFirst()) {
                break :blk (capacity * key_width) + (index * value_width);
            } else {
                break :blk (index * value_width);
            }
        };

        if (self.dict_bytes) |u8_ptr| {
            return u8_ptr + offset;
        } else {
            unreachable;
        }
    }

    fn findIndex(self: *const RocDict, capacity: usize, seed: u64, alignment: Alignment, key: Opaque, key_width: usize, value_width: usize, hash_fn: HashFn, is_eq: EqFn) MaybeIndex {
        if (self.isEmpty()) {
            return MaybeIndex.not_found;
        }

        const n = capacity;
        // hash the key, and modulo by the maximum size
        // (so we get an in-bounds index)
        const hash = hash_fn(seed, key);
        const index = hash % n;

        switch (self.getSlot(n, index, key_width, value_width)) {
            Slot.Empty, Slot.PreviouslyFilled => {
                return MaybeIndex.not_found;
            },
            Slot.Filled => {
                // is this the same key, or a new key?
                const current_key = self.getKey(n, index, alignment, key_width, value_width);

                if (is_eq(key, current_key)) {
                    return MaybeIndex{ .index = index };
                } else {
                    unreachable;
                }
            },
        }
    }
};

// Dict.empty
pub fn dictEmpty() callconv(.C) RocDict {
    return RocDict.empty();
}

pub fn slotSize(key_size: usize, value_size: usize) usize {
    return @sizeOf(Slot) + key_size + value_size;
}

// Dict.len
pub fn dictLen(dict: RocDict) callconv(.C) usize {
    return dict.dict_entries_len;
}

// commonly used type aliases
const Opaque = ?[*]u8;
const HashFn = fn (u64, ?[*]u8) callconv(.C) u64;
const EqFn = fn (?[*]u8, ?[*]u8) callconv(.C) bool;

const Inc = fn (?[*]u8) callconv(.C) void;
const Dec = fn (?[*]u8) callconv(.C) void;

// Dict.insert : Dict k v, k, v -> Dict k v
pub fn dictInsert(input: RocDict, alignment: Alignment, key: Opaque, key_width: usize, value: Opaque, value_width: usize, hash_fn: HashFn, is_eq: EqFn, inc_key: Inc, dec_key: Dec, inc_value: Inc, dec_value: Dec, output: *RocDict) callconv(.C) void {
    const n: usize = std.math.max(input.dict_slot_len, 8);
    const seed: u64 = INITIAL_SEED;

    var result: RocDict = blk: {
        if (input.isEmpty()) {
            var temp = RocDict.allocate(
                std.heap.c_allocator,
                InPlace.Clone,
                n, // number_of_slots,
                0, // number_of_entries,
                alignment.toUsize(),
                key_width,
                value_width,
            );

            {
                var i: usize = 0;
                while (i < n) {
                    temp.setSlot(n, i, key_width, value_width, Slot.Empty);
                    i += 1;
                }
            }

            break :blk temp;
        } else {
            const in_place = InPlace.Clone;

            var temp = input.makeUnique(std.heap.c_allocator, in_place, alignment, key_width, value_width, inc_key, inc_value);

            break :blk temp;
            // break :blk input;
        }
    };

    // hash the key, and modulo by the maximum size
    // (so we get an in-bounds index)
    const hash = hash_fn(seed, key);
    var index = hash % n;

    var current_level: usize = 1;
    var current_level_size: usize = 8;
    var next_level_size: usize = 16;

    while (true) {
        switch (result.getSlot(n, index, key_width, value_width)) {
            Slot.Empty, Slot.PreviouslyFilled => {
                result.setSlot(n, index, key_width, value_width, Slot.Filled);
                result.setKey(n, index, alignment, key_width, value_width, key);
                result.setValue(n, index, alignment, key_width, value_width, value);

                result.dict_entries_len += 1;
                break;
            },
            Slot.Filled => {
                // is this the same key, or a new key?
                const current_key = result.getKey(n, index, alignment, key_width, value_width);

                if (is_eq(key, current_key)) {
                    // we will override the old value, but first have to decrement its refcount
                    const current_value = result.getValue(n, index, alignment, key_width, value_width);
                    dec_value(current_value);

                    // we must consume the key argument!
                    dec_key(key);

                    result.setValue(n, index, alignment, key_width, value_width, value);
                    break;
                } else {
                    const next_layer_exists = false;

                    if (next_layer_exists) {
                        // rehash key with next seed
                        const next_level_seed = nextSeed(seed);
                        const next_level_index = hash_fn(next_level_seed, key) % 16;

                        index = (current_level_size + next_level_index);
                        current_level += 1;

                        current_level_size *= 2;
                        next_level_size *= 2;

                        continue;
                    } else {
                        // 8, 16, 32 ..
                        result = result.reallocate(std.heap.c_allocator, current_level, alignment.toUsize(), key_width, value_width);

                        const next_level_seed = nextSeed(seed);
                        const next_level_index = hash_fn(next_level_seed, key) % 16;

                        const new_index = (current_level_size + next_level_index);

                        const capacity = 8 + 16;
                        result.setSlot(capacity, new_index, key_width, value_width, Slot.Filled);
                        result.setKey(capacity, new_index, alignment, key_width, value_width, key);
                        result.setValue(capacity, new_index, alignment, key_width, value_width, value);

                        result.dict_entries_len += 1;
                        break;
                    }
                }
            },
        }
    }

    // write result into pointer
    output.* = result;
}

// { ptr, length, level: u8 }
// [ key1 .. key8, value1, ...

// Dict.remove : Dict k v, k -> Dict k v
pub fn dictRemove(input: RocDict, alignment: Alignment, key: Opaque, key_width: usize, value_width: usize, hash_fn: HashFn, is_eq: EqFn, inc_key: Inc, dec_key: Dec, inc_value: Inc, dec_value: Dec, output: *RocDict) callconv(.C) void {
    const capacity: usize = input.dict_slot_len;
    const n = capacity;
    const seed: u64 = INITIAL_SEED;

    switch (input.findIndex(capacity, seed, alignment, key, key_width, value_width, hash_fn, is_eq)) {
        MaybeIndex.not_found => {
            // the key was not found; we're done
            output.* = input;
            return;
        },
        MaybeIndex.index => |index| {
            // TODO make sure input is unique (or duplicate otherwise)
            var dict = input;

            dict.setSlot(n, index, key_width, value_width, Slot.PreviouslyFilled);
            const old_key = dict.getKey(n, index, alignment, key_width, value_width);
            const old_value = dict.getValue(n, index, alignment, key_width, value_width);

            dec_key(old_key);
            dec_value(old_value);

            dict.dict_entries_len -= 1;

            output.* = dict;
        },
    }
}

// Dict.contains : Dict k v, k -> Bool
pub fn dictContains(dict: RocDict, alignment: Alignment, key: Opaque, key_width: usize, value_width: usize, hash_fn: HashFn, is_eq: EqFn) callconv(.C) bool {
    const capacity: usize = dict.dict_slot_len;
    const seed: u64 = INITIAL_SEED;

    switch (dict.findIndex(capacity, seed, alignment, key, key_width, value_width, hash_fn, is_eq)) {
        MaybeIndex.not_found => {
            return false;
        },
        MaybeIndex.index => |_| {
            return true;
        },
    }
}

// Dict.get : Dict k v, k -> { flag: bool, value: Opaque }
pub fn dictGet(dict: RocDict, alignment: Alignment, key: Opaque, key_width: usize, value_width: usize, hash_fn: HashFn, is_eq: EqFn, inc_value: Inc) callconv(.C) extern struct { value: Opaque, flag: bool } {
    const capacity: usize = dict.dict_slot_len;
    const n: usize = capacity;
    const seed: u64 = INITIAL_SEED;

    switch (dict.findIndex(capacity, seed, alignment, key, key_width, value_width, hash_fn, is_eq)) {
        MaybeIndex.not_found => {
            return .{ .flag = false, .value = null };
        },
        MaybeIndex.index => |index| {
            var value = dict.getValue(n, index, alignment, key_width, value_width);
            inc_value(value);
            return .{ .flag = true, .value = value };
        },
    }
}

// Dict.elementsRc
// increment or decrement all dict elements (but not the dict's allocation itself)
pub fn elementsRc(dict: RocDict, alignment: Alignment, key_width: usize, value_width: usize, modify_key: Inc, modify_value: Inc) callconv(.C) void {
    const size = dict.dict_entries_len;
    const n = dict.dict_slot_len;
    var i: usize = 0;

    i = 0;
    while (i < size) : (i += 1) {
        modify_key(dict.getKey(n, i, alignment, key_width, value_width));
    }

    i = 0;
    while (i < size) : (i += 1) {
        modify_value(dict.getValue(n, i, alignment, key_width, value_width));
    }
}

test "RocDict.init() contains nothing" {
    const key_size = @sizeOf(usize);
    const value_size = @sizeOf(usize);

    const dict = dictEmpty();

    expectEqual(false, dict.contains(4, @ptrCast(*const c_void, &""), 9));
}
