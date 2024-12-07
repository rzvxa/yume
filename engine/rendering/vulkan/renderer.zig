const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");
const shaders = @import("../../shaders/builtin.zig");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const Allocator = std.mem.Allocator;

const Window = @import("../../window/Window.zig");

const Vertex = struct {
    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };

    pos: [2]f32,
    color: [3]f32,
};

const vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0, 0, 1 } },
};

pub fn Renderer() type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        extent: vk.Extent2D,
        window: *Window,
        gctx: GraphicsContext,
        swapchain: Swapchain,
        pipeline_layout: vk.PipelineLayout,
        render_pass: vk.RenderPass,
        pipeline: vk.Pipeline,
        framebuffers: []vk.Framebuffer,
        pool: vk.CommandPool,
        buffer: vk.Buffer,
        memory: vk.DeviceMemory,
        cmdbufs: []vk.CommandBuffer,

        pub fn init(window: *Window, allocator: Allocator) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .extent = vk.Extent2D{ .width = 800, .height = 600 },
                .window = window,
                .gctx = GraphicsContext.init(allocator, window.title, window.window) catch return error.FailedToInitializeGraphicsContext,
                .swapchain = try Swapchain.init(&self.gctx, allocator, self.extent),
                .pipeline_layout = try self.gctx.dev.createPipelineLayout(&.{
                    .flags = .{},
                    .set_layout_count = 0,
                    .p_set_layouts = undefined,
                    .push_constant_range_count = 0,
                    .p_push_constant_ranges = undefined,
                }, null),
                .render_pass = try createRenderPass(&self.gctx, self.swapchain),
                .pipeline = try createPipeline(&self.gctx, self.pipeline_layout, self.render_pass),
                .framebuffers = try createFramebuffers(&self.gctx, allocator, self.render_pass, self.swapchain),
                .pool = try self.gctx.dev.createCommandPool(&.{
                    .queue_family_index = self.gctx.graphics_queue.family,
                }, null),
                .buffer = try self.gctx.dev.createBuffer(&.{
                    .size = @sizeOf(@TypeOf(vertices)),
                    .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
                    .sharing_mode = .exclusive,
                }, null),
                .memory = try self.gctx.allocate(self.gctx.dev.getBufferMemoryRequirements(self.buffer), .{ .device_local_bit = true }),
                .cmdbufs = undefined,
            };
            std.log.debug("Using device: {s}", .{self.gctx.deviceName()});

            try self.gctx.dev.bindBufferMemory(self.buffer, self.memory, 0);
            try self.uploadVertices();

            self.cmdbufs = try self.createCommandBuffers();

            return self;
        }

        pub fn deinit(self: *Self) void {
            destroyCommandBuffers(&self.gctx, self.pool, self.allocator, self.cmdbufs);
            self.gctx.dev.freeMemory(self.memory, null);
            self.gctx.dev.destroyBuffer(self.buffer, null);
            self.gctx.dev.destroyCommandPool(self.pool, null);
            destroyFramebuffers(&self.gctx, self.allocator, self.framebuffers);
            self.gctx.dev.destroyPipeline(self.pipeline, null);
            self.gctx.dev.destroyRenderPass(self.render_pass, null);
            self.gctx.dev.destroyPipelineLayout(self.pipeline_layout, null);
            self.swapchain.deinit();
            self.gctx.deinit();
        }

        pub fn render(self: *Self) !void {
            const allocator = self.allocator;
            const size = self.window.getFramebufferSize();
            const w = size.width;
            const h = size.height;

            const cmdbuf = self.cmdbufs[self.swapchain.image_index];

            const state = self.swapchain.present(cmdbuf) catch |err| switch (err) {
                error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
                else => |narrow| return narrow,
            };

            if (state == .suboptimal or self.extent.width != @as(u32, @intCast(w)) or self.extent.height != @as(u32, @intCast(h))) {
                self.extent.width = @intCast(w);
                self.extent.height = @intCast(h);
                try self.swapchain.recreate(self.extent);

                destroyFramebuffers(&self.gctx, allocator, self.framebuffers);
                self.framebuffers = try createFramebuffers(&self.gctx, allocator, self.render_pass, self.swapchain);

                destroyCommandBuffers(&self.gctx, self.pool, allocator, self.cmdbufs);
                self.cmdbufs = try self.createCommandBuffers();
            }

            glfw.pollEvents();
        }

        fn uploadVertices(self: *Self) !void {
            const staging_buffer = try self.gctx.dev.createBuffer(&.{
                .size = @sizeOf(@TypeOf(vertices)),
                .usage = .{ .transfer_src_bit = true },
                .sharing_mode = .exclusive,
            }, null);
            defer self.gctx.dev.destroyBuffer(staging_buffer, null);
            const mem_reqs = self.gctx.dev.getBufferMemoryRequirements(staging_buffer);
            const staging_memory = try self.gctx.allocate(mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
            defer self.gctx.dev.freeMemory(staging_memory, null);
            try self.gctx.dev.bindBufferMemory(staging_buffer, staging_memory, 0);

            {
                const data = try self.gctx.dev.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
                defer self.gctx.dev.unmapMemory(staging_memory);

                const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(data));
                @memcpy(gpu_vertices, vertices[0..]);
            }

            try copyBuffer(&self.gctx, self.pool, self.buffer, staging_buffer, @sizeOf(@TypeOf(vertices)));
        }

        fn copyBuffer(gc: *const GraphicsContext, pool: vk.CommandPool, dst: vk.Buffer, src: vk.Buffer, size: vk.DeviceSize) !void {
            var cmdbuf_handle: vk.CommandBuffer = undefined;
            try gc.dev.allocateCommandBuffers(&.{
                .command_pool = pool,
                .level = .primary,
                .command_buffer_count = 1,
            }, @ptrCast(&cmdbuf_handle));
            defer gc.dev.freeCommandBuffers(pool, 1, @ptrCast(&cmdbuf_handle));

            const cmdbuf = GraphicsContext.CommandBuffer.init(cmdbuf_handle, gc.dev.wrapper);

            try cmdbuf.beginCommandBuffer(&.{
                .flags = .{ .one_time_submit_bit = true },
            });

            const region = vk.BufferCopy{
                .src_offset = 0,
                .dst_offset = 0,
                .size = size,
            };
            cmdbuf.copyBuffer(src, dst, 1, @ptrCast(&region));

            try cmdbuf.endCommandBuffer();

            const si = vk.SubmitInfo{
                .command_buffer_count = 1,
                .p_command_buffers = (&cmdbuf.handle)[0..1],
                .p_wait_dst_stage_mask = undefined,
            };
            try gc.dev.queueSubmit(gc.graphics_queue.handle, 1, @ptrCast(&si), .null_handle);
            try gc.dev.queueWaitIdle(gc.graphics_queue.handle);
        }

        fn createCommandBuffers(self: *Self) ![]vk.CommandBuffer {
            const cmdbufs = try self.allocator.alloc(vk.CommandBuffer, self.framebuffers.len);
            errdefer self.allocator.free(cmdbufs);

            try self.gctx.dev.allocateCommandBuffers(&.{
                .command_pool = self.pool,
                .level = .primary,
                .command_buffer_count = @intCast(cmdbufs.len),
            }, cmdbufs.ptr);
            errdefer self.gctx.dev.freeCommandBuffers(self.pool, @intCast(cmdbufs.len), cmdbufs.ptr);

            const clear = vk.ClearValue{
                .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
            };

            const viewport = vk.Viewport{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(self.extent.width),
                .height = @floatFromInt(self.extent.height),
                .min_depth = 0,
                .max_depth = 1,
            };

            const scissor = vk.Rect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.extent,
            };

            for (cmdbufs, self.framebuffers) |cmdbuf, framebuffer| {
                try self.gctx.dev.beginCommandBuffer(cmdbuf, &.{});

                self.gctx.dev.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&viewport));
                self.gctx.dev.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&scissor));

                // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
                const render_area = vk.Rect2D{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = self.extent,
                };

                self.gctx.dev.cmdBeginRenderPass(cmdbuf, &.{
                    .render_pass = self.render_pass,
                    .framebuffer = framebuffer,
                    .render_area = render_area,
                    .clear_value_count = 1,
                    .p_clear_values = @ptrCast(&clear),
                }, .@"inline");

                self.gctx.dev.cmdBindPipeline(cmdbuf, .graphics, self.pipeline);
                const offset = [_]vk.DeviceSize{0};
                self.gctx.dev.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&self.buffer), &offset);
                self.gctx.dev.cmdDraw(cmdbuf, vertices.len, 1, 0, 0);

                self.gctx.dev.cmdEndRenderPass(cmdbuf);
                try self.gctx.dev.endCommandBuffer(cmdbuf);
            }

            return cmdbufs;
        }

        fn destroyCommandBuffers(gc: *const GraphicsContext, pool: vk.CommandPool, allocator: Allocator, cmdbufs: []vk.CommandBuffer) void {
            gc.dev.freeCommandBuffers(pool, @truncate(cmdbufs.len), cmdbufs.ptr);
            allocator.free(cmdbufs);
        }

        fn createFramebuffers(gc: *const GraphicsContext, allocator: Allocator, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
            const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
            errdefer allocator.free(framebuffers);

            var i: usize = 0;
            errdefer for (framebuffers[0..i]) |fb| gc.dev.destroyFramebuffer(fb, null);

            for (framebuffers) |*fb| {
                fb.* = try gc.dev.createFramebuffer(&.{
                    .render_pass = render_pass,
                    .attachment_count = 1,
                    .p_attachments = @ptrCast(&swapchain.swap_images[i].view),
                    .width = swapchain.extent.width,
                    .height = swapchain.extent.height,
                    .layers = 1,
                }, null);
                i += 1;
            }

            return framebuffers;
        }

        fn destroyFramebuffers(gc: *const GraphicsContext, allocator: Allocator, framebuffers: []const vk.Framebuffer) void {
            for (framebuffers) |fb| gc.dev.destroyFramebuffer(fb, null);
            allocator.free(framebuffers);
        }

        fn createRenderPass(gc: *const GraphicsContext, swapchain: Swapchain) !vk.RenderPass {
            const color_attachment = vk.AttachmentDescription{
                .format = swapchain.surface_format.format,
                .samples = .{ .@"1_bit" = true },
                .load_op = .clear,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .present_src_khr,
            };

            const color_attachment_ref = vk.AttachmentReference{
                .attachment = 0,
                .layout = .color_attachment_optimal,
            };

            const subpass = vk.SubpassDescription{
                .pipeline_bind_point = .graphics,
                .color_attachment_count = 1,
                .p_color_attachments = @ptrCast(&color_attachment_ref),
            };

            return try gc.dev.createRenderPass(&.{
                .attachment_count = 1,
                .p_attachments = @ptrCast(&color_attachment),
                .subpass_count = 1,
                .p_subpasses = @ptrCast(&subpass),
            }, null);
        }

        fn createPipeline(
            gc: *const GraphicsContext,
            layout: vk.PipelineLayout,
            render_pass: vk.RenderPass,
        ) !vk.Pipeline {
            const vert = try gc.dev.createShaderModule(&.{
                .code_size = shaders.triangle_vert.len,
                .p_code = @ptrCast(&shaders.triangle_vert),
            }, null);
            defer gc.dev.destroyShaderModule(vert, null);

            const frag = try gc.dev.createShaderModule(&.{
                .code_size = shaders.triangle_frag.len,
                .p_code = @ptrCast(&shaders.triangle_frag),
            }, null);
            defer gc.dev.destroyShaderModule(frag, null);

            const pssci = [_]vk.PipelineShaderStageCreateInfo{
                .{
                    .stage = .{ .vertex_bit = true },
                    .module = vert,
                    .p_name = "main",
                },
                .{
                    .stage = .{ .fragment_bit = true },
                    .module = frag,
                    .p_name = "main",
                },
            };

            const pvisci = vk.PipelineVertexInputStateCreateInfo{
                .vertex_binding_description_count = 1,
                .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
                .vertex_attribute_description_count = Vertex.attribute_description.len,
                .p_vertex_attribute_descriptions = &Vertex.attribute_description,
            };

            const piasci = vk.PipelineInputAssemblyStateCreateInfo{
                .topology = .triangle_list,
                .primitive_restart_enable = vk.FALSE,
            };

            const pvsci = vk.PipelineViewportStateCreateInfo{
                .viewport_count = 1,
                .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
                .scissor_count = 1,
                .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
            };

            const prsci = vk.PipelineRasterizationStateCreateInfo{
                .depth_clamp_enable = vk.FALSE,
                .rasterizer_discard_enable = vk.FALSE,
                .polygon_mode = .fill,
                .cull_mode = .{ .back_bit = true },
                .front_face = .clockwise,
                .depth_bias_enable = vk.FALSE,
                .depth_bias_constant_factor = 0,
                .depth_bias_clamp = 0,
                .depth_bias_slope_factor = 0,
                .line_width = 1,
            };

            const pmsci = vk.PipelineMultisampleStateCreateInfo{
                .rasterization_samples = .{ .@"1_bit" = true },
                .sample_shading_enable = vk.FALSE,
                .min_sample_shading = 1,
                .alpha_to_coverage_enable = vk.FALSE,
                .alpha_to_one_enable = vk.FALSE,
            };

            const pcbas = vk.PipelineColorBlendAttachmentState{
                .blend_enable = vk.FALSE,
                .src_color_blend_factor = .one,
                .dst_color_blend_factor = .zero,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,
                .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
            };

            const pcbsci = vk.PipelineColorBlendStateCreateInfo{
                .logic_op_enable = vk.FALSE,
                .logic_op = .copy,
                .attachment_count = 1,
                .p_attachments = @ptrCast(&pcbas),
                .blend_constants = [_]f32{ 0, 0, 0, 0 },
            };

            const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
            const pdsci = vk.PipelineDynamicStateCreateInfo{
                .flags = .{},
                .dynamic_state_count = dynstate.len,
                .p_dynamic_states = &dynstate,
            };

            const gpci = vk.GraphicsPipelineCreateInfo{
                .flags = .{},
                .stage_count = 2,
                .p_stages = &pssci,
                .p_vertex_input_state = &pvisci,
                .p_input_assembly_state = &piasci,
                .p_tessellation_state = null,
                .p_viewport_state = &pvsci,
                .p_rasterization_state = &prsci,
                .p_multisample_state = &pmsci,
                .p_depth_stencil_state = null,
                .p_color_blend_state = &pcbsci,
                .p_dynamic_state = &pdsci,
                .layout = layout,
                .render_pass = render_pass,
                .subpass = 0,
                .base_pipeline_handle = .null_handle,
                .base_pipeline_index = -1,
            };

            var pipeline: vk.Pipeline = undefined;
            _ = try gc.dev.createGraphicsPipelines(
                .null_handle,
                1,
                @ptrCast(&gpci),
                null,
                @ptrCast(&pipeline),
            );
            return pipeline;
        }
    };
}
