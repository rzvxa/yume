const c = @import("clibs");

const std = @import("std");

const Event = @import("event.zig").Event;

const Uuid = @import("uuid.zig").Uuid;
const texs = @import("textures.zig");
const Vec4 = @import("math3d.zig").Vec4;
const Texture = texs.Texture;

const components = @import("ecs.zig").components;

const Mesh = components.Mesh;
const Vertex = components.mesh.Vertex;

const shading = @import("shading.zig");
const Shader = shading.Shader;
const Material = shading.Material;

const Engine = @import("VulkanEngine.zig");
const Scene = @import("scene.zig").Scene;

const check_vk = @import("vulkan_init.zig").check_vk;

const log = std.log.scoped(.assets);

const default_max_bytes = 30_000_000;
const Image = Engine.AllocatedImage;

pub const RGBA8 = [4]u8;

pub const Assets = struct {
    pub const Loaders = struct {
        pub const Error = error{
            OutOfMemory,
            ResourceNotFound,
            FailedToOpenResource,
            FailedToReadResource,
            FailedToParseResource,
        };

        pub const ResourceLoader = *const fn (allocator: std.mem.Allocator, id: Uuid, max_bytes: usize) Error![]u8;
        pub const ShaderDefLoader = *const fn (id: Uuid) Error!*const Shader.Def;
        pub const MaterialDefLoader = *const fn (id: Uuid) Error!*const Material.Def;

        resource: ResourceLoader,
        shader_def: ShaderDefLoader,
        material_def: MaterialDefLoader,
    };
    const Self = @This();

    var instance: Assets = undefined;

    allocator: std.mem.Allocator,
    engine: *Engine,
    loaded_ids: std.AutoHashMap(Uuid, void),
    loaded_assets: std.AutoHashMap(AssetHandle, LoadedAsset),

    color_texture_map: std.AutoHashMap(RGBA8, TextureHandle),
    texture_color_map: std.AutoHashMap(TextureHandle, RGBA8),

    unused_assets_maps: [Engine.FRAME_OVERLAP]std.AutoHashMap(AssetHandle, void),
    unused_assets_active_idx: usize = 0,

    orphan_assets_maps: [Engine.FRAME_OVERLAP]std.ArrayList(LoadedAsset),
    orphan_assets_active_idx: usize = 0,

    loaders: Loaders,

    pub fn init(allocator: std.mem.Allocator, engine: *Engine, loaders: Loaders) void {
        instance = .{
            .allocator = allocator,
            .engine = engine,
            .loaded_ids = std.AutoHashMap(Uuid, void).init(allocator),
            .loaded_assets = std.AutoHashMap(AssetHandle, LoadedAsset).init(allocator),

            .color_texture_map = std.AutoHashMap(RGBA8, TextureHandle).init(allocator),
            .texture_color_map = std.AutoHashMap(TextureHandle, RGBA8).init(allocator),

            .unused_assets_maps = undefined,
            .orphan_assets_maps = undefined,

            .loaders = loaders,
        };

        for (0..instance.unused_assets_maps.len) |i| {
            instance.unused_assets_maps[i] = std.AutoHashMap(AssetHandle, void).init(allocator);
        }

        for (0..instance.orphan_assets_maps.len) |i| {
            instance.orphan_assets_maps[i] = std.ArrayList(LoadedAsset).init(allocator);
        }
    }

    pub fn deinit() void {
        collect(.{ .force = true }) catch @panic("Failed to collect assets");
        {
            if (instance.loaded_assets.count() > 0) {
                log.err("Memory leak", .{});
                var iter = instance.loaded_assets.iterator();
                while (iter.next()) |next| {
                    log.err("leaked asset {s} -> {}", .{ next.key_ptr.uuid.urn(), next.value_ptr.assetType() });
                    if (next.value_ptr.assetType() == .texture) {
                        if (instance.texture_color_map.contains(next.key_ptr.*.unbox(.texture))) {
                            log.err("was a color texture", .{});
                        }
                    }
                }
            }
        }
        instance.loaded_ids.deinit();
        instance.loaded_assets.deinit();
        instance.color_texture_map.deinit();
        instance.texture_color_map.deinit();
        for (0..instance.unused_assets_maps.len) |i| {
            instance.unused_assets_maps[i].deinit();
        }

        for (0..instance.orphan_assets_maps.len) |i| {
            instance.orphan_assets_maps[i].deinit();
        }
    }

    pub inline fn GetResult(comptime T: type) type {
        if (@hasDecl(T, "BackingType") and @hasDecl(T, "toAssetHandle")) {
            return *T.BackingType;
        } else if (T == AssetHandle) {
            @compileError("Invalid use of AssetHandle, use `.unbox` method to get an asserted handle");
        } else {
            @compileError("Invalid handle type " ++ @typeName(T));
        }
    }

    pub fn get(handle: anytype) !GetResult(@TypeOf(handle)) {
        const tag = @TypeOf(handle).Tag;
        const generic_handle = handle.toAssetHandle();

        var loaded = getLoadedAsset(generic_handle) catch |err| r: {
            switch (err) {
                error.AssetNotLoaded => {
                    _ = try switch (tag) {
                        .binary => @panic("TODO"),
                        .image => loadImage(handle, null),
                        .texture => loadTexture(handle, null),
                        .mesh => loadMesh(handle, null),
                        .material => loadMaterial(handle, null),
                        .shader => loadShader(handle, null),
                        .scene => loadScene(handle),
                    };
                    break :r try getLoadedAsset(generic_handle);
                },
                else => return err,
            }
        };

        loaded.ref_count += 1;
        return switch (tag) {
            .binary => loaded.data.binary,
            .image => loaded.data.image,
            .texture => loaded.data.texture,
            .mesh => loaded.data.mesh,
            .material => loaded.data.material,
            .shader => loaded.data.shader,
            .scene => loaded.data.scene,
        };
    }

    pub fn release(asset: anytype) !void {
        comptime var actual_ty = @TypeOf(asset);
        const ty_info = @typeInfo(actual_ty);
        if (ty_info == .Pointer) {
            actual_ty = ty_info.Pointer.child;
        }
        const handle: AssetHandle = if (comptime @hasDecl(actual_ty, "toAssetHandle"))
            asset.toAssetHandle()
        else
            asset.handle.toAssetHandle();

        var loaded = try getLoadedAsset(handle);
        if (loaded.ref_count == 0) {
            // item released more times that borrowed
            return error.DoubleRelease;
        }
        loaded.ref_count -= 1;
        if (loaded.ref_count == 0) {
            try unused(handle);
        }
    }

    // does nothing if asset isn't loaded already
    pub fn reload(asset: anytype, comptime opts: struct {
        recursive: bool = true,
    }) (std.mem.Allocator.Error ||
        Engine.Error || Loaders.Error || error{
        AssetNotLoaded,
        DoubleRelease,
        failed_to_load_image,
        failed_to_create_image,
        FailedToLoadVertModule,
        FailedToLoadFragModule,
        InvalidAssetDependency,
        UnexpectedResourceBinding,
    })!void {
        comptime var actual_ty = @TypeOf(asset);
        const ty_info = @typeInfo(actual_ty);
        if (ty_info == .Pointer) {
            actual_ty = ty_info.Pointer.child;
        }
        const handle = if (comptime @hasDecl(actual_ty, "toAssetHandle"))
            asset
        else
            asset.handle;

        // unwrap generic handle to explicit handle call
        if (@TypeOf(handle) == AssetHandle) {
            return switch (handle.type) {
                // .binary => reload(handle.unbox(.binary), opts),
                .image => reload(handle.unbox(.image), opts),
                .texture => reload(handle.unbox(.texture), opts),
                .mesh => reload(handle.unbox(.mesh), opts),
                .material => reload(handle.unbox(.material), opts),
                .shader => reload(handle.unbox(.shader), opts),
                // .scene => reload(handle.unbox(.scene), opts),
                else => @panic("TODO"),
            };
        }

        const Tag = @TypeOf(handle).Tag;

        const generic_handle: AssetHandle = handle.toAssetHandle();

        var kv = instance.loaded_assets.fetchRemove(generic_handle) orelse return;
        // we manage the dependencies manually during the reloads
        defer kv.value.dependants.deinit();
        defer kv.value.dependencies.deinit();

        for (kv.value.dependencies.items) |dep| {
            try undependency(dep, generic_handle);
        }

        {
            // queue the orphan asset for release
            const orphan_copy = LoadedAsset.init(
                instance.allocator,
                kv.value.handle,
                try kv.value.data.clone(instance.allocator),
            );
            try orphan(orphan_copy);
        }

        if (comptime opts.recursive) {
            switch (kv.value.data) {
                .binary, .image, .mesh, .shader => {},
                .texture => |t| {
                    try release(t.image);
                    try reload(t.image, opts);
                },
                .material => |m| {
                    try release(m.shader);
                    try reload(m.shader, opts);
                    for (0..m.rsc_count) |i| {
                        try release(m.rsc_handles[i]);

                        if (m.rsc_handles[i].type == .texture and
                            instance.texture_color_map.contains(m.rsc_handles[i].unbox(.texture)))
                        {
                            // color textures don't need to be reloaded,
                            continue;
                        }

                        try reload(m.rsc_handles[i], opts);
                    }
                },
                else => @panic("TODO"),
            }
        }

        try switch (Tag) {
            .binary => @compileError("TODO"),
            .image => loadImage(handle, kv.value.data.image),
            .texture => loadTexture(handle, kv.value.data.texture),
            .mesh => loadMesh(handle, kv.value.data.mesh),
            .material => loadMaterial(handle, kv.value.data.material),
            .shader => loadShader(handle, kv.value.data.shader),
            .scene => @compileError("TODO"),
        };
        var new_loaded = try getLoadedAsset(generic_handle);
        new_loaded.ref_count = kv.value.ref_count;
        new_loaded.hooks.on_reload.fire(.{generic_handle});
    }

    pub fn collect(
        comptime opts: struct {
            // NOTE: disregards the thread safety with GPU frame buffers,
            // can only be used safely while all frames are idle.
            force: bool = false,
        },
    ) !void {
        {
            var orphan_assets = last_orphan_assets_map();
            // round robin between active maps on each collection,
            defer instance.orphan_assets_active_idx = @mod(instance.orphan_assets_active_idx + 1, instance.orphan_assets_maps.len);
            for (0..orphan_assets.items.len) |i| {
                orphan_assets.items[i].unload(.{ .orphan = true });
            }
            orphan_assets.clearRetainingCapacity();
        }

        {
            var unused_assets = last_unused_assets_map();
            // round robin between active maps on each collection,
            defer instance.unused_assets_active_idx = @mod(instance.unused_assets_active_idx + 1, instance.unused_assets_maps.len);
            var iter = unused_assets.keyIterator();
            while (iter.next()) |handle| {
                var loaded = getLoadedAsset(handle.*) catch |err| switch (err) {
                    error.AssetNotLoaded => {
                        log.debug("Unused asset {} already unloaded", .{handle.*});
                        continue;
                    },
                    else => return err,
                };
                // it is possible for an asset to get rescued if it's referenced again before collection
                // if that is the case, we just ignore this entry
                if (loaded.ref_count > 0) {
                    log.info("Rescued asset {s}, {}", .{ handle.uuid.urn(), loaded.assetType() });
                    continue;
                }

                if (loaded.assetType() == .texture) {
                    // NOTE: this edge case is for removing color textures from the cache,
                    // it's a bit hacky and I don't like it at all.
                    if (instance.texture_color_map.fetchRemove(handle.unbox(.texture))) |kv| {
                        _ = instance.color_texture_map.remove(kv.value);
                    }
                }
                loaded.unload(.{});
                std.debug.assert(instance.loaded_ids.remove(handle.uuid));
                std.debug.assert(instance.loaded_assets.remove(handle.toAssetHandle()));
            }
            unused_assets.clearRetainingCapacity();
        }

        if (comptime opts.force) {
            for (instance.unused_assets_maps) |m| {
                if (m.count() > 0) {
                    return collect(opts);
                }
            }

            for (instance.orphan_assets_maps) |m| {
                if (m.items.len > 0) {
                    return collect(opts);
                }
            }
        }
    }

    pub fn getColorTexture(color: RGBA8) !*Texture {
        const gop = try instance.color_texture_map.getOrPut(color);
        if (gop.found_existing) {
            return get(gop.value_ptr.*);
        }

        gop.value_ptr.* = .{ .uuid = Uuid.new() };

        try instance.texture_color_map.put(gop.value_ptr.*, color);
        try loadColorTexture(color, gop.value_ptr.*);

        return get(gop.value_ptr.*);
    }

    pub fn hooks(handle: AssetHandle) !*AssetHooks {
        var loaded = try getLoadedAsset(handle);
        return &loaded.hooks;
    }

    // declares the dependency of the `depender` on the `dependee`
    // both assets should be loaded
    fn dependency(dependee: AssetHandle, depender: AssetHandle) !void {
        const dependee_loaded = try getLoadedAsset(dependee);
        const depender_loaded = try getLoadedAsset(depender);

        const gop = try dependee_loaded.dependants.getOrPut(depender);
        gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;

        try depender_loaded.dependencies.append(dependee);
    }

    // undeclares the dependency of the `depender` on the `dependee`
    // it is the opposite of the `dependency`, however the depender can already been unloaded
    fn undependency(dependee: AssetHandle, depender: AssetHandle) !void {
        const dependee_loaded = try getLoadedAsset(dependee);

        if (dependee_loaded.dependants.getEntry(depender)) |entry| {
            entry.value_ptr.* -= 1;
            if (entry.value_ptr.* == 0) {
                dependee_loaded.dependants.removeByPtr(entry.key_ptr);
            }
        } else {
            return error.InvalidAssetDependency;
        }

        const depender_loaded = getLoadedAsset(depender) catch |err| switch (err) {
            error.AssetNotLoaded => return,
            else => return err,
        };

        for (depender_loaded.dependencies.items, 0..) |dep, i| {
            if (dep.eql(dependee)) {
                _ = depender_loaded.dependencies.swapRemove(i);
                return;
            }
        } else {
            return error.InvalidAssetDependency;
        }
    }

    fn unused(handle: AssetHandle) !void {
        try unused_assets_map().put(handle, {});
    }

    inline fn unused_assets_map() *std.AutoHashMap(AssetHandle, void) {
        return &instance.unused_assets_maps[instance.unused_assets_active_idx];
    }

    inline fn last_unused_assets_map() *std.AutoHashMap(AssetHandle, void) {
        return &instance.unused_assets_maps[(if (instance.unused_assets_active_idx == 0) instance.unused_assets_maps.len else instance.unused_assets_active_idx) - 1];
    }

    fn orphan(asset: LoadedAsset) !void {
        try orphan_assets_map().append(asset);
    }

    inline fn orphan_assets_map() *std.ArrayList(LoadedAsset) {
        return &instance.orphan_assets_maps[instance.orphan_assets_active_idx];
    }

    inline fn last_orphan_assets_map() *std.ArrayList(LoadedAsset) {
        return &instance.orphan_assets_maps[(if (instance.orphan_assets_active_idx == 0) instance.orphan_assets_maps.len else instance.orphan_assets_active_idx) - 1];
    }

    fn loadImage(handle: ImageHandle, ptr: ?*ImageHandle.BackingType) !void {
        const bytes = try instance.loaders.resource(instance.allocator, handle.uuid, default_max_bytes);
        defer instance.allocator.free(bytes);

        const image = ptr orelse try instance.allocator.create(Image);
        errdefer if (ptr == null) instance.allocator.destroy(image);
        image.* = try texs.loadImage(instance.engine, bytes, handle);

        const loaded = LoadedAsset.init(instance.allocator, handle.toAssetHandle(), .{ .image = image });
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(handle.uuid, {});
    }

    fn loadTexture(handle: TextureHandle, ptr: ?*TextureHandle.BackingType) !void {
        const image = try get(handle.toImage());

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

        const sampler_ci = std.mem.zeroInit(c.VkSamplerCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = c.VK_FILTER_NEAREST,
            .minFilter = c.VK_FILTER_NEAREST,
            .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        });
        var sampler: c.VkSampler = undefined;
        try check_vk(c.vkCreateSampler(instance.engine.device, &sampler_ci, Engine.vk_alloc_cbs, &sampler));

        var texture = ptr orelse try instance.allocator.create(Texture);
        texture.* = Texture{
            .handle = handle,
            .image = image.handle,
            .sampler = sampler,
            .image_view = null,
        };

        check_vk(c.vkCreateImageView(instance.engine.device, &image_view_ci, Engine.vk_alloc_cbs, &texture.image_view)) catch @panic("Failed to create image view");

        const loaded = LoadedAsset.init(instance.allocator, handle.toAssetHandle(), .{ .texture = texture });
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(handle.uuid, {});

        try dependency(
            image.handle.toAssetHandle(),
            texture.handle.toAssetHandle(),
        );
    }

    fn loadColorTexture(color: RGBA8, handle: TextureHandle) !void {
        const image = img: { // create the 1x1 image
            const image_handle = handle.toImage();
            const image = try instance.allocator.create(Image);
            errdefer instance.allocator.destroy(image);
            image.* = try texs.loadImageFromPixels(instance.engine, &color, 1, 1, c.VK_FORMAT_R8G8B8A8_UNORM, image_handle);
            const loaded = LoadedAsset.init(instance.allocator, image.handle.toAssetHandle(), .{ .image = image });
            try instance.loaded_assets.put(image_handle.toAssetHandle(), loaded);
            try instance.loaded_ids.put(image_handle.uuid, {});
            break :img try get(image_handle);
        };

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

        const sampler_ci = std.mem.zeroInit(c.VkSamplerCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = c.VK_FILTER_NEAREST,
            .minFilter = c.VK_FILTER_NEAREST,
            .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        });
        var sampler: c.VkSampler = undefined;
        try check_vk(c.vkCreateSampler(instance.engine.device, &sampler_ci, Engine.vk_alloc_cbs, &sampler));

        var texture = try instance.allocator.create(Texture);
        texture.* = Texture{
            .handle = handle,
            .image = image.handle,
            .sampler = sampler,
            .image_view = null,
        };

        check_vk(c.vkCreateImageView(instance.engine.device, &image_view_ci, Engine.vk_alloc_cbs, &texture.image_view)) catch @panic("Failed to create image view");

        const loaded = LoadedAsset.init(instance.allocator, handle.toAssetHandle(), .{ .texture = texture });
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(handle.uuid, {});
        try dependency(
            image.handle.toAssetHandle(),
            texture.handle.toAssetHandle(),
        );
    }

    fn loadMesh(handle: MeshHandle, ptr: ?*MeshHandle.BackingType) !void {
        const bytes = try instance.loaders.resource(instance.allocator, handle.uuid, default_max_bytes);
        defer instance.allocator.free(bytes);

        const mesh = ptr orelse try instance.allocator.create(Mesh);
        mesh.* = components.mesh.load_from_obj(instance.allocator, handle, bytes);
        instance.engine.uploadMesh(mesh);

        const loaded = LoadedAsset.init(instance.allocator, handle.toAssetHandle(), .{ .mesh = mesh });
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(handle.uuid, {});
    }

    fn loadMaterial(handle: MaterialHandle, ptr: ?*MaterialHandle.BackingType) !void {
        const material_def = try instance.loaders.material_def(handle.uuid);

        const shader_def = try instance.loaders.shader_def(material_def.shader);
        const shader = try get(ShaderHandle{ .uuid = material_def.shader });
        errdefer release(shader) catch |err| {
            log.err("Failed to release shader on error loading the material {s}, {} ", .{ handle.uuid.urn(), err });
        };

        const material = ptr orelse try instance.allocator.create(Material);

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

        // New layout for push constants
        const push_constant_range = std.mem.zeroInit(c.VkPushConstantRange, .{
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
            .offset = 0,
            .size = @sizeOf(Engine.MeshPushConstants),
        });

        var set_layouts = [3]c.VkDescriptorSetLayout{
            instance.engine.global_set_layout,
            instance.engine.object_set_layout,
            instance.engine.getDescriptorSetLayout(shader_def.layout) catch @panic("Failed to create shader resouces descriptor set layout"),
        };
        const resources_handles = try instance.allocator.alloc(AssetHandle, material_def.resources.len);

        // Allocate descriptor set for shader resources
        const descriptor_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = instance.engine.descriptor_pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &set_layouts[2],
        });

        var resource_set: c.VkDescriptorSet = undefined;
        try check_vk(c.vkAllocateDescriptorSets(instance.engine.device, &descriptor_set_alloc_info, &resource_set));

        for (shader_def.layout, material_def.resources, 0..) |uniform, resource, i| {
            switch (uniform.kind) {
                .texture => {
                    const tex = try resource.get(.texture);
                    resources_handles[i] = tex.handle.toAssetHandle();

                    const descriptor_image_info = std.mem.zeroInit(c.VkDescriptorImageInfo, .{
                        .sampler = tex.sampler,
                        .imageView = tex.image_view,
                        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    });

                    const write_descriptor_set = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
                        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .dstSet = resource_set,
                        .dstBinding = @as(u32, @intCast(i)),
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

        pipeline_builder.shader_stages[0].module = shader.modules.vertex;
        pipeline_builder.shader_stages[1].module = shader.modules.fragment;
        pipeline_builder.pipeline_layout = pipeline_layout;
        const pipeline = pipeline_builder.build(instance.engine.device, instance.engine.render_pass);

        material.* = Material{
            .handle = handle,
            .shader = shader.handle,

            .pipeline = pipeline,
            .pipeline_layout = pipeline_layout,

            .rsc_count = @intCast(resources_handles.len),
            .rsc_handles = resources_handles.ptr,
            .rsc_descriptor_set = resource_set,
        };

        const loaded = LoadedAsset.init(instance.allocator, handle.toAssetHandle(), .{ .material = material });
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(handle.uuid, {});

        for (material.rsc_handles[0..material.rsc_count]) |rsc| {
            try dependency(rsc, material.handle.toAssetHandle());
        }
        try dependency(
            shader.handle.toAssetHandle(),
            material.handle.toAssetHandle(),
        );
    }

    fn loadShader(handle: ShaderHandle, ptr: ?*ShaderHandle.BackingType) !void {
        const shader_def = try instance.loaders.shader_def(handle.uuid);
        const shader = ptr orelse try instance.allocator.create(Shader);

        const vert_code = try instance.loaders.resource(instance.allocator, shader_def.passes.vertex, 20_000);
        defer instance.allocator.free(vert_code);
        const vert_module = instance.engine.createShaderModule(vert_code) orelse null;
        errdefer c.vkDestroyShaderModule(instance.engine.device, vert_module, Engine.vk_alloc_cbs);

        if (vert_module == null) return error.FailedToLoadVertModule;

        log.info("vert module loaded successfully: {s}", .{handle.uuid.urn()});

        const frag_code = try instance.loaders.resource(instance.allocator, shader_def.passes.fragment, 20_000);
        defer instance.allocator.free(frag_code);
        const frag_module = instance.engine.createShaderModule(frag_code) orelse null;
        errdefer c.vkDestroyShaderModule(instance.engine.device, frag_module, Engine.vk_alloc_cbs);

        if (frag_module == null) return error.FailedToLoadFragModule;

        log.info("frag module loaded successfully: {s}", .{handle.uuid.urn()});

        shader.* = Shader{
            .handle = handle,
            .modules = .{ .vertex = vert_module, .fragment = frag_module },
        };

        const loaded = LoadedAsset.init(instance.allocator, handle.toAssetHandle(), .{ .shader = shader });
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(handle.uuid, {});
    }

    fn loadScene(handle: SceneHandle) !void {
        const bytes = try instance.loaders.resource(instance.allocator, handle.uuid, default_max_bytes);
        defer instance.allocator.free(bytes);

        const scene = try Scene.fromJson(instance.allocator, bytes, .{});
        scene.handle = handle;

        const loaded = LoadedAsset.init(instance.allocator, handle.toAssetHandle(), .{ .scene = scene });
        try instance.loaded_assets.put(handle.toAssetHandle(), loaded);
        try instance.loaded_ids.put(handle.uuid, {});
    }

    inline fn getLoadedAsset(hndl: AssetHandle) !*LoadedAsset {
        const it = instance.loaded_assets.getPtr(hndl) orelse return error.AssetNotLoaded;
        return it;
    }
};

pub const AssetType = enum(u8) {
    binary,
    image,
    texture,
    mesh,
    material,
    shader,
    scene,

    pub fn BackingType(ty: AssetType) type {
        return switch (ty) {
            .binary => []u8,
            .image => Image,
            .texture => Texture,
            .mesh => Mesh,
            .material => Material,
            .shader => Shader,
            .scene => Scene,
        };
    }

    pub fn HandleType(ty: AssetType) type {
        return switch (ty) {
            .binary => BinaryHandle,
            .image => ImageHandle,
            .texture => TextureHandle,
            .mesh => MeshHandle,
            .material => MaterialHandle,
            .shader => ShaderHandle,
            .scene => SceneHandle,
        };
    }
};

pub const AssetHandle = extern struct {
    uuid: Uuid,
    type: AssetType,

    pub inline fn unbox(handle: AssetHandle, comptime expect: AssetType) expect.HandleType() {
        std.debug.assert(handle.type == expect);
        return .{ .uuid = handle.uuid };
    }

    pub inline fn toAssetHandle(handle: AssetHandle) AssetHandle {
        return handle;
    }

    pub fn format(handle: AssetHandle, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        _ = try writer.print("[{s}]({s})", .{ @tagName(handle.type), handle.uuid.urn() });
    }

    pub fn eql(lhs: AssetHandle, rhs: AssetHandle) bool {
        return lhs.type == rhs.type and lhs.uuid.raw == rhs.uuid.raw;
    }
};

pub fn AssetHandleOf(comptime tag: AssetType, comptime opts: struct {
    extensions: type = struct {},
    overrides: type = struct {},
}) type {
    return extern struct {
        pub usingnamespace opts.extensions;

        pub const BackingType = tag.BackingType();
        pub const Tag = tag;

        uuid: Uuid,

        pub inline fn toAssetHandle(hndl: @This()) AssetHandle {
            if (comptime @hasDecl(opts.overrides, "toAssetHandle")) {
                return opts.overrides.toAssetHandle(hndl);
            } else {
                return .{
                    .uuid = hndl.uuid,
                    .type = @This().Tag,
                };
            }
        }

        inline fn fromAssetHandleUnsafe(hndl: AssetHandle) @This() {
            if (comptime @hasDecl(opts.overrides, "fromAssetHandleUnsafe")) {
                return opts.overrides.fromAssetHandleUnsafe(hndl);
            } else {
                return fromAssetIdUnsafe(hndl.uuid);
            }
        }

        inline fn fromAssetIdUnsafe(id: Uuid) @This() {
            if (comptime @hasDecl(opts.overrides, "fromAssetIdUnsafe")) {
                return opts.overrides.fromAssetIdUnsafe(id);
            } else {
                return .{ .uuid = id };
            }
        }

        pub fn jsonStringify(hndl: @This(), jws: anytype) !void {
            try jws.write(hndl.uuid);
        }

        pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, po: std.json.ParseOptions) !@This() {
            return .{ .uuid = try Uuid.jsonParse(a, jrs, po) };
        }
    };
}

