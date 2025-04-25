const c = @import("clibs");

const std = @import("std");

const Uuid = @import("uuid.zig").Uuid;
const texs = @import("textures.zig");
const Texture = texs.Texture;

const components = @import("ecs.zig").components;

const Mesh = components.Mesh;
const Vertex = components.mesh.Vertex;
const load_from_obj = components.mesh.load_from_obj2;

const Material = components.Material;

const Engine = @import("VulkanEngine.zig");
const Scene = @import("scene.zig").Scene;

const check_vk = @import("vulkan_init.zig").check_vk;

const log = std.log.scoped(.assets);

const default_max_bytes = 30_000_000;

pub const Assets = struct {
    const Self = @This();

    var instance: Assets = undefined;

    allocator: std.mem.Allocator,
    engine: *Engine,
    loaded_ids: std.AutoHashMap(Uuid, void),
    loaded_assets: std.AutoHashMap(AssetHandle, LoadedAsset),

    loader: ResourceLoader,

    pub fn init(allocator: std.mem.Allocator, engine: *Engine, loader: ResourceLoader) void {
        instance = .{
            .allocator = allocator,
            .engine = engine,
            .loaded_ids = std.AutoHashMap(Uuid, void).init(allocator),
            .loaded_assets = std.AutoHashMap(AssetHandle, LoadedAsset).init(allocator),

            .loader = loader,
        };
    }

    pub fn deinit() void {
        {
            const RecursiveReverseUnloader = struct {
                fn unload(assets: std.AutoHashMap(AssetHandle, LoadedAsset)) void {
                    var iter = assets.valueIterator();
                    @This().f(&iter);
                }

                fn f(iter: *std.AutoHashMap(AssetHandle, LoadedAsset).ValueIterator) void {
                    if (iter.next()) |it| {
                        @This().f(iter);
                        it.unload();
                    }
                }
            };

            RecursiveReverseUnloader.unload(instance.loaded_assets);
        }
        instance.loaded_ids.deinit();
        instance.loaded_assets.deinit();
    }

    pub fn getOrLoadImage(id: Uuid) !*Engine.AllocatedImage {
        const hndl = try loadImage(id);
        return getImage(hndl);
    }

    pub fn getImage(hndl: ImageAssetHandle) !*Engine.AllocatedImage {
        const asset = try getLoadedAsset(hndl.toAssetHandle(), .image);
        return asset.data.image;
    }

    pub fn loadImage(id: Uuid) !ImageAssetHandle {
        if (instance.loaded_ids.contains(id)) {
            return ImageAssetHandle.fromAssetIdUnsafe(id);
        }
        const handle = ImageAssetHandle{ .uuid = id };

        const bytes = try instance.loader(instance.allocator, id, default_max_bytes);
        defer instance.allocator.free(bytes);

        const image = try instance.allocator.create(Engine.AllocatedImage);
        image.* = try texs.load_image(instance.engine, bytes, id.urn());

        const loaded = LoadedAsset{ .data = .{ .image = image } };
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(id, {});
        return handle;
    }

    pub fn getOrLoadTexture(id: Uuid) !*Texture {
        const hndl = try loadTexture(id);
        return getTexture(hndl);
    }

    pub fn getTexture(hndl: TextureAssetHandle) !*Texture {
        const asset = try getLoadedAsset(hndl.toAssetHandle(), .texture);
        return asset.data.texture;
    }

    pub fn loadTexture(img_id: Uuid) !TextureAssetHandle {
        if (instance.loaded_ids.contains(img_id)) {
            return TextureAssetHandle.fromAssetIdUnsafe(img_id);
        }
        const handle = TextureAssetHandle.fromAssetIdUnsafe(img_id);

        const image = try Self.getOrLoadImage(img_id);

        const image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .image = image.image,
            .format = c.VK_FORMAT_R8G8B8A8_UNORM,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        });

        var texture = try instance.allocator.create(Texture);
        texture.* = Texture{
            .image = image.*,
            .image_view = null,
        };

        check_vk(c.vkCreateImageView(instance.engine.device, &image_view_ci, Engine.vk_alloc_cbs, &texture.image_view)) catch @panic("Failed to create image view");

        const loaded = LoadedAsset{ .data = .{ .texture = texture } };
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(handle.uuid, {});
        return handle;
    }

    pub fn getOrLoadMesh(id: Uuid) !*Mesh {
        const hndl = try loadMesh(id);
        return getMesh(hndl);
    }

    pub fn getMesh(hndl: MeshAssetHandle) !*Mesh {
        const asset = try getLoadedAsset(hndl.toAssetHandle(), .mesh);
        return asset.data.mesh;
    }

    pub fn loadMesh(id: Uuid) !MeshAssetHandle {
        if (instance.loaded_ids.contains(id)) {
            return MeshAssetHandle.fromAssetIdUnsafe(id);
        }
        const handle = MeshAssetHandle{ .uuid = id };
        const bytes = try instance.loader(instance.allocator, id, default_max_bytes);
        defer instance.allocator.free(bytes);

        const mesh = try instance.allocator.create(Mesh);
        mesh.* = load_from_obj(instance.allocator, bytes);
        mesh.uuid = id;
        instance.engine.uploadMesh(mesh);

        const loaded = LoadedAsset{ .data = .{ .mesh = mesh } };
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(id, {});
        return handle;
    }

    pub fn getOrLoadMaterial(id: Uuid) !*Material {
        const hndl = try loadMaterial(id);
        return getMaterial(hndl);
    }

    pub fn getMaterial(hndl: MaterialAssetHandle) !*Material {
        const asset = try getLoadedAsset(hndl.toAssetHandle(), .material);
        return asset.data.material;
    }

    pub fn loadMaterial(id: Uuid) !MaterialAssetHandle {
        if (instance.loaded_ids.contains(id)) {
            return MaterialAssetHandle.fromAssetIdUnsafe(id);
        }
        const handle = MaterialAssetHandle{ .uuid = id };
        const matjson = try instance.loader(instance.allocator, id, 20_000);
        defer instance.allocator.free(matjson);

        const matparsed = std.json.parseFromSlice(
            MaterialDef,
            instance.allocator,
            matjson,
            .{},
        ) catch @panic("Failed to parse the material json");
        defer matparsed.deinit();

        const material = try instance.allocator.create(Material);

        // NOTE: we are currently destroying the shader modules as soon as we are done
        // creating the pipeline. This is not great if we needed the modules for multiple pipelines.
        // Howver, for the sake of simplicity, we are doing it this way for now.

        const vertex_input_state_ci = std.mem.zeroInit(c.VkPipelineVertexInputStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        });

        const input_assembly_state_ci = std.mem.zeroInit(c.VkPipelineInputAssemblyStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        });

        const rasterization_state_ci = std.mem.zeroInit(c.VkPipelineRasterizationStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .cullMode = c.VK_CULL_MODE_NONE,
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
            .lineWidth = 1.0,
        });

        const multisample_state_ci = std.mem.zeroInit(c.VkPipelineMultisampleStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .minSampleShading = 1.0,
        });

        const depth_stencil_state_ci = std.mem.zeroInit(c.VkPipelineDepthStencilStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = c.VK_TRUE,
            .depthWriteEnable = c.VK_TRUE,
            .depthCompareOp = c.VK_COMPARE_OP_LESS_OR_EQUAL,
            .depthBoundsTestEnable = c.VK_FALSE,
            .stencilTestEnable = c.VK_FALSE,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
        });

        const color_blend_attachment_state = std.mem.zeroInit(c.VkPipelineColorBlendAttachmentState, .{
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        });

        var shader_stages = [_]c.VkPipelineShaderStageCreateInfo{
            std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                .pName = "main",
            }),
            std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .pName = "main",
            }),
        };

        var pipeline_builder = Engine.PipelineBuilder{
            .shader_stages = shader_stages[0..],
            .vertex_input_state = vertex_input_state_ci,
            .input_assembly_state = input_assembly_state_ci,
            .viewport = .{
                .x = 0.0,
                .y = 0.0,
                .width = @as(f32, @floatFromInt(instance.engine.swapchain_extent.width)),
                .height = @as(f32, @floatFromInt(instance.engine.swapchain_extent.height)),
                .minDepth = 0.0,
                .maxDepth = 1.0,
            },
            .scissor = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = instance.engine.swapchain_extent,
            },
            .rasterization_state = rasterization_state_ci,
            .color_blend_attachment_state = color_blend_attachment_state,
            .multisample_state = multisample_state_ci,
            .pipeline_layout = undefined, // TBD
            .depth_stencil_state = depth_stencil_state_ci,
        };

        // Create pipeline for meshes
        const vertex_descritpion = Vertex.vertex_input_description;

        pipeline_builder.vertex_input_state.pVertexAttributeDescriptions = vertex_descritpion.attributes.ptr;
        pipeline_builder.vertex_input_state.vertexAttributeDescriptionCount = @as(u32, @intCast(vertex_descritpion.attributes.len));
        pipeline_builder.vertex_input_state.pVertexBindingDescriptions = vertex_descritpion.bindings.ptr;
        pipeline_builder.vertex_input_state.vertexBindingDescriptionCount = @as(u32, @intCast(vertex_descritpion.bindings.len));

        const vert_code = try instance.loader(instance.allocator, matparsed.value.shader.passes.vertex, 20_000);
        defer instance.allocator.free(vert_code);
        const vert_module = instance.engine.createShaderModule(vert_code) orelse null;
        defer c.vkDestroyShaderModule(instance.engine.device, vert_module, Engine.vk_alloc_cbs);

        if (vert_module != null) log.info("vert module loaded successfully", .{});

        // New layout for push constants
        const push_constant_range = std.mem.zeroInit(c.VkPushConstantRange, .{
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
            .offset = 0,
            .size = @sizeOf(Engine.MeshPushConstants),
        });

        const builtin_uniforms_len = 2;
        const set_layouts = try instance.allocator.alloc(
            c.VkDescriptorSetLayout,
            matparsed.value.resources.len + builtin_uniforms_len,
        );
        defer instance.allocator.free(set_layouts);
        const resources_uuids = try instance.allocator.alloc(Uuid, matparsed.value.resources.len);
        const resources_sets = try instance.allocator.alloc(c.VkDescriptorSet, matparsed.value.resources.len);
        set_layouts[0] = instance.engine.global_set_layout;
        set_layouts[1] = instance.engine.object_set_layout;
        for (matparsed.value.shader.layouts, matparsed.value.resources, 0..) |layout, resource, i| {
            switch (layout) {
                .texture => {
                    set_layouts[i + builtin_uniforms_len] = instance.engine.texture_set_layout;
                    resources_uuids[i] = resource.?;
                    // Allocate descriptor set for signle-texture to use on the material
                    const descriptor_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
                        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                        .descriptorPool = instance.engine.descriptor_pool,
                        .descriptorSetCount = 1,
                        .pSetLayouts = &instance.engine.texture_set_layout,
                    });

                    check_vk(c.vkAllocateDescriptorSets(instance.engine.device, &descriptor_set_alloc_info, &resources_sets[i])) catch @panic("Failed to allocate descriptor set");
                    const sampler_ci = std.mem.zeroInit(c.VkSamplerCreateInfo, .{
                        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                        .magFilter = c.VK_FILTER_NEAREST,
                        .minFilter = c.VK_FILTER_NEAREST,
                        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                    });
                    var sampler: c.VkSampler = undefined;
                    check_vk(c.vkCreateSampler(instance.engine.device, &sampler_ci, Engine.vk_alloc_cbs, &sampler)) catch @panic("Failed to create sampler");
                    instance.engine.deletion_queue.append(Engine.VulkanDeleter.make(sampler, c.vkDestroySampler)) catch @panic("Out of memory");

                    const tex = Self.getOrLoadTexture(resource.?) catch @panic("Failed to load texture");
                    const descriptor_image_info = std.mem.zeroInit(c.VkDescriptorImageInfo, .{
                        .sampler = sampler,
                        .imageView = tex.image_view,
                        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    });

                    const write_descriptor_set = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
                        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .dstSet = resources_sets[i],
                        .dstBinding = 0,
                        .descriptorCount = 1,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                        .pImageInfo = &descriptor_image_info,
                    });

                    c.vkUpdateDescriptorSets(instance.engine.device, 1, &write_descriptor_set, 0, null);
                },
                .cube => @panic("TODO"),
            }
        }
        var pipeline_layout_ci = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = @as(u32, @intCast(set_layouts.len)),
            .pSetLayouts = &set_layouts[0],
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &push_constant_range,
        });

        var pipeline_layout: c.VkPipelineLayout = undefined;
        check_vk(c.vkCreatePipelineLayout(
            instance.engine.device,
            &pipeline_layout_ci,
            Engine.vk_alloc_cbs,
            &pipeline_layout,
        )) catch @panic("Failed to create textured mesh pipeline layout");

        const frag_code = try instance.loader(instance.allocator, matparsed.value.shader.passes.fragment, 20_000);
        defer instance.allocator.free(frag_code);
        const frag_module = instance.engine.createShaderModule(frag_code) orelse null;
        defer c.vkDestroyShaderModule(instance.engine.device, frag_module, Engine.vk_alloc_cbs);

        pipeline_builder.shader_stages[0].module = vert_module;
        pipeline_builder.shader_stages[1].module = frag_module;
        pipeline_builder.pipeline_layout = pipeline_layout;
        const pipeline = pipeline_builder.build(instance.engine.device, instance.engine.render_pass);

        material.* = Material{
            .uuid = id,
            .pipeline = pipeline,
            .pipeline_layout = pipeline_layout,

            .rsc_uuids = resources_uuids.ptr,
            .rsc_descriptor_sets = resources_sets.ptr,
            .rsc_count = @intCast(resources_sets.len),
        };

        const loaded = LoadedAsset{ .data = .{ .material = material } };
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(id, {});
        return handle;
    }

    pub fn getOrLoadScene(id: Uuid) !*Scene {
        const hndl = try loadScene(id);
        return getScene(hndl);
    }

    pub fn getScene(hndl: SceneAssetHandle) !*Scene {
        const asset = try getLoadedAsset(hndl.toAssetHandle(), .scene);
        return asset.data.scene;
    }

    pub fn loadScene(id: Uuid) !SceneAssetHandle {
        if (instance.loaded_ids.contains(id)) {
            return SceneAssetHandle.fromAssetIdUnsafe(id);
        }
        const handle = SceneAssetHandle{ .uuid = id };
        const bytes = try instance.loader(instance.allocator, id, default_max_bytes);
        defer instance.allocator.free(bytes);

        const scene = try Scene.fromJson(instance.allocator, bytes, .{});

        const loaded = LoadedAsset{ .data = .{ .scene = scene } };
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(id, {});
        return handle;
    }

    pub fn getLoadedAsset(hndl: AssetHandle, ty: AssetType) !LoadedAsset {
        const it = instance.loaded_assets.get(hndl) orelse return error.AssetNotLoaded;
        if (it.assetType() != ty) return error.InvalidType;
        return it;
    }

    pub fn unload(hndl: AssetHandle) !void {
        var it = instance.loaded_assets.fetchRemove(hndl) orelse return error.AssetNotLoaded;
        std.debug.assert(instance.loaded_ids.remove(hndl.uuid));
        it.value.unload();
    }
};

