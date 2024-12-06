const std = @import("std");
const mem = std.mem;
const re = @cImport(@cInclude("regex.h"));
// const SIZEOF_REGEX_T = @sizeOf(re.regex_t);
// const ALIGNOF_REGEX_T = @alignOf(re.regex_t);
const SIZEOF_REGEX_T = 64;
const ALIGNOF_REGEX_T = 8;

const RegexError = error{
    CompilationFailed,
    OutOfMemory,
};

/// return preg
/// Do not forget to re.regfree(preg);
fn regComp(slice: []u8, pattern: []const u8) !*re.regex_t {
    const preg: *re.regex_t = @ptrCast(slice.ptr);
    if (re.regcomp(preg, @ptrCast(pattern.ptr), 0) != 0)
        return RegexError.CompilationFailed;
    return preg;
}

pub fn match(allocator: mem.Allocator, pattern: []const u8, target: []u8) !?usize {
    const slice = try allocator.alignedAlloc(u8, ALIGNOF_REGEX_T, SIZEOF_REGEX_T);
    defer allocator.free(slice);

    const preg = try regComp(slice, pattern);
    defer re.regfree(preg);

    var matches: [5]re.regmatch_t = undefined;
    if (re.regexec(preg, @ptrCast(target.ptr), matches.len, &matches, 0) != 0)
        return null;
    const rlength: usize = @intCast(matches[0].rm_eo - matches[0].rm_so);
    return rlength;
}

pub fn sub(allocator: mem.Allocator, pattern: []const u8, replacement: []const u8, target: []u8) !void {
    const slice = try allocator.alignedAlloc(u8, ALIGNOF_REGEX_T, SIZEOF_REGEX_T);
    defer allocator.free(slice);

    const preg = try regComp(slice, pattern);
    defer re.regfree(preg);

    var matches: [5]re.regmatch_t = undefined;
    if (re.regexec(preg, @ptrCast(target.ptr), matches.len, &matches, 0) != 0)
        return;

    const place = matches[0];
    try replace(allocator, place, replacement, target);
}

fn replace(allocator: mem.Allocator, place: re.regmatch_t, replacement: []const u8, target: []u8) !void {
    const so: usize = @intCast(place.rm_so);
    const eo: usize = @intCast(place.rm_eo);
    const rep_end = so + replacement.len;
    const total = rep_end + (target.len - eo);
    var tmp = try allocator.alloc(u8, 0x1000);
    defer allocator.free(tmp);
    @memset(tmp, 0);

    if (so + replacement.len > target.len)
        return RegexError.OutOfMemory;
    if (tmp.len < total)
        return RegexError.OutOfMemory;

    mem.copyForwards(u8, tmp, target[0..so]);
    mem.copyForwards(u8, tmp[so..rep_end], replacement);
    mem.copyForwards(u8, tmp[rep_end .. rep_end + (target.len - eo)], target[eo..target.len]);

    @memset(target, 0);
    mem.copyForwards(u8, target, tmp[0..target.len]);
}

comptime {
    @export(&sub, .{ .name = "sub", .linkage = .internal });
    @export(&match, .{ .name = "match", .linkage = .internal });
}
