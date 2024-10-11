const vk = @import("vulkan");

const VulkanDevice = @import("VulkanDevice.zig");

const Self = @This();

device: *VulkanDevice,

graphics_pipeline: vk.Pipeline,

vert_shader_module: vk.ShaderModule,
frag_shader_module: vk.ShaderModule,

pub fn init(
    device: *VulkanDevice,
    vert_path: []const u8,
    frag_path: []const u8,
    config_info: *const PipelineConfigInfo,
) Self {
    _ = vert_path;
    _ = frag_path;
    _ = config_info;
    return .{
        .device = device,
    };
}

pub inline fn defaultPipelineConfigInfo(config_info: *PipelineConfigInfo) void {
    config_info.viewport_info = .{
        .viewport_count = 1,
        .p_viewports = null,
        .scissor_count = 1,
        .p_scissors = null,
    };
    config_info.input_assembly_info = .{
        .topology = .triangle_list,
        .primitive_restart_enable = vk.TRUE,
    };
    config_info.rasterization_info = .{
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .line_width = 1,
        .cull_mode = .none,
        .front_face = .clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
    };
    config_info.multisample_info = .{
        .sample_shading_enable = vk.TRUE,
        .rasterization_samples = .@"1_bit",
        .min_sample_shading = 1,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };
    config_info.color_blend_attachment = .{
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        .blend_enable = vk.FALSE,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
    };
    config_info.color_blend_info = .{
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = &config_info.color_blend_attachment,
        .blend_constants = .{ 0, 0, 0, 0 },
    };
    config_info.depth_stencil_info = .{
        .depth_test_enable = vk.TRUE,
        .depth_write_enable = vk.TRUE,
        .depth_compare_op = .less,
        .depth_bounds_test_enable = vk.FALSE,
        .min_depth_bounds = 0,
        .max_depth_bounds = 1,
        .stencil_test_enable = vk.FALSE,
        .front = .{},
        .back = .{},
    };

    config_info.dynamic_state_enables = .{ .viewport, .scissor };
    config_info.dyncamic_state_info = .{
        .flags = .{},
        .dynamic_state_count = @as(u32, @truncate(config_info.dynamic_state_enables.len)),
        .p_dynamic_states = config_info.dynamic_state_enables.ptr,
    };


    config_info.binding_descriptions = 
}

pub const PipelineConfigInfo = struct {
    binding_descriptions: []vk.VertexInputBindingDescription,
    attribute_descriptions: []vk.VertexInputAttributeDescription,
    viewport_info: vk.PipelineViewportStateCreateInfo,
    input_assembly_info: vk.PipelineInputAssemblyStateCreateInfo,
    rasterization_info: vk.PipelineRasterizationStateCreateInfo,
    multisample_info: vk.PipelineMultisampleStateCreateInfo,
    color_blend_attachment: vk.PipelineColorBlendAttachmentState,
    color_blend_info: vk.PipelineColorBlendStateCreateInfo,
    depth_stencil_info: vk.PipelineDepthStencilStateCreateInfo,
    dynamic_state_enables: []vk.DynamicState,
    dyncamic_state_info: vk.PipelineDynamicStateCreateInfo,
    pipeline_layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
    subpass: u32,
};
