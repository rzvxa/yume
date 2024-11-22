// TODO: abstract me!
const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const Mat4 = @import("../math/mod.zig").Mat4;

const VulkanDevice = @import("vulkan/VulkanDevice.zig");
const VulkanPipeline = @import("vulkan/VulkanPipeline.zig");
const FrameInfo = @import("mod.zig").FrameInfo;

const Self = @This();

device: *VulkanDevice,
pipeline: VulkanPipeline,
pipeline_layout: vk.PipelineLayout,

pub fn init(device: *VulkanDevice, render_pass: vk.RenderPass, global_set_layout: vk.DescriptorSetLayout, allocator: Allocator) !Self {
    const pipeline_layout = try createPipelineLayout(device, global_set_layout);
    const pipeline = try createPipeline(device, pipeline_layout, render_pass, allocator);
    return .{
        .device = device,
        .pipeline = pipeline,
        .pipeline_layout = pipeline_layout,
    };
}

pub fn render(self: *const Self, frame_info: *const FrameInfo) void {
    self.pipeline.bind(frame_info.command_buffer);

    std.debug.print("render: {any} {d}\n", .{ &frame_info.global_descriptor_set, &frame_info.global_descriptor_set });
    self.device.device.cmdBindDescriptorSets(
        frame_info.command_buffer,
        .graphics,
        self.pipeline_layout,
        0,
        1,
        @ptrCast(&frame_info.global_descriptor_set),
        0,
        null,
    );

    // TODO Render
}

fn createPipelineLayout(device: *VulkanDevice, global_set_layout: vk.DescriptorSetLayout) !vk.PipelineLayout {
    const push_constant_ranges: [1]vk.PushConstantRange = .{.{
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        .offset = 0,
        .size = @sizeOf(SimplePushConstantData),
    }};

    const descriptor_set_layouts: [1]vk.DescriptorSetLayout = .{global_set_layout};

    const pipeline_layout_create_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = @as(u32, @truncate(descriptor_set_layouts.len)),
        .p_set_layouts = &descriptor_set_layouts,
        .push_constant_range_count = @as(u32, @truncate(push_constant_ranges.len)),
        .p_push_constant_ranges = &push_constant_ranges,
    };

    return try device.device.createPipelineLayout(&pipeline_layout_create_info, null);
}

fn createPipeline(device: *VulkanDevice, layout: vk.PipelineLayout, render_pass: vk.RenderPass, allocator: Allocator) !VulkanPipeline {
    var pipeline_config_info: VulkanPipeline.PipelineConfigInfo = undefined;
    try VulkanPipeline.defaultPipelineConfigInfo(&pipeline_config_info, allocator);
    defer pipeline_config_info.deinit(allocator);
    pipeline_config_info.render_pass = render_pass;
    pipeline_config_info.pipeline_layout = layout;
    return try VulkanPipeline.init(
        device,
        "assets/shaders/simple_shader.vert.spv",
        "assets/shaders/simple_shader.frag.spv",
        &pipeline_config_info,
        allocator,
    );
}

const SimplePushConstantData = struct {
    model_matrix: Mat4 = Mat4.new(1),
    normal_matrix: Mat4 = Mat4.new(1),
};
