const std = @import("std");
const Uuid = @import("yume").Uuid;

const Self = @This();

yume_version: std.SemanticVersion,
project_name: []u8,
scenes: []Uuid,
default_scene: Uuid,
