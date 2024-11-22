const vk = @import("vulkan");

const yume = @import("../root.zig");
const Camera = @import("../components/Camera.zig");

const Vec4 = yume.Vec4;
const Mat4 = yume.Mat4;

pub const GlobalUbo = struct {
    projection: Mat4 = Mat4.scalar(1),
    view: Mat4 = Mat4.scalar(1),
    ambient_light_color: Vec4 = Vec4.new(1, 1, 1, 0.02),
};

pub const FrameInfo = struct {
    index: usize,
    time: f32,
    command_buffer: vk.CommandBuffer, // abstract me
    camera: *Camera,
    global_descriptor_set: vk.DescriptorSet, // abstract me
};
