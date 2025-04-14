const c = @import("clibs");

const std = @import("std");

const Uuid = @import("uuid.zig").Uuid;
const texs = @import("textures.zig");
const Texture = texs.Texture;

const Mesh = @import("components/mesh.zig").Mesh;
const Vertex = @import("components/mesh.zig").Vertex;
const load_from_obj = @import("components/mesh.zig").load_from_obj;

const Engine = @import("VulkanEngine.zig");
const Material = Engine.Material;
const Scene = @import("scene.zig").Scene;

const check_vk = @import("vulkan_init.zig").check_vk;

const log = std.log.scoped(.assets);

const default_max_bytes = 30_000_000;

pub const AssetsDatabase = struct {
    const Self = @This();

    var instance: AssetsDatabase = undefined;

    allocator: std.mem.Allocator,
    engine: *Engine,
    loaded_ids: std.AutoHashMap(Uuid, void),
    loaded_assets: std.AutoHashMap(AssetHandle, LoadedAsset),

    loader: AssetLoader,

    pub fn init(allocator: std.mem.Allocator, engine: *Engine, loader: AssetLoader) void {
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
            var iter = instance.loaded_assets.valueIterator();
            while (iter.next()) |it| {
                it.unload();
            }
        }
        instance.loaded_ids.deinit();
        instance.loaded_assets.deinit();
    }

    pub fn getOrLoadTexture(id: Uuid) !*Texture {
        const hndl = try loadTexture(id);
        return getMaterial(hndl);
    }

    pub fn getTexture(hndl: TextureAssetHandle) !*Texture {
        const asset = try getLoadedAsset(hndl.toAssetHandle(), .texture);
        return asset.data.texture;
    }

    pub fn loadTexture(id: Uuid) !TextureAssetHandle {
        if (instance.loaded_ids.contains(id)) {
            return TextureAssetHandle.fromAssetIdUnsafe(id);
        }
        const handle = TextureAssetHandle{ .uuid = id };

        const bytes = try instance.loader(instance.allocator, id, default_max_bytes);
        defer instance.allocator.free(bytes);
        const image = try texs.load_image(instance.engine, bytes, id.urn());

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
            .image = image,
            .image_view = null,
        };

        check_vk(c.vkCreateImageView(instance.engine.device, &image_view_ci, Engine.vk_alloc_cbs, &texture.image_view)) catch @panic("Failed to create image view");

        const loaded = LoadedAsset{ .data = .{ .texture = texture } };
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(id, {});
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

        const vert_code = try instance.loader(instance.allocator, matparsed.value.passes.vertex, 20_000);
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

        const set_layouts = try instance.allocator.alloc(c.VkDescriptorSetLayout, matparsed.value.set_layouts.len);
        defer instance.allocator.free(set_layouts);
        for (matparsed.value.set_layouts, 0..) |set_layout, i| {
            set_layouts[i] = switch (set_layout) {
                .global => instance.engine.global_set_layout,
                .object => instance.engine.object_set_layout,
                .single_texture => instance.engine.single_texture_set_layout,
            };
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

        const frag_code = try instance.loader(instance.allocator, matparsed.value.passes.fragment, 20_000);
        defer instance.allocator.free(frag_code);
        const frag_module = instance.engine.createShaderModule(frag_code) orelse null;
        defer c.vkDestroyShaderModule(instance.engine.device, frag_module, Engine.vk_alloc_cbs);

        pipeline_builder.shader_stages[0].module = vert_module;
        pipeline_builder.shader_stages[1].module = frag_module;
        pipeline_builder.pipeline_layout = pipeline_layout;
        const pipeline = pipeline_builder.build(instance.engine.device, instance.engine.render_pass);

        material.* = Material{
            .uuid = Uuid.new(),
            .pipeline = pipeline,
            .pipeline_layout = pipeline_layout,
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
    texture,
    mesh,
    material,
    scene,
};

pub const AssetHandle = struct {
    uuid: Uuid,
};

pub const TextureAssetHandle = struct {
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
            .texture => {
                const it = self.data.texture;
                var img_del = Engine.VmaImageDeleter{ .image = it.image };
                img_del.delete(AssetsDatabase.instance.engine);
                var view_del = Engine.VulkanDeleter.make(
                    it.image_view,
                    c.vkDestroyImageView,
                );
                view_del.delete(AssetsDatabase.instance.engine);
                AssetsDatabase.instance.allocator.destroy(it);
            },
            .mesh => {
                const it = self.data.mesh;
                AssetsDatabase.instance.allocator.free(it.vertices[0..it.vertices_count]);
                AssetsDatabase.instance.allocator.destroy(it);
            },
            .material => {
                const it = self.data.material;
                var layout_del = Engine.VulkanDeleter.make(it.pipeline_layout, c.vkDestroyPipelineLayout);
                layout_del.delete(AssetsDatabase.instance.engine);
                var pipeline_del = Engine.VulkanDeleter.make(it.pipeline, c.vkDestroyPipeline);
                pipeline_del.delete(AssetsDatabase.instance.engine);
                AssetsDatabase.instance.allocator.destroy(it);
            },
            .scene => {
                const it = self.data.scene;
                it.deinit();
            },
        }
    }
};

const Passes = struct {
    vertex: Uuid,
    fragment: Uuid,
};

const SetLayout = enum {
    global,
    object,
    single_texture,
};

const MaterialDef = struct {
    name: []const u8,
    passes: Passes,
    set_layouts: []SetLayout,
};

fn parseJson(json_str: []const u8, allocator: *std.mem.Allocator) !Material {
    const json = std.json.parse(json_str, allocator) catch return error.InvalidJson;
    return Material{
        .name = json.get([]const u8, "name") catch return error.MissingKey,
        .passes = Passes{
            .vertex = json.get([]const u8, "passes").get([]const u8, "vertex") catch return error.MissingKey,
            .fragment = json.get([]const u8, "passes").get([]const u8, "fragment") catch return error.MissingKey,
        },
        .set_layouts = try json.get([]const u8, "set_layouts").map(setLayoutFromString),
    };
}

fn setLayoutFromString(layout: []const u8) !SetLayout {
    if (std.mem.eql(u8, layout, "global")) {
        return SetLayout.global;
    } else if (std.mem.eql(u8, layout, "object")) {
        return SetLayout.object;
    } else if (std.mem.eql(u8, layout, "single_texture")) {
        return SetLayout.single_texture;
    } else unreachable;
}

pub const AssetLoader = *const fn (allocator: std.mem.Allocator, id: Uuid, max_bytes: usize) error{ ResourceNotFound, FailedToOpenResource, FailedToReadResource }![]u8;