pub const BinaryHandle = AssetHandleOf(.binary, .{});
pub const ImageHandle = AssetHandleOf(.image, .{
    .extensions = struct {
        pub inline fn fromTexture(tex: TextureHandle) ImageHandle {
            return TextureHandle.toImage(tex);
        }

        pub inline fn toTexture(img: ImageHandle) TextureHandle {
            return TextureHandle.fromImage(img);
        }
    },
});
pub const TextureHandle = AssetHandleOf(.texture, .{
    .extensions = struct {
        // perhaps use a mask over this? given the randomness of UUID this should work at least for now
        pub const offset_with_image = 1;

        pub inline fn fromImage(img: ImageHandle) TextureHandle {
            return .{ .uuid = .{ .raw = img.uuid.raw + offset_with_image } };
        }

        pub inline fn toImage(tex: TextureHandle) ImageHandle {
            return .{ .uuid = .{ .raw = tex.uuid.raw - offset_with_image } };
        }
    },
});
pub const MeshHandle = AssetHandleOf(.mesh, .{});
pub const MaterialHandle = AssetHandleOf(.material, .{});
pub const ShaderHandle = AssetHandleOf(.shader, .{});
pub const SceneHandle = AssetHandleOf(.scene, .{});

pub const AssetHooks = struct {
    pub const OnReload = Event(.{AssetHandle});
    on_reload: OnReload.List,

    fn init(allocator: std.mem.Allocator) AssetHooks {
        return .{
            .on_reload = OnReload.List.init(allocator),
        };
    }

    fn deinit(hooks: *AssetHooks) void {
        hooks.on_reload.deinit();
    }
};