const AssetType = enum {
    image,
    texture,
    mesh,
    material,
    scene,
};

pub const AssetHandle = struct {
    uuid: Uuid,
};

pub const ImageAssetHandle = struct {
    uuid: Uuid,

    pub inline fn toAssetHandle(hndl: @This()) AssetHandle {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetHandleUnsafe(hndl: AssetHandle) @This() {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetIdUnsafe(id: Uuid) @This() {
        return .{ .uuid = id };
    }
};

pub const TextureAssetHandle = struct {
    uuid: Uuid,

    pub inline fn toAssetHandle(hndl: @This()) AssetHandle {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetHandleUnsafe(hndl: AssetHandle) @This() {
        return fromAssetIdUnsafe(hndl.uuid);
    }

    inline fn fromAssetIdUnsafe(id: Uuid) @This() {
        return .{ .uuid = .{ .raw = id.raw + 1 } };
    }
};

pub const MeshAssetHandle = struct {
    uuid: Uuid,

    pub inline fn toAssetHandle(hndl: @This()) AssetHandle {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetHandleUnsafe(hndl: AssetHandle) @This() {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetIdUnsafe(id: Uuid) @This() {
        return .{ .uuid = id };
    }
};

pub const MaterialAssetHandle = struct {
    uuid: Uuid,

    pub inline fn toAssetHandle(hndl: @This()) AssetHandle {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetHandleUnsafe(hndl: AssetHandle) @This() {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetIdUnsafe(id: Uuid) @This() {
        return .{ .uuid = id };
    }
};

pub const SceneAssetHandle = struct {
    uuid: Uuid,

    pub inline fn toAssetHandle(hndl: @This()) AssetHandle {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetHandleUnsafe(hndl: AssetHandle) @This() {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetIdUnsafe(id: Uuid) @This() {
        return .{ .uuid = id };
    }
};

const LoadedAsset = struct {
    const Self = @This();
    data: union(AssetType) {
        image: *Engine.AllocatedImage,
        texture: *Texture,
        mesh: *Mesh,
        material: *Material,
        scene: *Scene,
    },

    pub fn assetType(self: *const Self) AssetType {
        return @enumFromInt(@intFromEnum(self.data));
    }

    fn unload(self: *Self) void {
        switch (self.data) {
            .image => {
                const it = self.data.image;
                var img_del = Engine.VmaImageDeleter{ .image = it.* };
                img_del.delete(Assets.instance.engine);
                Assets.instance.allocator.destroy(it);
            },
            .texture => {
                const it = self.data.texture;
                var view_del = Engine.VulkanDeleter.make(
                    it.image_view,
                    c.vkDestroyImageView,
                );
                view_del.delete(Assets.instance.engine);
                Assets.instance.allocator.destroy(it);
            },
            .mesh => {
                const it = self.data.mesh;
                Assets.instance.allocator.free(it.vertices[0..it.vertices_count]);
                Assets.instance.allocator.destroy(it);
            },
            .material => {
                const it = self.data.material;
                var layout_del = Engine.VulkanDeleter.make(it.pipeline_layout, c.vkDestroyPipelineLayout);
                layout_del.delete(Assets.instance.engine);
                var pipeline_del = Engine.VulkanDeleter.make(it.pipeline, c.vkDestroyPipeline);
                pipeline_del.delete(Assets.instance.engine);
                Assets.instance.allocator.free(it.rsc_descriptor_sets[0..@intCast(it.rsc_count)]);
                Assets.instance.allocator.free(it.rsc_uuids[0..@intCast(it.rsc_count)]);
                Assets.instance.allocator.destroy(it);
            },
            .scene => {
                const it = self.data.scene;
                it.deinit();
            },
        }
    }
};

const ShaderDef = struct {
    const Passes = struct {
        vertex: Uuid,
        fragment: Uuid,
    };
    const SetLayout = enum {
        texture,
        cube,
    };
    passes: Passes,
    layouts: []SetLayout,
};

const MaterialDef = struct {
    name: []const u8,
    shader: ShaderDef,
    resources: []?Uuid,

    pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, opts: anytype) !@This() {
        var tk = try jrs.next();
        if (tk != .object_begin) return error.UnexpectedEndOfInput;

        var result: MaterialDef = undefined;
        var resources: ?[]?Uuid = null;

        while (true) {
            tk = try jrs.nextAlloc(a, .alloc_if_needed);
            if (tk == .object_end) break;

            const field_name = switch (tk) {
                inline .string, .allocated_string => |slice| slice,
                else => {
                    log.err("{}\n", .{tk});
                    return error.UnexpectedToken;
                },
            };

            if (std.mem.eql(u8, field_name, "name")) {
                result.name = switch (try jrs.next()) {
                    inline .string => |slice| try a.dupeZ(u8, slice),
                    else => {
                        log.err("{}\n", .{tk});
                        return error.UnexpectedToken;
                    },
                };
            } else if (std.mem.eql(u8, field_name, "shader")) {
                result.shader = try std.json.innerParse(ShaderDef, a, jrs, opts);
            } else if (std.mem.eql(u8, field_name, "resources")) {
                resources = try std.json.innerParse([]?Uuid, a, jrs, opts);
            } else {
                try jrs.skipValue();
            }
        }

        result.resources = resources orelse try a.alloc(?Uuid, 0);

        return result;
    }
};

pub const ResourceLoader = *const fn (allocator: std.mem.Allocator, id: Uuid, max_bytes: usize) error{ ResourceNotFound, FailedToOpenResource, FailedToReadResource }![]u8;
