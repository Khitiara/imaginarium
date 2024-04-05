pub const ChecksumErrors = error{invalid_checksum};

pub fn add_checksum(comptime T: type, comptime Self: type, comptime use_length_field: bool) type {
    return struct {
        pub fn compute_checksum(self: Self) u8 {
            const len = if (use_length_field and @hasField(T, "length")) self.length else @sizeOf(T);
            const bytes: []const u8 = @as([*]const u8, @ptrCast(self))[0..len];
            var sum: u8 = 0;
            for (bytes) |b| {
                sum +%= b;
            }
            return sum;
        }

        pub fn verify_checksum(self: Self) ChecksumErrors!void {
            if (compute_checksum(self) != 0) {
                return error.invalid_checksum;
            }
        }
    };
}

pub fn add_acpi_checksum(comptime T: type) type {
    return struct {
        pub fn compute_checksum(self: *const T) u8 {
            const len = self.header.length;
            const bytes: []const u8 = @as([*]const u8, @ptrCast(self))[0..len];
            var sum: u8 = 0;
            for (bytes) |b| {
                sum +%= b;
            }
            return sum;
        }

        pub fn verify_checksum(self: *const T) ChecksumErrors!void {
            if (compute_checksum(self) != 0) {
                return error.invalid_checksum;
            }
        }
    };
}