const LoadedAsset = struct {
    const Self = @This();
    pub const Data = union(AssetType) {
        binary: *[]u8,
        image: *Image,
        texture: *Texture,
        mesh: *Mesh,
        material: *Material,
        shader: *Shader,
        scene: *Scene,

        pub fn clone(data: *const Data, allocator: std.mem.Allocator) !Data {
            switch (data.*) {
                .binary => @panic("TODO"),
                .image => |it| {
                    const orphan_data = try allocator.create(Image);
                    orphan_data.* = it.*;
                    return .{ .image = orphan_data };
                },
                .texture => |it| {
                    const orphan_data = try allocator.create(Texture);
                    orphan_data.* = it.*;
                    return .{ .texture = orphan_data };
                },
                .mesh => |it| {
                    const orphan_data = try allocator.create(Mesh);
                    orphan_data.* = it.*;
                    return .{ .mesh = orphan_data };
                },
                .material => |it| {
                    const orphan_data = try allocator.create(Material);
                    orphan_data.* = it.*;
                    return .{ .material = orphan_data };
                },
                .shader => |it| {
                    const orphan_data = try allocator.create(Shader);
                    orphan_data.* = it.*;
                    return .{ .shader = orphan_data };
                },
                .scene => |it| {
                    const orphan_data = try allocator.create(Scene);
                    orphan_data.* = it.*;
                    return .{ .scene = orphan_data };
                },
            }
        }
    };
    handle: AssetHandle,
    data: Data,
    ref_count: usize = 0,
    hooks: AssetHooks,
    dependencies: std.ArrayList(AssetHandle),
    dependants: std.AutoHashMap(AssetHandle, usize),

    pub fn assetType(self: *const Self) AssetType {
        return @enumFromInt(@intFromEnum(self.data));
    }

    fn init(allocator: std.mem.Allocator, handle: AssetHandle, data: Data) LoadedAsset {
        return .{
            .handle = handle,
            .data = data,
            .hooks = AssetHooks.init(allocator),
            .dependencies = std.ArrayList(AssetHandle).init(allocator),
            .dependants = std.AutoHashMap(AssetHandle, usize).init(allocator),
        };
    }

    fn unload(self: *Self, comptime opts: struct { orphan: bool = false }) void {
        log.debug("unload {}", .{self.handle});
        if (comptime !opts.orphan) {
            if (self.dependants.count() > 0) {
                var iter = self.dependants.iterator();
                while (iter.next()) |kv| {
                    log.err("Unexpected attempt to unload the {} while depended on by {}, depended N: {d}", .{ self.handle, kv.key_ptr.*, kv.value_ptr.* });
                }
                std.debug.assert(false); // all dependencies should've already been unloaded

            }
        }
        switch (self.data) {
            .binary => {
                const it = self.data.binary;
                Assets.instance.allocator.free(it.*);
                Assets.instance.allocator.destroy(it);
            },
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

                var sampler_del = Engine.VulkanDeleter.make(it.sampler, c.vkDestroySampler);
                sampler_del.delete(Assets.instance.engine);

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
                const slice = it.rsc_handles[0..@intCast(it.rsc_count)];
                // TODO: this should only happen in the editor builds
                check_vk(c.vkFreeDescriptorSets(
                    Assets.instance.engine.device,
                    Assets.instance.engine.descriptor_pool,
                    1,
                    &[_]c.VkDescriptorSet{it.rsc_descriptor_set},
                )) catch @panic("failed to free descriptor set");
                Assets.instance.allocator.free(slice);
                Assets.instance.allocator.destroy(it);
            },
            .shader => {
                const it = self.data.shader;
                c.vkDestroyShaderModule(Assets.instance.engine.device, it.modules.vertex, Engine.vk_alloc_cbs);
                c.vkDestroyShaderModule(Assets.instance.engine.device, it.modules.fragment, Engine.vk_alloc_cbs);
                Assets.instance.allocator.destroy(it);
            },
            .scene => {
                const it = self.data.scene;
                it.deinit();
            },
        }

        for (self.dependencies.items) |dep| {
            Assets.undependency(dep, self.handle) catch |err| {
                log.err(
                    "Failed to undeclare the dependency between {s} and {s}, {}",
                    .{ dep, self.handle, err },
                );
            };
            if (comptime !opts.orphan) Assets.release(dep) catch |err| {
                log.err(
                    "Failed to release {s} dependency of {s}, {}",
                    .{ dep, self.handle, err },
                );
            };
        }

        self.hooks.deinit();
        self.dependants.deinit();
        self.dependencies.deinit();
    }
};
