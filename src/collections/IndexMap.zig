pub fn IndexMap(comptime K: type, comptime V: type) type {
    _ = K;
    return @import("std").ArrayList(V);
}
