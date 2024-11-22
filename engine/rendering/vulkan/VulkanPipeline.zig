const std = @import("std");
const vk = @import("vulkan");

const assert = @import("../../assert.zig").assert;
const Allocator = std.mem.Allocator;

const VulkanDevice = @import("VulkanDevice.zig");
const Vertex = @import("../Vertex.zig");

const Self = @This();

device: *VulkanDevice,

graphics_pipeline: vk.Pipeline,

vert_shader: vk.ShaderModule,
frag_shader: vk.ShaderModule,

pub fn init(
    device: *VulkanDevice,
    vert_path: []const u8,
    frag_path: []const u8,
    config_info: *const PipelineConfigInfo,
    allocator: Allocator,
) !Self {
    assert(
        config_info.pipeline_layout != .null_handle,
        "Cannot create `VulkanPipeline`, no `pipeline_layout` provided in the `config_info`",
        .{},
    );
    assert(
        config_info.render_pass != .null_handle,
        "Cannot create `VulkanPipeline`, no `render_pass` provided in the `config_info`",
        .{},
    );
    const vert_code = try readFile(vert_path, allocator);
    const frag_code = try readFile(frag_path, allocator);
    const vert_shader = try createShaderModule(device, vert_code);
    const frag_shader = try createShaderModule(device, frag_code);

    const stages: [2]vk.PipelineShaderStageCreateInfo = .{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert_shader,
            .p_name = "main",
            .flags = .{},
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag_shader,
            .p_name = "main",
            .flags = .{},
        },
    };

    const binding_descriptions = &config_info.binding_descriptions;
    const attribute_descriptions = &config_info.attribute_descriptions;

    const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
        .vertex_attribute_description_count = @as(u32, @truncate(attribute_descriptions.len)),
        .p_vertex_attribute_descriptions = attribute_descriptions.ptr,

        .vertex_binding_description_count = @as(u32, @truncate(binding_descriptions.len)),
        .p_vertex_binding_descriptions = binding_descriptions.ptr,
    };

    const pipeline_info = vk.GraphicsPipelineCreateInfo{
        .stage_count = 2,
        .p_stages = &stages,
        .p_vertex_input_state = &vertex_input_info,
        .p_input_assembly_state = &config_info.input_assembly_info,
        .p_viewport_state = &config_info.viewport_info,
        .p_rasterization_state = &config_info.rasterization_info,
        .p_multisample_state = &config_info.multisample_info,
        .p_color_blend_state = &config_info.color_blend_info,
        .p_depth_stencil_state = &config_info.depth_stencil_info,
        .p_dynamic_state = &config_info.dyncamic_state_info,

        .layout = config_info.pipeline_layout,
        .render_pass = config_info.render_pass,
        .subpass = config_info.subpass,

        .base_pipeline_index = -1,
        .base_pipeline_handle = .null_handle,
    };

    var graphics_pipeline: [1]vk.Pipeline = undefined;
    if (try device.device.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_info), null, &graphics_pipeline) != .success) {
        return error.FailedToCreateGraphicsPipeline;
    }

    return .{
        .device = device,
        .graphics_pipeline = graphics_pipeline[0],
        .vert_shader = vert_shader,
        .frag_shader = frag_shader,
    };
}

pub inline fn defaultPipelineConfigInfo(config_info: *PipelineConfigInfo, allocator: Allocator) !void {
    var dynamic_state_enables = try allocator.alloc(vk.DynamicState, 2);
    dynamic_state_enables[0] = .viewport;
    dynamic_state_enables[1] = .scissor;
    config_info.* = .{
        .viewport_info = .{
            .viewport_count = 1,
            .p_viewports = null,
            .scissor_count = 1,
            .p_scissors = null,
        },
        .input_assembly_info = .{
            .topology = .triangle_list,
            .primitive_restart_enable = vk.TRUE,
        },
        .rasterization_info = .{
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = .{},
            .front_face = .clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        },
        .multisample_info = .{
            .sample_shading_enable = vk.TRUE,
            .rasterization_samples = .{ .@"1_bit" = true },
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        },
        .color_blend_attachment = .{
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
            .blend_enable = vk.FALSE,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
        },
        .color_blend_info = .{
            .logic_op_enable = vk.FALSE,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = &.{config_info.color_blend_attachment},
            .blend_constants = .{ 0, 0, 0, 0 },
        },
        .depth_stencil_info = .{
            .depth_test_enable = vk.TRUE,
            .depth_write_enable = vk.TRUE,
            .depth_compare_op = .less,
            .depth_bounds_test_enable = vk.FALSE,
            .min_depth_bounds = 0,
            .max_depth_bounds = 1,
            .stencil_test_enable = vk.FALSE,
            .front = .{
                .fail_op = .keep,
                .pass_op = .keep,
                .depth_fail_op = .keep,
                .compare_op = .never,
                .compare_mask = 0,
                .write_mask = 0,
                .reference = 0,
            },
            .back = .{
                .fail_op = .keep,
                .pass_op = .keep,
                .depth_fail_op = .keep,
                .compare_op = .never,
                .compare_mask = 0,
                .write_mask = 0,
                .reference = 0,
            },
        },
        .dynamic_state_enables = dynamic_state_enables,
        .dyncamic_state_info = .{
            .flags = .{},
            .dynamic_state_count = @as(u32, @truncate(config_info.dynamic_state_enables.len)),
            .p_dynamic_states = config_info.dynamic_state_enables.ptr,
        },

        .binding_descriptions = try Vertex.getBindingDescriptions(allocator),
        .attribute_descriptions = try Vertex.getAttributeDescriptions(allocator),
    };
}

pub inline fn bind(self: *const Self, command_buffer: vk.CommandBuffer) void {
    self.device.device.cmdBindPipeline(command_buffer, .graphics, self.graphics_pipeline);
}

var asset_root_directory: ?[]const u8 = null;
inline fn readFile(path: []const u8, allocator: Allocator) ![]align(4) const u8 {
    if (asset_root_directory == null) {
        asset_root_directory = try std.fs.cwd().realpathAlloc(allocator, ".");
    }
    const abs_path = try std.fs.path.join(allocator, &.{ asset_root_directory.?, path });
    defer allocator.free(abs_path);
    std.debug.print("{s}\n", .{abs_path});
    const file = try std.fs.cwd().openFile(abs_path, .{ .mode = .read_only });
    const stat = try file.stat();
    const buffer: []align(4) u8 = try allocator.allocWithOptions(u8, stat.size - stat.size % 4, 4, null);
    _ = try file.readAll(buffer);
    return buffer;
}

fn createShaderModule(device: *VulkanDevice, code: []align(4) const u8) !vk.ShaderModule {
    const create_info = vk.ShaderModuleCreateInfo{
        .code_size = code.len,
        .p_code = @alignCast(@ptrCast(code)),
    };
    return try device.device.createShaderModule(&create_info, null);
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
    pipeline_layout: vk.PipelineLayout = .null_handle,
    render_pass: vk.RenderPass = .null_handle,
    subpass: u32 = 0,
    pub fn deinit(self: *PipelineConfigInfo, allocator: Allocator) void {
        allocator.free(self.binding_descriptions);
        allocator.free(self.attribute_descriptions);
        allocator.free(self.dynamic_state_enables);
    }
};
