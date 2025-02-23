const std = @import("std");
// const edc = @import("v.zig");

const yume = @import("yume");
const c = @import("clibs");
const edc = @import("edclibs");

const VulkanEngine = yume.VulkanEngine;

const vki = yume.vki;
const check_vk = vki.check_vk;
const mesh_mod = yume.Mesh;
const Mesh = mesh_mod.Mesh;

const math3d = yume.math3d;
const Vec2 = math3d.Vec2;
const Vec3 = math3d.Vec3;
const Vec4 = math3d.Vec4;
const Mat4 = math3d.Mat4;

const AllocatedBuffer = VulkanEngine.AllocatedBuffer;
const AllocatedImage = VulkanEngine.AllocatedImage;

const texs = yume.textures;
const Texture = texs.Texture;

const log = std.log.scoped(.vulkan_engine);

const Self = @This();

const window_extent = c.VkExtent2D{ .width = 1600, .height = 900 };

const VK_NULL_HANDLE = null;

const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;

// Scene management
const Material = struct {
    texture_set: c.VkDescriptorSet = VK_NULL_HANDLE,
    pipeline: c.VkPipeline,
    pipeline_layout: c.VkPipelineLayout,
};

const RenderObject = struct {
    name: [*c]const u8,
    mesh: *Mesh,
    material: *Material,
    transform: Mat4,
};

const FrameData = struct {
    present_semaphore: c.VkSemaphore = VK_NULL_HANDLE,
    render_semaphore: c.VkSemaphore = VK_NULL_HANDLE,
    render_fence: c.VkFence = VK_NULL_HANDLE,
    command_pool: c.VkCommandPool = VK_NULL_HANDLE,
    main_command_buffer: c.VkCommandBuffer = VK_NULL_HANDLE,

    object_buffer: AllocatedBuffer = .{ .buffer = VK_NULL_HANDLE, .allocation = VK_NULL_HANDLE },
    object_descriptor_set: c.VkDescriptorSet = VK_NULL_HANDLE,
};

const GPUCameraData = struct {
    view: Mat4,
    proj: Mat4,
    view_proj: Mat4,
};

const GPUSceneData = struct {
    fog_color: Vec4,
    fog_distance: Vec4, // x = start, y = end
    ambient_color: Vec4,
    sunlight_dir: Vec4,
    sunlight_color: Vec4,
};

const GPUObjectData = struct {
    model_matrix: Mat4,
};

const UploadContext = struct {
    upload_fence: c.VkFence = VK_NULL_HANDLE,
    command_pool: c.VkCommandPool = VK_NULL_HANDLE,
    command_buffer: c.VkCommandBuffer = VK_NULL_HANDLE,
};

const FRAME_OVERLAP = 2;

// Data
//
frame_number: i32 = 0,
selected_shader: i32 = 0,
selected_mesh: i32 = 0,

window: *c.SDL_Window = undefined,

// Keep this around for long standing allocations
allocator: std.mem.Allocator = undefined,

// Vulkan data
instance: c.VkInstance = VK_NULL_HANDLE,
debug_messenger: c.VkDebugUtilsMessengerEXT = VK_NULL_HANDLE,

physical_device: c.VkPhysicalDevice = VK_NULL_HANDLE,
physical_device_properties: c.VkPhysicalDeviceProperties = undefined,

device: c.VkDevice = VK_NULL_HANDLE,
surface: c.VkSurfaceKHR = VK_NULL_HANDLE,

swapchain: c.VkSwapchainKHR = VK_NULL_HANDLE,
swapchain_format: c.VkFormat = undefined,
swapchain_extent: c.VkExtent2D = undefined,
swapchain_images: []c.VkImage = undefined,
swapchain_image_views: []c.VkImageView = undefined,

graphics_queue: c.VkQueue = VK_NULL_HANDLE,
graphics_queue_family: u32 = undefined,
present_queue: c.VkQueue = VK_NULL_HANDLE,
present_queue_family: u32 = undefined,

render_pass: c.VkRenderPass = VK_NULL_HANDLE,
framebuffers: []c.VkFramebuffer = undefined,

depth_image_view: c.VkImageView = VK_NULL_HANDLE,
depth_image: AllocatedImage = undefined,
depth_format: c.VkFormat = undefined,

upload_context: UploadContext = .{},

frames: [FRAME_OVERLAP]FrameData = .{FrameData{}} ** FRAME_OVERLAP,

camera_and_scene_set: c.VkDescriptorSet = VK_NULL_HANDLE,
camera_and_scene_buffer: AllocatedBuffer = undefined,

global_set_layout: c.VkDescriptorSetLayout = VK_NULL_HANDLE,
object_set_layout: c.VkDescriptorSetLayout = VK_NULL_HANDLE,
single_texture_set_layout: c.VkDescriptorSetLayout = VK_NULL_HANDLE,
descriptor_pool: c.VkDescriptorPool = VK_NULL_HANDLE,

vma_allocator: c.VmaAllocator = undefined,

renderables: std.ArrayList(RenderObject),
materials: std.StringHashMap(Material),
meshes: std.StringHashMap(Mesh),
textures: std.StringHashMap(Texture),

camera_pos: Vec3 = Vec3.make(0.0, -3.0, -10.0),
camera_input: Vec3 = Vec3.make(0.0, 0.0, 0.0),

deletion_queue: std.ArrayList(VulkanDeleter) = undefined,
buffer_deletion_queue: std.ArrayList(VmaBufferDeleter) = undefined,
image_deletion_queue: std.ArrayList(VmaImageDeleter) = undefined,

// imgui state
play: bool = false,
imgui_demo_open: bool = false,

first_time: bool = true,
game_view_size: edc.ImVec2 = std.mem.zeroInit(edc.ImVec2, .{}),
mouse: edc.ImVec2 = std.mem.zeroInit(edc.ImVec2, .{}),
game_window_rect: edc.ImVec4 = std.mem.zeroInit(edc.ImVec4, .{}),
is_game_window_active: bool = false,
is_game_window_focused: bool = false,

play_icon_ds: c.VkDescriptorSet = undefined,
pause_icon_ds: c.VkDescriptorSet = undefined,
stop_icon_ds: c.VkDescriptorSet = undefined,
fast_forward_icon_ds: c.VkDescriptorSet = undefined,

pub const MeshPushConstants = struct {
    data: Vec4,
    render_matrix: Mat4,
};

pub const VulkanDeleter = struct {
    object: ?*anyopaque,
    delete_fn: *const fn (entry: *VulkanDeleter, self: *Self) void,

    fn delete(self: *VulkanDeleter, engine: *Self) void {
        self.delete_fn(self, engine);
    }

    fn make(object: anytype, func: anytype) VulkanDeleter {
        const T = @TypeOf(object);
        comptime {
            std.debug.assert(@typeInfo(T) == .Optional);
            const Ptr = @typeInfo(T).Optional.child;
            std.debug.assert(@typeInfo(Ptr) == .Pointer);
            std.debug.assert(@typeInfo(Ptr).Pointer.size == .One);

            const Fn = @TypeOf(func);
            std.debug.assert(@typeInfo(Fn) == .Fn);
        }

        return VulkanDeleter{
            .object = object,
            .delete_fn = struct {
                fn destroy_impl(entry: *VulkanDeleter, self: *Self) void {
                    const obj: @TypeOf(object) = @ptrCast(entry.object);
                    func(self.device, obj, vk_alloc_cbs);
                }
            }.destroy_impl,
        };
    }
};

pub const VmaBufferDeleter = struct {
    buffer: AllocatedBuffer,

    fn delete(self: *VmaBufferDeleter, engine: *Self) void {
        c.vmaDestroyBuffer(engine.vma_allocator, self.buffer.buffer, self.buffer.allocation);
    }
};

pub const VmaImageDeleter = struct {
    image: AllocatedImage,

    fn delete(self: *VmaImageDeleter, engine: *Self) void {
        c.vmaDestroyImage(engine.vma_allocator, self.image.image, self.image.allocation);
    }
};

pub fn init(a: std.mem.Allocator) Self {
    check_sdl(c.SDL_Init(c.SDL_INIT_VIDEO));

    const window = c.SDL_CreateWindow("Vulkan", window_extent.width, window_extent.height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse @panic("Failed to create SDL window");

    _ = c.SDL_ShowWindow(window);

    var engine = Self{
        .window = window,
        .allocator = a,
        .deletion_queue = std.ArrayList(VulkanDeleter).init(a),
        .buffer_deletion_queue = std.ArrayList(VmaBufferDeleter).init(a),
        .image_deletion_queue = std.ArrayList(VmaImageDeleter).init(a),
        .renderables = std.ArrayList(RenderObject).init(a),
        .materials = std.StringHashMap(Material).init(a),
        .meshes = std.StringHashMap(Mesh).init(a),
        .textures = std.StringHashMap(Texture).init(a),
    };

    engine.init_instance();

    // Create the window surface
    check_sdl_bool(c.SDL_Vulkan_CreateSurface(window, engine.instance, vk_alloc_cbs, &engine.surface));

    engine.init_device();

    // Create a VMA allocator
    const allocator_ci = std.mem.zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = engine.physical_device,
        .device = engine.device,
        .instance = engine.instance,
    });
    check_vk(c.vmaCreateAllocator(&allocator_ci, &engine.vma_allocator)) catch @panic("Failed to create VMA allocator");

    engine.init_swapchain();
    engine.init_commands();
    engine.init_default_renderpass();
    engine.init_framebuffers();
    engine.init_sync_structures();
    engine.init_descriptors();
    engine.init_pipelines();
    engine.load_textures();
    engine.load_meshes();
    engine.init_scene();
    engine.init_imgui();

    return engine;
}

fn init_instance(self: *Self) void {
    var sdl_required_extension_count: u32 = undefined;
    const sdl_extensions = c.SDL_Vulkan_GetInstanceExtensions(&sdl_required_extension_count);
    const sdl_extension_slice = sdl_extensions[0..sdl_required_extension_count];

    // Instance creation and optional debug utilities
    const instance = vki.create_instance(std.heap.page_allocator, .{
        .application_name = "yume",
        .application_version = c.VK_MAKE_VERSION(0, 1, 0),
        .engine_name = "yume",
        .engine_version = c.VK_MAKE_VERSION(0, 1, 0),
        .api_version = c.VK_MAKE_VERSION(1, 1, 0),
        .debug = true,
        .required_extensions = sdl_extension_slice,
    }) catch |err| {
        log.err("Failed to create vulkan instance with error: {s}", .{@errorName(err)});
        unreachable;
    };

    self.instance = instance.handle;
    self.debug_messenger = instance.debug_messenger;
}

fn init_device(self: *Self) void {
    // Physical device selection
    const required_device_extensions: []const [*c]const u8 = &.{
        "VK_KHR_swapchain",
    };

    const physical_device = vki.select_physical_device(std.heap.page_allocator, self.instance, .{
        .min_api_version = c.VK_MAKE_VERSION(1, 1, 0),
        .required_extensions = required_device_extensions,
        .surface = self.surface,
        .criteria = .PreferDiscrete,
    }) catch |err| {
        log.err("Failed to select physical device with error: {s}", .{@errorName(err)});
        unreachable;
    };

    self.physical_device = physical_device.handle;
    self.physical_device_properties = physical_device.properties;

    log.info("The GPU has a minimum buffer alignment of {} bytes", .{physical_device.properties.limits.minUniformBufferOffsetAlignment});

    self.graphics_queue_family = physical_device.graphics_queue_family;
    self.present_queue_family = physical_device.present_queue_family;

    const shader_draw_parameters_features = std.mem.zeroInit(c.VkPhysicalDeviceShaderDrawParametersFeatures, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
        .shaderDrawParameters = c.VK_TRUE,
    });

    // Create a logical device
    const device = vki.create_logical_device(self.allocator, .{
        .physical_device = physical_device,
        .features = std.mem.zeroInit(c.VkPhysicalDeviceFeatures, .{}),
        .alloc_cb = vk_alloc_cbs,
        .pnext = &shader_draw_parameters_features,
    }) catch @panic("Failed to create logical device");

    self.device = device.handle;
    self.graphics_queue = device.graphics_queue;
    self.present_queue = device.present_queue;
}

fn init_swapchain(self: *Self) void {
    var win_width: c_int = undefined;
    var win_height: c_int = undefined;
    check_sdl(c.SDL_GetWindowSize(self.window, &win_width, &win_height));

    // Create a swapchain
    const swapchain = vki.create_swapchain(self.allocator, .{
        .physical_device = self.physical_device,
        .graphics_queue_family = self.graphics_queue_family,
        .present_queue_family = self.graphics_queue_family,
        .device = self.device,
        .surface = self.surface,
        .old_swapchain = null,
        .vsync = true,
        .window_width = @intCast(win_width),
        .window_height = @intCast(win_height),
        .alloc_cb = vk_alloc_cbs,
    }) catch @panic("Failed to create swapchain");

    self.swapchain = swapchain.handle;
    self.swapchain_format = swapchain.format;
    self.swapchain_extent = swapchain.extent;
    self.swapchain_images = swapchain.images;
    self.swapchain_image_views = swapchain.image_views;

    for (self.swapchain_image_views) |view|
        self.deletion_queue.append(VulkanDeleter.make(view, c.vkDestroyImageView)) catch @panic("Out of memory");
    self.deletion_queue.append(VulkanDeleter.make(swapchain.handle, c.vkDestroySwapchainKHR)) catch @panic("Out of memory");

    log.info("Created swapchain", .{});

    // Create depth image to associate with the swapchain
    const extent = c.VkExtent3D{
        .width = self.swapchain_extent.width,
        .height = self.swapchain_extent.height,
        .depth = 1,
    };

    // Hard-coded 32-bit float depth format
    self.depth_format = c.VK_FORMAT_D32_SFLOAT;

    const depth_image_ci = std.mem.zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.depth_format,
        .extent = extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    });

    const depth_image_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    });

    check_vk(c.vmaCreateImage(self.vma_allocator, &depth_image_ci, &depth_image_ai, &self.depth_image.image, &self.depth_image.allocation, null)) catch @panic("Failed to create depth image");

    const depth_image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.depth_image.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = self.depth_format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });

    check_vk(c.vkCreateImageView(self.device, &depth_image_view_ci, vk_alloc_cbs, &self.depth_image_view)) catch @panic("Failed to create depth image view");

    self.deletion_queue.append(VulkanDeleter.make(self.depth_image_view, c.vkDestroyImageView)) catch @panic("Out of memory");
    self.image_deletion_queue.append(VmaImageDeleter{ .image = self.depth_image }) catch @panic("Out of memory");

    log.info("Created depth image", .{});
}

fn init_commands(self: *Self) void {
    // Create a command pool
    const command_pool_ci = std.mem.zeroInit(c.VkCommandPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = self.graphics_queue_family,
    });

    for (&self.frames) |*frame| {
        check_vk(c.vkCreateCommandPool(self.device, &command_pool_ci, vk_alloc_cbs, &frame.command_pool)) catch log.err("Failed to create command pool", .{});
        self.deletion_queue.append(VulkanDeleter.make(frame.command_pool, c.vkDestroyCommandPool)) catch @panic("Out of memory");

        // Allocate a command buffer from the command pool
        const command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = frame.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        });

        check_vk(c.vkAllocateCommandBuffers(self.device, &command_buffer_ai, &frame.main_command_buffer)) catch @panic("Failed to allocate command buffer");

        log.info("Created command pool and command buffer", .{});
    }

    // =================================
    // Upload context
    //

    // For the time being this is submitting on the graphics queue
    const upload_command_pool_ci = std.mem.zeroInit(c.VkCommandPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = 0,
        .queueFamilyIndex = self.graphics_queue_family,
    });

    check_vk(c.vkCreateCommandPool(self.device, &upload_command_pool_ci, vk_alloc_cbs, &self.upload_context.command_pool)) catch @panic("Failed to create upload command pool");
    self.deletion_queue.append(VulkanDeleter.make(self.upload_context.command_pool, c.vkDestroyCommandPool)) catch @panic("Out of memory");

    const upload_command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.upload_context.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });

    check_vk(c.vkAllocateCommandBuffers(self.device, &upload_command_buffer_ai, &self.upload_context.command_buffer)) catch @panic("Failed to allocate upload command buffer");
}

fn init_default_renderpass(self: *Self) void {
    // Color attachement
    const color_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.swapchain_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    });

    const color_attachment_ref = std.mem.zeroInit(c.VkAttachmentReference, .{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    });

    // Depth attachment
    const depth_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.depth_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });

    const depth_attachement_ref = std.mem.zeroInit(c.VkAttachmentReference, .{
        .attachment = 1,
        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });

    // Subpass
    const subpass = std.mem.zeroInit(c.VkSubpassDescription, .{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
        .pDepthStencilAttachment = &depth_attachement_ref,
    });

    const attachment_descriptions = [_]c.VkAttachmentDescription{
        color_attachment,
        depth_attachment,
    };

    // Subpass color and depth depencies
    const color_dependency = std.mem.zeroInit(c.VkSubpassDependency, .{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    });

    const depth_dependency = std.mem.zeroInit(c.VkSubpassDependency, .{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        .srcAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        .dstAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
    });

    const dependecies = [_]c.VkSubpassDependency{
        color_dependency,
        depth_dependency,
    };

    const render_pass_create_info = std.mem.zeroInit(c.VkRenderPassCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = @as(u32, @intCast(attachment_descriptions.len)),
        .pAttachments = attachment_descriptions[0..].ptr,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = @as(u32, @intCast(dependecies.len)),
        .pDependencies = &dependecies[0],
    });

    check_vk(c.vkCreateRenderPass(self.device, &render_pass_create_info, vk_alloc_cbs, &self.render_pass)) catch @panic("Failed to create render pass");
    self.deletion_queue.append(VulkanDeleter.make(self.render_pass, c.vkDestroyRenderPass)) catch @panic("Out of memory");

    log.info("Created render pass", .{});
}

fn init_framebuffers(self: *Self) void {
    var framebuffer_ci = std.mem.zeroInit(c.VkFramebufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = self.render_pass,
        .attachmentCount = 2,
        .width = self.swapchain_extent.width,
        .height = self.swapchain_extent.height,
        .layers = 1,
    });

    self.framebuffers = self.allocator.alloc(c.VkFramebuffer, self.swapchain_image_views.len) catch @panic("Out of memory");

    for (self.swapchain_image_views, self.framebuffers) |view, *framebuffer| {
        const attachements = [2]c.VkImageView{
            view,
            self.depth_image_view,
        };
        framebuffer_ci.pAttachments = &attachements[0];
        check_vk(c.vkCreateFramebuffer(self.device, &framebuffer_ci, vk_alloc_cbs, framebuffer)) catch @panic("Failed to create framebuffer");
        self.deletion_queue.append(VulkanDeleter.make(framebuffer.*, c.vkDestroyFramebuffer)) catch @panic("Out of memory");
    }

    log.info("Created {} framebuffers", .{self.framebuffers.len});
}

fn init_sync_structures(self: *Self) void {
    const semaphore_ci = std.mem.zeroInit(c.VkSemaphoreCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    });

    const fence_ci = std.mem.zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    });

    for (&self.frames) |*frame| {
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.present_semaphore)) catch @panic("Failed to create present semaphore");
        self.deletion_queue.append(VulkanDeleter.make(frame.present_semaphore, c.vkDestroySemaphore)) catch @panic("Out of memory");
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.render_semaphore)) catch @panic("Failed to create render semaphore");
        self.deletion_queue.append(VulkanDeleter.make(frame.render_semaphore, c.vkDestroySemaphore)) catch @panic("Out of memory");

        check_vk(c.vkCreateFence(self.device, &fence_ci, vk_alloc_cbs, &frame.render_fence)) catch @panic("Failed to create render fence");
        self.deletion_queue.append(VulkanDeleter.make(frame.render_fence, c.vkDestroyFence)) catch @panic("Out of memory");
    }

    // Upload context
    const upload_fence_ci = std.mem.zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    });

    check_vk(c.vkCreateFence(self.device, &upload_fence_ci, vk_alloc_cbs, &self.upload_context.upload_fence)) catch @panic("Failed to create upload fence");

    self.deletion_queue.append(VulkanDeleter.make(self.upload_context.upload_fence, c.vkDestroyFence)) catch @panic("Out of memory");

    log.info("Created sync structures", .{});
}

const PipelineBuilder = struct {
    shader_stages: []c.VkPipelineShaderStageCreateInfo,
    vertex_input_state: c.VkPipelineVertexInputStateCreateInfo,
    input_assembly_state: c.VkPipelineInputAssemblyStateCreateInfo,
    viewport: c.VkViewport,
    scissor: c.VkRect2D,
    rasterization_state: c.VkPipelineRasterizationStateCreateInfo,
    color_blend_attachment_state: c.VkPipelineColorBlendAttachmentState,
    multisample_state: c.VkPipelineMultisampleStateCreateInfo,
    pipeline_layout: c.VkPipelineLayout,
    depth_stencil_state: c.VkPipelineDepthStencilStateCreateInfo,

    fn build(self: PipelineBuilder, device: c.VkDevice, render_pass: c.VkRenderPass) c.VkPipeline {
        const viewport_state = std.mem.zeroInit(c.VkPipelineViewportStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .pViewports = &self.viewport,
            .scissorCount = 1,
            .pScissors = &self.scissor,
        });

        const color_blend_state = std.mem.zeroInit(c.VkPipelineColorBlendStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = &self.color_blend_attachment_state,
        });

        const dynamicState = c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = 2,
            .pDynamicStates = &[_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_SCISSOR, c.VK_DYNAMIC_STATE_VIEWPORT },
        };
        const pipeline_ci = std.mem.zeroInit(c.VkGraphicsPipelineCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount = @as(u32, @intCast(self.shader_stages.len)),
            .pStages = self.shader_stages.ptr,
            .pVertexInputState = &self.vertex_input_state,
            .pInputAssemblyState = &self.input_assembly_state,
            .pViewportState = &viewport_state,
            .pRasterizationState = &self.rasterization_state,
            .pMultisampleState = &self.multisample_state,
            .pColorBlendState = &color_blend_state,
            .pDepthStencilState = &self.depth_stencil_state,
            .pDynamicState = &[_]c.VkPipelineDynamicStateCreateInfo{dynamicState},
            .layout = self.pipeline_layout,
            .renderPass = render_pass,
            .subpass = 0,
            .basePipelineHandle = VK_NULL_HANDLE,
        });

        var pipeline: c.VkPipeline = undefined;
        check_vk(c.vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipeline_ci, vk_alloc_cbs, &pipeline)) catch {
            log.err("Failed to create graphics pipeline", .{});
            return VK_NULL_HANDLE;
        };

        return pipeline;
    }
};

fn init_pipelines(self: *Self) void {
    // NOTE: we are currently destroying the shader modules as soon as we are done
    // creating the pipeline. This is not great if we needed the modules for multiple pipelines.
    // Howver, for the sake of simplicity, we are doing it this way for now.
    const red_vert_code align(4) = @embedFile("triangle.vert").*;
    const red_frag_code align(4) = @embedFile("triangle.frag").*;
    const red_vert_module = create_shader_module(self, &red_vert_code) orelse VK_NULL_HANDLE;
    defer c.vkDestroyShaderModule(self.device, red_vert_module, vk_alloc_cbs);
    const red_frag_module = create_shader_module(self, &red_frag_code) orelse VK_NULL_HANDLE;
    defer c.vkDestroyShaderModule(self.device, red_frag_module, vk_alloc_cbs);

    if (red_vert_module != VK_NULL_HANDLE) log.info("Vert module loaded successfully", .{});
    if (red_frag_module != VK_NULL_HANDLE) log.info("Frag module loaded successfully", .{});

    const pipeline_layout_ci = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    });
    var triangle_pipeline_layout: c.VkPipelineLayout = undefined;
    check_vk(c.vkCreatePipelineLayout(self.device, &pipeline_layout_ci, vk_alloc_cbs, &triangle_pipeline_layout)) catch @panic("Failed to create pipeline layout");
    self.deletion_queue.append(VulkanDeleter.make(triangle_pipeline_layout, c.vkDestroyPipelineLayout)) catch @panic("Out of memory");

    const vert_stage_ci = std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = red_vert_module,
        .pName = "main",
    });

    const frag_stage_ci = std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = red_frag_module,
        .pName = "main",
    });

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
        vert_stage_ci,
        frag_stage_ci,
    };
    var pipeline_builder = PipelineBuilder{
        .shader_stages = shader_stages[0..],
        .vertex_input_state = vertex_input_state_ci,
        .input_assembly_state = input_assembly_state_ci,
        .viewport = .{
            .x = 0.0,
            .y = 0.0,
            .width = @as(f32, @floatFromInt(self.swapchain_extent.width)),
            .height = @as(f32, @floatFromInt(self.swapchain_extent.height)),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        },
        .scissor = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        },
        .rasterization_state = rasterization_state_ci,
        .color_blend_attachment_state = color_blend_attachment_state,
        .multisample_state = multisample_state_ci,
        .pipeline_layout = triangle_pipeline_layout,
        .depth_stencil_state = depth_stencil_state_ci,
    };

    const red_triangle_pipeline = pipeline_builder.build(self.device, self.render_pass);
    self.deletion_queue.append(VulkanDeleter.make(red_triangle_pipeline, c.vkDestroyPipeline)) catch @panic("Out of memory");
    if (red_triangle_pipeline == VK_NULL_HANDLE) {
        log.err("Failed to create red triangle pipeline", .{});
    } else {
        log.info("Created red triangle pipeline", .{});
    }

    _ = self.create_material(red_triangle_pipeline, triangle_pipeline_layout, "red_triangle_mat");

    const rgb_vert_code align(4) = @embedFile("colored_triangle.vert").*;
    const rgb_frag_code align(4) = @embedFile("colored_triangle.frag").*;
    const rgb_vert_module = create_shader_module(self, &rgb_vert_code) orelse VK_NULL_HANDLE;
    defer c.vkDestroyShaderModule(self.device, rgb_vert_module, vk_alloc_cbs);
    const rgb_frag_module = create_shader_module(self, &rgb_frag_code) orelse VK_NULL_HANDLE;
    defer c.vkDestroyShaderModule(self.device, rgb_frag_module, vk_alloc_cbs);

    if (rgb_vert_module != VK_NULL_HANDLE) log.info("Vert module loaded successfully", .{});
    if (rgb_frag_module != VK_NULL_HANDLE) log.info("Frag module loaded successfully", .{});

    pipeline_builder.shader_stages[0].module = rgb_vert_module;
    pipeline_builder.shader_stages[1].module = rgb_frag_module;

    const rgb_triangle_pipeline = pipeline_builder.build(self.device, self.render_pass);
    self.deletion_queue.append(VulkanDeleter.make(rgb_triangle_pipeline, c.vkDestroyPipeline)) catch @panic("Out of memory");
    if (rgb_triangle_pipeline == VK_NULL_HANDLE) {
        log.err("Failed to create rgb triangle pipeline", .{});
    } else {
        log.info("Created rgb triangle pipeline", .{});
    }

    _ = self.create_material(rgb_triangle_pipeline, triangle_pipeline_layout, "rgb_triangle_mat");

    // Create pipeline for meshes
    const vertex_descritpion = mesh_mod.Vertex.vertex_input_description;

    pipeline_builder.vertex_input_state.pVertexAttributeDescriptions = vertex_descritpion.attributes.ptr;
    pipeline_builder.vertex_input_state.vertexAttributeDescriptionCount = @as(u32, @intCast(vertex_descritpion.attributes.len));
    pipeline_builder.vertex_input_state.pVertexBindingDescriptions = vertex_descritpion.bindings.ptr;
    pipeline_builder.vertex_input_state.vertexBindingDescriptionCount = @as(u32, @intCast(vertex_descritpion.bindings.len));

    const tri_mesh_vert_code align(4) = @embedFile("tri_mesh.vert").*;
    const tri_mesh_vert_module = create_shader_module(self, &tri_mesh_vert_code) orelse VK_NULL_HANDLE;
    defer c.vkDestroyShaderModule(self.device, tri_mesh_vert_module, vk_alloc_cbs);

    if (tri_mesh_vert_module != VK_NULL_HANDLE) log.info("Tri-mesh vert module loaded successfully", .{});

    // Default lit shader
    const default_lit_frag_code align(4) = @embedFile("default_lit.frag").*;
    const default_lit_frag_module = create_shader_module(self, &default_lit_frag_code) orelse VK_NULL_HANDLE;
    defer c.vkDestroyShaderModule(self.device, default_lit_frag_module, vk_alloc_cbs);

    if (default_lit_frag_module != VK_NULL_HANDLE) log.info("Default lit frag module loaded successfully", .{});

    pipeline_builder.shader_stages[0].module = tri_mesh_vert_module;
    pipeline_builder.shader_stages[1].module = default_lit_frag_module;

    // New layout for push constants
    const push_constant_range = std.mem.zeroInit(c.VkPushConstantRange, .{
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = @sizeOf(MeshPushConstants),
    });

    const set_layouts = [_]c.VkDescriptorSetLayout{
        self.global_set_layout,
        self.object_set_layout,
    };

    const mesh_pipeline_layout_ci = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = @as(u32, @intCast(set_layouts.len)),
        .pSetLayouts = &set_layouts[0],
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_constant_range,
    });

    var mesh_pipeline_layout: c.VkPipelineLayout = undefined;
    check_vk(c.vkCreatePipelineLayout(self.device, &mesh_pipeline_layout_ci, vk_alloc_cbs, &mesh_pipeline_layout)) catch @panic("Failed to create mesh pipeline layout");
    self.deletion_queue.append(VulkanDeleter.make(mesh_pipeline_layout, c.vkDestroyPipelineLayout)) catch @panic("Out of memory");

    pipeline_builder.pipeline_layout = mesh_pipeline_layout;

    const mesh_pipeline = pipeline_builder.build(self.device, self.render_pass);
    self.deletion_queue.append(VulkanDeleter.make(mesh_pipeline, c.vkDestroyPipeline)) catch @panic("Out of memory");
    if (mesh_pipeline == VK_NULL_HANDLE) {
        log.err("Failed to create mesh pipeline", .{});
    } else {
        log.info("Created mesh pipeline", .{});
    }

    _ = self.create_material(mesh_pipeline, mesh_pipeline_layout, "default_mesh");

    // Textured mesh shader
    var textured_pipe_layout_ci = mesh_pipeline_layout_ci;
    const textured_set_layoyts = [_]c.VkDescriptorSetLayout{
        self.global_set_layout,
        self.object_set_layout,
        self.single_texture_set_layout,
    };
    textured_pipe_layout_ci.setLayoutCount = @as(u32, @intCast(textured_set_layoyts.len));
    textured_pipe_layout_ci.pSetLayouts = &textured_set_layoyts[0];

    var textured_pipe_layout: c.VkPipelineLayout = undefined;
    check_vk(c.vkCreatePipelineLayout(self.device, &textured_pipe_layout_ci, vk_alloc_cbs, &textured_pipe_layout)) catch @panic("Failed to create textured mesh pipeline layout");
    self.deletion_queue.append(VulkanDeleter.make(textured_pipe_layout, c.vkDestroyPipelineLayout)) catch @panic("Out of memory");

    const textured_lit_frag_code align(4) = @embedFile("textured_lit.frag").*;
    const textured_lit_frag = create_shader_module(self, &textured_lit_frag_code) orelse VK_NULL_HANDLE;
    defer c.vkDestroyShaderModule(self.device, textured_lit_frag, vk_alloc_cbs);

    pipeline_builder.shader_stages[1].module = textured_lit_frag;
    pipeline_builder.pipeline_layout = textured_pipe_layout;
    const textured_mesh_pipeline = pipeline_builder.build(self.device, self.render_pass);

    _ = self.create_material(textured_mesh_pipeline, textured_pipe_layout, "textured_mesh");
    self.deletion_queue.append(VulkanDeleter.make(textured_mesh_pipeline, c.vkDestroyPipeline)) catch @panic("Out of memory");
}

fn init_descriptors(self: *Self) void {
    // Descriptor pool
    const pool_sizes = [_]c.VkDescriptorPoolSize{
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 10,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
            .descriptorCount = 10,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 10,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 10,
        },
    };

    const pool_ci = std.mem.zeroInit(c.VkDescriptorPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = 0,
        .maxSets = 10,
        .poolSizeCount = @as(u32, @intCast(pool_sizes.len)),
        .pPoolSizes = &pool_sizes[0],
    });

    check_vk(c.vkCreateDescriptorPool(self.device, &pool_ci, vk_alloc_cbs, &self.descriptor_pool)) catch @panic("Failed to create descriptor pool");

    self.deletion_queue.append(VulkanDeleter.make(self.descriptor_pool, c.vkDestroyDescriptorPool)) catch @panic("Out of memory");

    // =========================================================================
    // Information about the binding
    // =========================================================================

    // =================================
    // Global set layout
    //

    // Camera binding
    const camera_buffer_binding = std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
    });

    // Scene param binding
    const scene_parameters_binding = std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{
        .binding = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
    });

    const bindings = [_]c.VkDescriptorSetLayoutBinding{
        camera_buffer_binding,
        scene_parameters_binding,
    };

    const global_set_ci = std.mem.zeroInit(c.VkDescriptorSetLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = @as(u32, @intCast(bindings.len)),
        .pBindings = &bindings[0],
    });

    check_vk(c.vkCreateDescriptorSetLayout(self.device, &global_set_ci, vk_alloc_cbs, &self.global_set_layout)) catch @panic("Failed to create global descriptor set layout");

    self.deletion_queue.append(VulkanDeleter.make(self.global_set_layout, c.vkDestroyDescriptorSetLayout)) catch @panic("Out of memory");

    log.info("Created global set layout", .{});

    // =================================
    // Object set layout
    //

    // Object buffer binding
    const object_buffer_binding = std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
    });

    const object_set_ci = std.mem.zeroInit(c.VkDescriptorSetLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &object_buffer_binding,
    });

    check_vk(c.vkCreateDescriptorSetLayout(self.device, &object_set_ci, vk_alloc_cbs, &self.object_set_layout)) catch @panic("Failed to create object descriptor set layout");

    self.deletion_queue.append(VulkanDeleter.make(self.object_set_layout, c.vkDestroyDescriptorSetLayout)) catch @panic("Out of memory");

    log.info("Created object set layout", .{});

    // Scene and camera (per-frame) in a single buffer
    // Only one buffer and we get multiple offset of of it
    const camera_and_scene_buffer_size =
        FRAME_OVERLAP * self.pad_uniform_buffer_size(@sizeOf(GPUCameraData)) +
        FRAME_OVERLAP * self.pad_uniform_buffer_size(@sizeOf(GPUSceneData));

    self.camera_and_scene_buffer = self.create_buffer(camera_and_scene_buffer_size, c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    self.buffer_deletion_queue.append(VmaBufferDeleter{ .buffer = self.camera_and_scene_buffer }) catch @panic("Out of memory");

    // Camera and scene descriptor set
    const global_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &self.global_set_layout,
    });

    // Allocate a single set for multiple frame worth of camera and scene data
    check_vk(c.vkAllocateDescriptorSets(self.device, &global_set_alloc_info, &self.camera_and_scene_set)) catch @panic("Failed to allocate global descriptor set");

    // Camera
    const camera_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
        .buffer = self.camera_and_scene_buffer.buffer,
        .range = @sizeOf(GPUCameraData),
    });

    const camera_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = self.camera_and_scene_set,
        .dstBinding = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .pBufferInfo = &camera_buffer_info,
    });

    // Scene parameters
    const scene_parameters_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
        .buffer = self.camera_and_scene_buffer.buffer,
        .range = @sizeOf(GPUSceneData),
    });

    const scene_parameters_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = self.camera_and_scene_set,
        .dstBinding = 1,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .pBufferInfo = &scene_parameters_buffer_info,
    });

    const camera_and_scene_writes = [_]c.VkWriteDescriptorSet{
        camera_write,
        scene_parameters_write,
    };

    c.vkUpdateDescriptorSets(self.device, @as(u32, @intCast(camera_and_scene_writes.len)), &camera_and_scene_writes[0], 0, null);

    // =================================
    // Texture set layout
    //
    const texture_bind = std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    });

    const texture_set_ci = std.mem.zeroInit(c.VkDescriptorSetLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &texture_bind,
    });

    check_vk(c.vkCreateDescriptorSetLayout(self.device, &texture_set_ci, vk_alloc_cbs, &self.single_texture_set_layout)) catch @panic("Failed to create texture descriptor set layout");

    self.deletion_queue.append(VulkanDeleter.make(self.single_texture_set_layout, c.vkDestroyDescriptorSetLayout)) catch @panic("Out of memory");

    for (0..FRAME_OVERLAP) |i| {
        // ======================================================================
        // Allocate descriptor sets
        // ======================================================================

        // Object descriptor set
        const object_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = self.descriptor_pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &self.object_set_layout,
        });

        check_vk(c.vkAllocateDescriptorSets(self.device, &object_set_alloc_info, &self.frames[i].object_descriptor_set)) catch @panic("Failed to allocate object descriptor set");

        // ======================================================================
        // Buffer allocations
        // ======================================================================

        // Object buffer
        const MAX_OBJECTS = 10000;
        self.frames[i].object_buffer = self.create_buffer(MAX_OBJECTS * @sizeOf(GPUObjectData), c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
        self.buffer_deletion_queue.append(VmaBufferDeleter{ .buffer = self.frames[i].object_buffer }) catch @panic("Out of memory");

        // ======================================================================
        // Write descriptors
        // ======================================================================

        // =============================
        // Object descriptor set
        //
        const object_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
            .buffer = self.frames[i].object_buffer.buffer,
            .offset = 0,
            .range = MAX_OBJECTS * @sizeOf(GPUObjectData),
        });

        const object_buffer_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = self.frames[i].object_descriptor_set,
            .dstBinding = 0,
            .descriptorCount = 1,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &object_buffer_info,
        });

        const writes = [_]c.VkWriteDescriptorSet{
            object_buffer_write,
        };

        c.vkUpdateDescriptorSets(self.device, @as(u32, @intCast(writes.len)), &writes[0], 0, null);
    }
}

fn create_shader_module(self: *Self, code: []const u8) ?c.VkShaderModule {
    // NOTE: This being a better language than C/C++, means we don´t need to load
    // the SPIR-V code from a file, we can just embed it as an array of bytes.
    // To reflect the different behaviour from the original code, we also changed
    // the function name.
    std.debug.assert(code.len % 4 == 0);

    const data: *const u32 = @alignCast(@ptrCast(code.ptr));

    const shader_module_ci = std.mem.zeroInit(c.VkShaderModuleCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = data,
    });

    var shader_module: c.VkShaderModule = undefined;
    check_vk(c.vkCreateShaderModule(self.device, &shader_module_ci, vk_alloc_cbs, &shader_module)) catch |err| {
        log.err("Failed to create shader module with error: {s}", .{@errorName(err)});
        return null;
    };

    return shader_module;
}

fn init_scene(self: *Self) void {
    const monkey = RenderObject{
        .name = "monkey",
        .mesh = self.meshes.getPtr("monkey") orelse @panic("Failed to get monkey mesh"),
        .material = self.materials.getPtr("default_mesh") orelse @panic("Failed to get default mesh material"),
        .transform = Mat4.IDENTITY,
    };
    self.renderables.append(monkey) catch @panic("Out of memory");

    // const diorama = RenderObject {
    //     .mesh = self.meshes.getPtr("diorama") orelse @panic("Failed to get diorama mesh"),
    //     .material = self.materials.getPtr("default_mesh") orelse @panic("Failed to get default mesh material"),
    //     .transform = Mat4.mul(
    //         Mat4.mul(
    //             m3d.translation(m3d.vec3(3.0, 1, 0)),
    //             m3d.rotation(m3d.vec3(0, 1, 0), std.math.degreesToRadians(f32, -60)),
    //         ),
    //         m3d.scale(m3d.vec3(2.0, 2.0, 2.0))
    //     ),
    // };
    // self.renderables.append(diorama) catch @panic("Out of memory");
    //
    // const body = RenderObject {
    //     .mesh = self.meshes.getPtr("body") orelse @panic("Failed to get body mesh"),
    //     .material = self.materials.getPtr("default_mesh") orelse @panic("Failed to get default mesh material"),
    //     .transform = Mat4.mul(
    //         Mat4.mul(
    //             m3d.translation(m3d.vec3(-3.0, -0.5, 0)),
    //             m3d.rotation(m3d.vec3(0, 1, 0), std.math.degreesToRadians(f32, 45)),
    //         ),
    //         m3d.scale(m3d.vec3(2.0, 2.0, 2.0))
    //     ),
    // };
    // self.renderables.append(body) catch @panic("Out of memory");

    var material = self.materials.getPtr("textured_mesh") orelse @panic("Failed to get default mesh material");

    // Allocate descriptor set for signle-texture to use on the material
    const descriptor_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &self.single_texture_set_layout,
    });

    check_vk(c.vkAllocateDescriptorSets(self.device, &descriptor_set_alloc_info, &material.texture_set)) catch @panic("Failed to allocate descriptor set");

    // Sampler
    const sampler_ci = std.mem.zeroInit(c.VkSamplerCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = c.VK_FILTER_NEAREST,
        .minFilter = c.VK_FILTER_NEAREST,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
    });

    var sampler: c.VkSampler = undefined;
    check_vk(c.vkCreateSampler(self.device, &sampler_ci, vk_alloc_cbs, &sampler)) catch @panic("Failed to create sampler");
    self.deletion_queue.append(VulkanDeleter.make(sampler, c.vkDestroySampler)) catch @panic("Out of memory");

    const lost_empire_tex = (self.textures.get("empire_diffuse") orelse @panic("Failed to get empire texture"));

    const descriptor_image_info = std.mem.zeroInit(c.VkDescriptorImageInfo, .{
        .sampler = sampler,
        .imageView = lost_empire_tex.image_view,
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    });

    const write_descriptor_set = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = material.texture_set,
        .dstBinding = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &descriptor_image_info,
    });

    c.vkUpdateDescriptorSets(self.device, 1, &write_descriptor_set, 0, null);

    const lost_empire = RenderObject{
        .name = "lost_empire",
        .mesh = self.meshes.getPtr("lost_empire") orelse @panic("Failed to get triangle mesh"),
        .transform = Mat4.translation(Vec3.make(5.0, -10.0, 0.0)),
        .material = material,
    };
    self.renderables.append(lost_empire) catch @panic("Out of memory");

    var x: i32 = -20;
    var i: i32 = 0;
    while (x <= 20) : (x += 1) {
        var y: i32 = -20;
        while (y <= 20) : (y += 1) {
            const translation = Mat4.translation(Vec3.make(@floatFromInt(x), 0.0, @floatFromInt(y)));
            const scale = Mat4.scale(Vec3.make(0.2, 0.2, 0.2));
            const transform = Mat4.mul(translation, scale);

            i += 1;
            const tri = RenderObject{
                .name = "triangle",
                .mesh = self.meshes.getPtr("triangle") orelse @panic("Failed to get triangle mesh"),
                .material = self.materials.getPtr("default_mesh") orelse @panic("Failed to get default mesh material"),
                .transform = transform,
            };

            self.renderables.append(tri) catch @panic("Out of memory");
        }
    }
}

fn init_imgui(self: *Self) void {
    const pool_sizes = [_]c.VkDescriptorPoolSize{
        .{
            .type = c.VK_DESCRIPTOR_TYPE_SAMPLER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,
            .descriptorCount = 1000,
        },
    };

    const pool_ci = std.mem.zeroInit(c.VkDescriptorPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        .maxSets = 1000,
        .poolSizeCount = @as(u32, @intCast(pool_sizes.len)),
        .pPoolSizes = &pool_sizes[0],
    });

    var imgui_pool: c.VkDescriptorPool = undefined;
    check_vk(c.vkCreateDescriptorPool(self.device, &pool_ci, vk_alloc_cbs, &imgui_pool)) catch @panic("Failed to create imgui descriptor pool");

    _ = edc.ImGui_CreateContext(null);
    _ = edc.cImGui_ImplSDL3_InitForVulkan(@ptrCast(self.window));

    var init_info = std.mem.zeroInit(edc.ImGui_ImplVulkan_InitInfo, .{
        .Instance = @as(edc.VkInstance, @ptrCast(self.instance)),
        .PhysicalDevice = @as(edc.VkPhysicalDevice, @ptrCast(self.physical_device)),
        .Device = @as(edc.VkDevice, @ptrCast(self.device)),
        .QueueFamily = self.graphics_queue_family,
        .Queue = @as(edc.VkQueue, @ptrCast(self.graphics_queue)),
        .DescriptorPool = @as(edc.VkDescriptorPool, @ptrCast(self.descriptor_pool)),
        .MinImageCount = FRAME_OVERLAP,
        .ImageCount = FRAME_OVERLAP,
        .MSAASamples = c.VK_SAMPLE_COUNT_1_BIT,
    });

    const io = edc.ImGui_GetIO();
    _ = edc.ImFontAtlas_AddFontFromFileTTF(io.*.Fonts, "assets/roboto.ttf", 14, null, null);

    _ = edc.cImGui_ImplVulkan_Init(&init_info, @ptrCast(self.render_pass));
    _ = edc.cImGui_ImplVulkan_CreateFontsTexture();

    self.play_icon_ds = self.create_imgui_texture("assets/icons/play.png");
    self.pause_icon_ds = self.create_imgui_texture("assets/icons/pause.png");
    self.stop_icon_ds = self.create_imgui_texture("assets/icons/stop.png");
    self.fast_forward_icon_ds = self.create_imgui_texture("assets/icons/fast-forward.png");

    self.deletion_queue.append(VulkanDeleter.make(imgui_pool, c.vkDestroyDescriptorPool)) catch @panic("Out of memory");

    edc.ImGui_GetIO().*.ConfigFlags |= edc.ImGuiConfigFlags_DockingEnable;
    edc.ImGui_GetIO().*.ConfigWindowsMoveFromTitleBarOnly = true;

    const ImVec2 = struct {
        fn f(x: f32, y: f32) edc.ImVec2 {
            return edc.ImVec2{ .x = x, .y = y };
        }
    }.f;
    const ImVec4 = struct {
        fn f(x: f32, y: f32, z: f32, w: f32) edc.ImVec4 {
            return edc.ImVec4{ .x = x, .y = y, .z = z, .w = w };
        }
    }.f;

    const style = edc.ImGui_GetStyle();
    style.*.Alpha = 1.0;
    style.*.DisabledAlpha = 0.6000000238418579;
    style.*.WindowPadding = ImVec2(8.0, 8.0);
    style.*.WindowRounding = 0.0;
    style.*.WindowBorderSize = 1.0;
    style.*.WindowMinSize = ImVec2(32.0, 32.0);
    style.*.WindowTitleAlign = ImVec2(0.0, 0.5);
    style.*.WindowMenuButtonPosition = edc.ImGuiDir_Left;
    style.*.ChildRounding = 0.0;
    style.*.ChildBorderSize = 1.0;
    style.*.PopupRounding = 0.0;
    style.*.PopupBorderSize = 1.0;
    style.*.FramePadding = ImVec2(4.0, 3.0);
    style.*.FrameRounding = 0.0;
    style.*.FrameBorderSize = 0.0;
    style.*.ItemSpacing = ImVec2(8.0, 4.0);
    style.*.ItemInnerSpacing = ImVec2(4.0, 4.0);
    style.*.CellPadding = ImVec2(4.0, 2.0);
    style.*.IndentSpacing = 21.0;
    style.*.ColumnsMinSpacing = 6.0;
    style.*.ScrollbarSize = 14.0;
    style.*.ScrollbarRounding = 0.0;
    style.*.GrabMinSize = 10.0;
    style.*.GrabRounding = 0.0;
    style.*.TabRounding = 0.0;
    style.*.TabBorderSize = 0.0;
    style.*.TabMinWidthForCloseButton = 0.0;
    style.*.ColorButtonPosition = edc.ImGuiDir_Right;
    style.*.ButtonTextAlign = ImVec2(0.5, 0.5);
    style.*.SelectableTextAlign = ImVec2(0.0, 0.0);

    style.*.Colors[edc.ImGuiCol_Text] = ImVec4(1.0, 1.0, 1.0, 1.0);
    style.*.Colors[edc.ImGuiCol_TextDisabled] = ImVec4(0.5921568870544434, 0.5921568870544434, 0.5921568870544434, 1.0);
    style.*.Colors[edc.ImGuiCol_WindowBg] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_ChildBg] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_PopupBg] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_Border] = ImVec4(0.3058823645114899, 0.3058823645114899, 0.3058823645114899, 1.0);
    style.*.Colors[edc.ImGuiCol_BorderShadow] = ImVec4(0.3058823645114899, 0.3058823645114899, 0.3058823645114899, 1.0);
    style.*.Colors[edc.ImGuiCol_FrameBg] = ImVec4(0.2000000029802322, 0.2000000029802322, 0.2156862765550613, 1.0);
    style.*.Colors[edc.ImGuiCol_FrameBgHovered] = ImVec4(0.1137254908680916, 0.5921568870544434, 0.9254902005195618, 1.0);
    style.*.Colors[edc.ImGuiCol_FrameBgActive] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_TitleBg] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_TitleBgActive] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_TitleBgCollapsed] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_MenuBarBg] = ImVec4(0.2000000029802322, 0.2000000029802322, 0.2156862765550613, 1.0);
    style.*.Colors[edc.ImGuiCol_ScrollbarBg] = ImVec4(0.2000000029802322, 0.2000000029802322, 0.2156862765550613, 1.0);
    style.*.Colors[edc.ImGuiCol_ScrollbarGrab] = ImVec4(0.321568638086319, 0.321568638086319, 0.3333333432674408, 1.0);
    style.*.Colors[edc.ImGuiCol_ScrollbarGrabHovered] = ImVec4(0.3529411852359772, 0.3529411852359772, 0.3725490272045135, 1.0);
    style.*.Colors[edc.ImGuiCol_ScrollbarGrabActive] = ImVec4(0.3529411852359772, 0.3529411852359772, 0.3725490272045135, 1.0);
    style.*.Colors[edc.ImGuiCol_CheckMark] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_SliderGrab] = ImVec4(0.1137254908680916, 0.5921568870544434, 0.9254902005195618, 1.0);
    style.*.Colors[edc.ImGuiCol_SliderGrabActive] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_Button] = ImVec4(0.2000000029802322, 0.2000000029802322, 0.2156862765550613, 1.0);
    style.*.Colors[edc.ImGuiCol_ButtonHovered] = ImVec4(0.1137254908680916, 0.5921568870544434, 0.9254902005195618, 1.0);
    style.*.Colors[edc.ImGuiCol_ButtonActive] = ImVec4(0.1137254908680916, 0.5921568870544434, 0.9254902005195618, 1.0);
    style.*.Colors[edc.ImGuiCol_Header] = ImVec4(0.2000000029802322, 0.2000000029802322, 0.2156862765550613, 1.0);
    style.*.Colors[edc.ImGuiCol_HeaderHovered] = ImVec4(0.1137254908680916, 0.5921568870544434, 0.9254902005195618, 1.0);
    style.*.Colors[edc.ImGuiCol_HeaderActive] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_Separator] = ImVec4(0.3058823645114899, 0.3058823645114899, 0.3058823645114899, 1.0);
    style.*.Colors[edc.ImGuiCol_SeparatorHovered] = ImVec4(0.3058823645114899, 0.3058823645114899, 0.3058823645114899, 1.0);
    style.*.Colors[edc.ImGuiCol_SeparatorActive] = ImVec4(0.3058823645114899, 0.3058823645114899, 0.3058823645114899, 1.0);
    style.*.Colors[edc.ImGuiCol_ResizeGrip] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_ResizeGripHovered] = ImVec4(0.2000000029802322, 0.2000000029802322, 0.2156862765550613, 1.0);
    style.*.Colors[edc.ImGuiCol_ResizeGripActive] = ImVec4(0.321568638086319, 0.321568638086319, 0.3333333432674408, 1.0);
    style.*.Colors[edc.ImGuiCol_Tab] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_TabHovered] = ImVec4(0.1137254908680916, 0.5921568870544434, 0.9254902005195618, 1.0);
    style.*.Colors[edc.ImGuiCol_TabActive] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_TabUnfocused] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_TabUnfocusedActive] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_PlotLines] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_PlotLinesHovered] = ImVec4(0.1137254908680916, 0.5921568870544434, 0.9254902005195618, 1.0);
    style.*.Colors[edc.ImGuiCol_PlotHistogram] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_PlotHistogramHovered] = ImVec4(0.1137254908680916, 0.5921568870544434, 0.9254902005195618, 1.0);
    style.*.Colors[edc.ImGuiCol_TableHeaderBg] = ImVec4(0.1882352977991104, 0.1882352977991104, 0.2000000029802322, 1.0);
    style.*.Colors[edc.ImGuiCol_TableBorderStrong] = ImVec4(0.3098039329051971, 0.3098039329051971, 0.3490196168422699, 1.0);
    style.*.Colors[edc.ImGuiCol_TableBorderLight] = ImVec4(0.2274509817361832, 0.2274509817361832, 0.2470588237047195, 1.0);
    style.*.Colors[edc.ImGuiCol_TableRowBg] = ImVec4(0.0, 0.0, 0.0, 0.0);
    style.*.Colors[edc.ImGuiCol_TableRowBgAlt] = ImVec4(1.0, 1.0, 1.0, 0.05999999865889549);
    style.*.Colors[edc.ImGuiCol_TextSelectedBg] = ImVec4(0.0, 0.4666666686534882, 0.7843137383460999, 1.0);
    style.*.Colors[edc.ImGuiCol_DragDropTarget] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_NavHighlight] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
    style.*.Colors[edc.ImGuiCol_NavWindowingHighlight] = ImVec4(1.0, 1.0, 1.0, 0.699999988079071);
    style.*.Colors[edc.ImGuiCol_NavWindowingDimBg] = ImVec4(0.800000011920929, 0.800000011920929, 0.800000011920929, 0.2000000029802322);
    style.*.Colors[edc.ImGuiCol_ModalWindowDimBg] = ImVec4(0.1450980454683304, 0.1450980454683304, 0.1490196138620377, 1.0);
}

pub fn cleanup(self: *Self) void {
    check_vk(c.vkDeviceWaitIdle(self.device)) catch @panic("Failed to wait for device idle");

    // TODO: this is a horrible way to keep track of the meshes to free. Quick and dirty hack.
    var mesh_it = self.meshes.iterator();
    while (mesh_it.next()) |entry| {
        self.allocator.free(entry.value_ptr.vertices);
    }

    self.textures.deinit();
    self.meshes.deinit();
    self.materials.deinit();
    self.renderables.deinit();

    edc.cImGui_ImplVulkan_Shutdown();

    for (self.buffer_deletion_queue.items) |*entry| {
        entry.delete(self);
    }
    self.buffer_deletion_queue.deinit();

    for (self.image_deletion_queue.items) |*entry| {
        entry.delete(self);
    }
    self.image_deletion_queue.deinit();

    for (self.deletion_queue.items) |*entry| {
        entry.delete(self);
    }
    self.deletion_queue.deinit();

    self.allocator.free(self.framebuffers);
    self.allocator.free(self.swapchain_image_views);
    self.allocator.free(self.swapchain_images);

    c.vmaDestroyAllocator(self.vma_allocator);

    c.vkDestroyDevice(self.device, vk_alloc_cbs);
    c.vkDestroySurfaceKHR(self.instance, self.surface, vk_alloc_cbs);

    if (self.debug_messenger != VK_NULL_HANDLE) {
        const destroy_fn = vki.get_destroy_debug_utils_messenger_fn(self.instance).?;
        destroy_fn(self.instance, self.debug_messenger, vk_alloc_cbs);
    }

    c.vkDestroyInstance(self.instance, vk_alloc_cbs);
    c.SDL_DestroyWindow(self.window);
}

fn load_textures(self: *Self) void {
    const lost_empire_image = texs.load_image_from_file(Self, self, "assets/lost_empire-RGBA.png") catch @panic("Failed to load image");
    self.image_deletion_queue.append(VmaImageDeleter{ .image = lost_empire_image }) catch @panic("Out of memory");
    const image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .image = lost_empire_image.image,
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

    var lost_empire = Texture{
        .image = lost_empire_image,
        .image_view = VK_NULL_HANDLE,
    };

    check_vk(c.vkCreateImageView(self.device, &image_view_ci, vk_alloc_cbs, &lost_empire.image_view)) catch @panic("Failed to create image view");
    self.deletion_queue.append(VulkanDeleter.make(lost_empire.image_view, c.vkDestroyImageView)) catch @panic("Out of memory");

    self.textures.put("empire_diffuse", lost_empire) catch @panic("Out of memory");
}

fn load_meshes(self: *Self) void {
    const vertices = [_]mesh_mod.Vertex{ .{
        .position = Vec3.make(1.0, 1.0, 0.0),
        .normal = undefined,
        .color = Vec3.make(0.0, 1.0, 0.0),
        .uv = Vec2.make(1.0, 1.0),
    }, .{
        .position = Vec3.make(-1.0, 1.0, 0.0),
        .normal = undefined,
        .color = Vec3.make(0.0, 1.0, 0.0),
        .uv = Vec2.make(0.0, 1.0),
    }, .{
        .position = Vec3.make(0.0, -1.0, 0.0),
        .normal = undefined,
        .color = Vec3.make(0.0, 1.0, 0.0),
        .uv = Vec2.make(0.5, 0.0),
    } };

    var triangle_mesh = Mesh{
        .vertices = self.allocator.dupe(mesh_mod.Vertex, vertices[0..]) catch @panic("Out of memory"),
    };
    self.upload_mesh(&triangle_mesh);
    self.meshes.put("triangle", triangle_mesh) catch @panic("Out of memory");

    var monkey_mesh = mesh_mod.load_from_obj(self.allocator, "assets/suzanne.obj");
    self.upload_mesh(&monkey_mesh);
    self.meshes.put("monkey", monkey_mesh) catch @panic("Out of memory");

    //var cube_diorama = mesh_mod.load_from_obj(self.allocator, "assets/cube_diorama.obj");
    //self.upload_mesh(&cube_diorama);
    //self.meshes.put("diorama", cube_diorama) catch @panic("Out of memory");

    //var body = mesh_mod.load_from_obj(self.allocator, "assets/body_male_realistic.obj");
    //self.upload_mesh(&body);
    //self.meshes.put("body", body) catch @panic("Out of memory");

    var lost_empire = mesh_mod.load_from_obj(self.allocator, "assets/lost_empire.obj");
    self.upload_mesh(&lost_empire);
    self.meshes.put("lost_empire", lost_empire) catch @panic("Out of memory");
}

fn upload_mesh(self: *Self, mesh: *Mesh) void {
    // Create a cpu buffer for staging
    const staging_buffer_ci = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = mesh.vertices.len * @sizeOf(mesh_mod.Vertex),
        .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
    });

    const staging_buffer_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_CPU_ONLY,
    });

    var staging_buffer: AllocatedBuffer = undefined;
    check_vk(c.vmaCreateBuffer(self.vma_allocator, &staging_buffer_ci, &staging_buffer_ai, &staging_buffer.buffer, &staging_buffer.allocation, null)) catch @panic("Failed to create vertex buffer");

    log.info("Created staging buffer {}", .{@intFromPtr(mesh.vertex_buffer.buffer)});

    var data: ?*align(@alignOf(mesh_mod.Vertex)) anyopaque = undefined;
    check_vk(c.vmaMapMemory(self.vma_allocator, staging_buffer.allocation, &data)) catch @panic("Failed to map vertex buffer");
    @memcpy(@as([*]mesh_mod.Vertex, @ptrCast(data)), mesh.vertices);
    c.vmaUnmapMemory(self.vma_allocator, staging_buffer.allocation);

    log.info("Copied mesh data into staging buffer", .{});

    const gpu_buffer_ci = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = mesh.vertices.len * @sizeOf(mesh_mod.Vertex),
        .usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
    });

    const gpu_buffer_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
    });

    check_vk(c.vmaCreateBuffer(self.vma_allocator, &gpu_buffer_ci, &gpu_buffer_ai, &mesh.vertex_buffer.buffer, &mesh.vertex_buffer.allocation, null)) catch @panic("Failed to create vertex buffer");

    log.info("Created GPU buffer for mesh", .{});

    self.buffer_deletion_queue.append(VmaBufferDeleter{ .buffer = mesh.vertex_buffer }) catch @panic("Out of memory");

    // Now we can copy immediate the content of the staging buffer to the gpu
    // only memory.
    self.immediate_submit(struct {
        mesh_buffer: c.VkBuffer,
        staging_buffer: c.VkBuffer,
        size: usize,

        fn submit(ctx: @This(), cmd: c.VkCommandBuffer) void {
            const copy_region = std.mem.zeroInit(c.VkBufferCopy, .{
                .size = ctx.size,
            });
            c.vkCmdCopyBuffer(cmd, ctx.staging_buffer, ctx.mesh_buffer, 1, &copy_region);
        }
    }{
        .mesh_buffer = mesh.vertex_buffer.buffer,
        .staging_buffer = staging_buffer.buffer,
        .size = mesh.vertices.len * @sizeOf(mesh_mod.Vertex),
    });

    // We can free the staging buffer at this point.
    c.vmaDestroyBuffer(self.vma_allocator, staging_buffer.buffer, staging_buffer.allocation);
}

pub fn run(self: *Self) void {
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var delta: f32 = 0.016;

    var quit = false;
    var event: c.SDL_Event = undefined;
    while (!quit) {
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_EVENT_MOUSE_MOTION) {
                self.mouse.x = event.motion.x;
                self.mouse.y = event.motion.y;
            }
            const mouse = self.mouse;

            _ = edc.cImGui_ImplSDL3_ProcessEvent(@ptrCast(&event));
            if (event.type == c.SDL_EVENT_QUIT) {
                quit = true;
            } else if (self.is_game_window_active and self.isInGameView(mouse)) {
                self.processGameEvent(event);
            } else {
                self.camera_input.x = 0;
                self.camera_input.y = 0;
                self.camera_input.z = 0;
            }
        }

        if (self.camera_input.squared_norm() > (0.1 * 0.1)) {
            const camera_delta = self.camera_input.normalized().mul(delta * 5.0);
            self.camera_pos = Vec3.add(self.camera_pos, camera_delta);
        }

        {
            edc.cImGui_ImplVulkan_NewFrame();
            edc.cImGui_ImplSDL3_NewFrame();
            edc.ImGui_NewFrame();
            if (self.imgui_demo_open) {
                edc.ImGui_ShowDemoWindow(&self.imgui_demo_open);
            }

            if (edc.ImGui_BeginMainMenuBar()) {
                if (edc.ImGui_BeginMenu("File")) {
                    if (edc.ImGui_MenuItem("New")) {}
                    if (edc.ImGui_MenuItem("Open")) {}
                    if (edc.ImGui_MenuItem("Save")) {}
                    if (edc.ImGui_MenuItem("Quit")) {}
                    edc.ImGui_EndMenu();
                }
                if (edc.ImGui_BeginMenu("Edit")) {
                    if (edc.ImGui_MenuItemEx("Undo", "CTRL+Z", false, true)) {}
                    if (edc.ImGui_MenuItemEx("Redo", "CTRL+Y", false, false)) {} // Disabled item
                    edc.ImGui_Separator();
                    if (edc.ImGui_MenuItemEx("Cut", "CTRL+X", false, true)) {}
                    if (edc.ImGui_MenuItemEx("Copy", "CTRL+C", false, true)) {}
                    if (edc.ImGui_MenuItemEx("Paste", "CTRL+V", false, true)) {}
                    edc.ImGui_EndMenu();
                }
                if (edc.ImGui_BeginMenu("Help")) {
                    _ = edc.ImGui_MenuItemBoolPtr("ImGui Demo Window", null, &self.imgui_demo_open, true);
                    edc.ImGui_Separator();
                    if (edc.ImGui_MenuItem("About")) {}
                    edc.ImGui_EndMenu();
                }
                edc.ImGui_SetCursorPosX((edc.ImGui_GetCursorPosX() - (13 * 3)) + (window_extent.width / 2) - edc.ImGui_GetCursorPosX());
                if (edc.ImGui_ImageButton("Play", if (self.play) self.stop_icon_ds else self.play_icon_ds, edc.ImVec2{ .x = 13, .y = 13 })) {
                    self.play = !self.play;
                }
                _ = edc.ImGui_ImageButton("Pause", self.pause_icon_ds, edc.ImVec2{ .x = 13, .y = 13 });
                _ = edc.ImGui_ImageButton("Next", self.fast_forward_icon_ds, edc.ImVec2{ .x = 13, .y = 13 });
                edc.ImGui_EndMainMenuBar();
            }

            // We are using the ImGuiWindowFlags_NoDocking flag to make the parent window not dockable into,
            // because it would be confusing to have two docking targets within each others.
            var window_flags = edc.ImGuiWindowFlags_MenuBar | edc.ImGuiWindowFlags_NoDocking;

            const viewport = edc.ImGui_GetMainViewport();
            edc.ImGui_SetNextWindowPos(viewport.*.Pos, 0);
            edc.ImGui_SetNextWindowSize(viewport.*.Size, 0);
            edc.ImGui_SetNextWindowViewport(viewport.*.ID);
            edc.ImGui_PushStyleVar(edc.ImGuiStyleVar_WindowRounding, 0);
            edc.ImGui_PushStyleVar(edc.ImGuiStyleVar_WindowBorderSize, 0);
            window_flags |= edc.ImGuiWindowFlags_NoTitleBar | edc.ImGuiWindowFlags_NoCollapse | edc.ImGuiWindowFlags_NoResize | edc.ImGuiWindowFlags_NoMove;
            window_flags |= edc.ImGuiWindowFlags_NoBringToFrontOnFocus | edc.ImGuiWindowFlags_NoNavFocus;

            // When using ImGuiDockNodeFlags_PassthruCentralNode, DockSpace() will render our background and handle the pass-thru hole, so we ask Begin() to not render a background.
            if ((dockspace_flags & edc.ImGuiDockNodeFlags_PassthruCentralNode) > 0) {
                window_flags |= edc.ImGuiWindowFlags_NoBackground;
            }

            // Important: note that we proceed even if Begin() returns false (aka window is collapsed).
            // This is because we want to keep our DockSpace() active. If a DockSpace() is inactive,
            // all active windows docked into it will lose their parent and become undocked.
            // We cannot preserve the docking relationship between an active window and an inactive docking, otherwise
            // any change of dockspace/settings would lead to windows being stuck in limbo and never being visible.
            edc.ImGui_PushStyleVarImVec2(edc.ImGuiStyleVar_WindowPadding, edc.ImVec2{ .x = 0, .y = 0 });
            _ = edc.ImGui_Begin("DockSpace", null, window_flags);
            edc.ImGui_PopStyleVar();
            edc.ImGui_PopStyleVarEx(2);

            // DockSpace
            const io = edc.ImGui_GetIO();
            if ((io.*.ConfigFlags & edc.ImGuiConfigFlags_DockingEnable) > 0) {
                var dockspace_id = edc.ImGui_GetID("MyDockSpace");
                _ = edc.ImGui_DockSpaceEx(dockspace_id, edc.ImVec2{ .x = 0, .y = 0 }, dockspace_flags, null);

                if (self.first_time) {
                    self.first_time = false;

                    edc.ImGui_DockBuilderRemoveNode(dockspace_id); // clear any previous layout
                    _ = edc.ImGui_DockBuilderAddNodeEx(dockspace_id, dockspace_flags | edc.ImGuiDockNodeFlags_DockSpace);
                    edc.ImGui_DockBuilderSetNodeSize(dockspace_id, viewport.*.Size);

                    // split the dockspace into 2 nodes -- DockBuilderSplitNode takes in the following args in the following order
                    //   window ID to split, direction, fraction (between 0 and 1), the final two setting let's us choose which id we want (which ever one we DON'T set as NULL, will be returned by the function)
                    //                                                              out_id_at_dir is the id of the node in the direction we specified earlier, out_id_at_opposite_dir is in the opposite direction
                    const dock_id_left = edc.ImGui_DockBuilderSplitNode(dockspace_id, edc.ImGuiDir_Left, 0.2, null, &dockspace_id);
                    const dock_id_down = edc.ImGui_DockBuilderSplitNode(dockspace_id, edc.ImGuiDir_Down, 0.25, null, &dockspace_id);

                    // we now dock our windows into the docking node we made above
                    edc.ImGui_DockBuilderDockWindow("Assets", dock_id_down);
                    edc.ImGui_DockBuilderDockWindow("Hierarchy", dock_id_left);
                    edc.ImGui_DockBuilderFinish(dockspace_id);
                }
            }

            edc.ImGui_End();

            _ = edc.ImGui_Begin("Hierarchy", null, 0);
            for (self.renderables.items) |r| {
                var node_flags = edc.ImGuiTreeNodeFlags_OpenOnArrow;
                if (std.mem.eql(u8, std.mem.span(r.name), "triangle")) {
                    node_flags = edc.ImGuiTreeNodeFlags_Leaf;
                }
                if (edc.ImGui_TreeNodeEx(r.name, node_flags)) {
                    edc.ImGui_TreePop();
                }
            }
            edc.ImGui_End();

            _ = edc.ImGui_Begin("Assets", null, 0);
            edc.ImGui_Text("TODO");
            edc.ImGui_End();

            _ = edc.ImGui_Begin("Properties", null, 0);
            edc.ImGui_Text("TODO");
            edc.ImGui_End();

            _ = edc.ImGui_Begin("Game", null, 0);
            const old_is_game_window_focused = self.is_game_window_focused;
            self.is_game_window_focused = edc.ImGui_IsWindowFocused(edc.ImGuiFocusedFlags_None);
            if (self.is_game_window_focused) {
                if (!old_is_game_window_focused) {
                    self.is_game_window_active = true;
                } else if (self.isInGameView(edc.ImGui_GetMousePos()) and edc.ImGui_IsMouseClicked(edc.ImGuiMouseButton_Left)) {
                    self.is_game_window_active = true;
                }
            } else {
                self.is_game_window_active = false;
            }
            const game_image = edc.ImGui_GetWindowDrawList();
            self.game_view_size = edc.ImGui_GetWindowSize();
            edc.ImDrawList_AddCallback(game_image, extern struct {
                fn f(dl: [*c]const edc.ImDrawList, dc: [*c]const edc.ImDrawCmd) callconv(.C) void {
                    _ = dl;
                    const me: *Self = @alignCast(@ptrCast(dc.*.UserCallbackData));
                    const cmd = me.get_current_frame().main_command_buffer;
                    const cr = dc.*.ClipRect;
                    me.game_window_rect = cr;
                    const w = cr.z - cr.x;
                    const h = cr.w - cr.y;
                    c.vkCmdSetScissor(cmd, 0, 1, &[_]c.VkRect2D{.{
                        .offset = .{ .x = @intFromFloat(cr.x), .y = @intFromFloat(cr.y) },
                        .extent = .{ .width = @intFromFloat(w), .height = @intFromFloat(h) },
                    }});

                    const vx = if (cr.x > 0) cr.x else cr.z - me.game_view_size.x;
                    c.vkCmdSetViewport(cmd, 0, 1, &[_]c.VkViewport{.{
                        .x = vx,
                        .y = cr.y,
                        .width = me.game_view_size.x,
                        .height = me.game_view_size.y,
                        .minDepth = 0.0,
                        .maxDepth = 1.0,
                    }});

                    const aspect = me.game_view_size.x / me.game_view_size.y;
                    _ = aspect;
                    // me.draw_objects(cmd, me.renderables.items, aspect);

                    c.vkCmdSetScissor(cmd, 0, 1, &[_]c.VkRect2D{.{
                        .offset = .{ .x = 0, .y = 0 },
                        .extent = window_extent,
                    }});
                }
            }.f, self);
            edc.ImDrawList_AddCallback(game_image, edc.ImDrawCallback_ResetRenderState, null);
            edc.ImGui_End();

            edc.ImGui_Render();
        }

        self.draw();

        delta = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        const TitleDelay = struct {
            var accumulator: f32 = 0.0;
        };

        TitleDelay.accumulator += delta;
        if (TitleDelay.accumulator > 0.1) {
            TitleDelay.accumulator = 0.0;
            const fps = 1.0 / delta;
            const new_title = std.fmt.allocPrintZ(self.allocator, "Yume Editor - FPS: {d:6.3}, ms: {d:6.3}", .{ fps, delta * 1000.0 }) catch @panic("Out of memory");
            defer self.allocator.free(new_title);
            _ = c.SDL_SetWindowTitle(self.window, new_title.ptr);
        }
    }
}

fn processGameEvent(self: *Self, event: c.SDL_Event) void {
    if (event.type == c.SDL_EVENT_KEY_DOWN) {
        switch (event.key.keysym.scancode) {
            c.SDL_SCANCODE_SPACE => {
                self.selected_shader = if (self.selected_shader == 1) 0 else 1;
            },
            c.SDL_SCANCODE_M => {
                self.selected_mesh = if (self.selected_mesh == 1) 0 else 1;
            },

            // WASD for camera
            c.SDL_SCANCODE_W => {
                self.camera_input.z = 1.0;
            },
            c.SDL_SCANCODE_S => {
                self.camera_input.z = -1.0;
            },
            c.SDL_SCANCODE_A => {
                self.camera_input.x = 1.0;
            },
            c.SDL_SCANCODE_D => {
                self.camera_input.x = -1.0;
            },
            c.SDL_SCANCODE_E => {
                self.camera_input.y = 1.0;
            },
            c.SDL_SCANCODE_Q => {
                self.camera_input.y = -1.0;
            },

            else => {},
        }
    } else if (event.type == c.SDL_EVENT_KEY_UP) {
        switch (event.key.keysym.scancode) {
            c.SDL_SCANCODE_ESCAPE => {
                self.is_game_window_active = false;
            },
            c.SDL_SCANCODE_W => {
                self.camera_input.z = 0.0;
            },
            c.SDL_SCANCODE_S => {
                self.camera_input.z = 0.0;
            },
            c.SDL_SCANCODE_A => {
                self.camera_input.x = 0.0;
            },
            c.SDL_SCANCODE_D => {
                self.camera_input.x = 0.0;
            },
            c.SDL_SCANCODE_E => {
                self.camera_input.y = 0.0;
            },
            c.SDL_SCANCODE_Q => {
                self.camera_input.y = 0.0;
            },

            else => {},
        }
    }
}

fn get_current_frame(self: *Self) FrameData {
    return self.frames[@intCast(@mod(self.frame_number, FRAME_OVERLAP))];
}

fn draw(self: *Self) void {
    // Wait until the GPU has finished rendering the last frame
    const timeout: u64 = 1_000_000_000; // 1 second in nanonesconds
    const frame = self.get_current_frame();

    check_vk(c.vkWaitForFences(self.device, 1, &frame.render_fence, c.VK_TRUE, timeout)) catch @panic("Failed to wait for render fence");
    check_vk(c.vkResetFences(self.device, 1, &frame.render_fence)) catch @panic("Failed to reset render fence");

    var swapchain_image_index: u32 = undefined;
    check_vk(c.vkAcquireNextImageKHR(self.device, self.swapchain, timeout, frame.present_semaphore, VK_NULL_HANDLE, &swapchain_image_index)) catch @panic("Failed to acquire swapchain image");

    current_image_idx = swapchain_image_index;
    var cmd = frame.main_command_buffer;

    check_vk(c.vkResetCommandBuffer(cmd, 0)) catch @panic("Failed to reset command buffer");

    const cmd_begin_info = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });

    check_vk(c.vkBeginCommandBuffer(cmd, &cmd_begin_info)) catch @panic("Failed to begin command buffer");

    // Make a claer color that changes with each frame (120*pi frame period)
    // 0.11 and 0.12 fix for change in fabs
    const color = math3d.abs(std.math.sin(@as(f32, @floatFromInt(self.frame_number)) / 120.0));

    const color_clear: c.VkClearValue = .{
        .color = .{ .float32 = [_]f32{ color, 0.0, color, 1.0 } },
    };

    const depth_clear = c.VkClearValue{
        .depthStencil = .{
            .depth = 1.0,
            .stencil = 0,
        },
    };

    const clear_values = [_]c.VkClearValue{
        color_clear,
        depth_clear,
    };

    const render_pass_begin_info = std.mem.zeroInit(c.VkRenderPassBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = self.render_pass,
        .framebuffer = self.framebuffers[swapchain_image_index],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        },
        .clearValueCount = @as(u32, @intCast(clear_values.len)),
        .pClearValues = &clear_values[0],
    });
    c.vkCmdBeginRenderPass(cmd, &render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);

    c.vkCmdSetScissor(cmd, 0, 1, &[_]c.VkRect2D{.{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain_extent,
    }});

    // UI
    edc.cImGui_ImplVulkan_RenderDrawData(edc.ImGui_GetDrawData(), @ptrCast(cmd));

    c.vkCmdEndRenderPass(cmd);
    check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const wait_stage = @as(u32, @intCast(c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT));
    const submit_info = std.mem.zeroInit(c.VkSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &frame.present_semaphore,
        .pWaitDstStageMask = &wait_stage,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &frame.render_semaphore,
    });
    check_vk(c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, frame.render_fence)) catch @panic("Failed to submit to graphics queue");

    const present_info = std.mem.zeroInit(c.VkPresentInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &frame.render_semaphore,
        .swapchainCount = 1,
        .pSwapchains = &self.swapchain,
        .pImageIndices = &swapchain_image_index,
    });
    check_vk(c.vkQueuePresentKHR(self.present_queue, &present_info)) catch @panic("Failed to present swapchain image");

    self.frame_number +%= 1;
}

fn create_material(self: *Self, pipeline: c.VkPipeline, pipeline_layout: c.VkPipelineLayout, name: []const u8) *Material {
    self.materials.put(name, Material{
        .pipeline = pipeline,
        .pipeline_layout = pipeline_layout,
    }) catch @panic("Out of memory");
    return self.materials.getPtr(name) orelse unreachable;
}

fn get_material(self: *Self, name: []const u8) ?*Material {
    return self.material.getPtr(name);
}

fn get_mesh(self: *Self, name: []const u8) ?*Mesh {
    return self.meshes.getPtr(name);
}

pub fn create_buffer(self: *Self, alloc_size: usize, usage: c.VkBufferUsageFlags, memory_usage: c.VmaMemoryUsage) AllocatedBuffer {
    const buffer_ci = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = alloc_size,
        .usage = usage,
    });

    const vma_alloc_info = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = memory_usage,
    });

    var buffer: AllocatedBuffer = undefined;
    check_vk(c.vmaCreateBuffer(self.vma_allocator, &buffer_ci, &vma_alloc_info, &buffer.buffer, &buffer.allocation, null)) catch @panic("Failed to create buffer");

    return buffer;
}

fn pad_uniform_buffer_size(self: *Self, original_size: usize) usize {
    const min_ubo_alignment = @as(usize, @intCast(self.physical_device_properties.limits.minUniformBufferOffsetAlignment));
    const aligned_size = (original_size + min_ubo_alignment - 1) & ~(min_ubo_alignment - 1);
    return aligned_size;
}

pub fn immediate_submit(self: *Self, submit_ctx: anytype) void {
    // Check the context is good
    comptime {
        var Context = @TypeOf(submit_ctx);
        var is_ptr = false;
        switch (@typeInfo(Context)) {
            .Struct, .Union, .Enum => {},
            .Pointer => |ptr| {
                if (ptr.size != .One) {
                    @compileError("Context must be a type with a submit function. " ++ @typeName(Context) ++ "is a multi element pointer");
                }
                Context = ptr.child;
                is_ptr = true;
                switch (Context) {
                    .Struct, .Union, .Enum, .Opaque => {},
                    else => @compileError("Context must be a type with a submit function. " ++ @typeName(Context) ++ "is a pointer to a non struct/union/enum/opaque type"),
                }
            },
            else => @compileError("Context must be a type with a submit method. Cannot use: " ++ @typeName(Context)),
        }

        if (!@hasDecl(Context, "submit")) {
            @compileError("Context should have a submit method");
        }

        const submit_fn_info = @typeInfo(@TypeOf(Context.submit));
        if (submit_fn_info != .Fn) {
            @compileError("Context submit method should be a function");
        }

        if (submit_fn_info.Fn.params.len != 2) {
            @compileError("Context submit method should have two parameters");
        }

        if (submit_fn_info.Fn.params[0].type != Context) {
            @compileError("Context submit method first parameter should be of type: " ++ @typeName(Context));
        }

        if (submit_fn_info.Fn.params[1].type != c.VkCommandBuffer) {
            @compileError("Context submit method second parameter should be of type: " ++ @typeName(c.VkCommandBuffer));
        }
    }

    const cmd = self.upload_context.command_buffer;

    const commmand_begin_ci = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    check_vk(c.vkBeginCommandBuffer(cmd, &commmand_begin_ci)) catch @panic("Failed to begin command buffer");

    submit_ctx.submit(cmd);

    check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const submit_info = std.mem.zeroInit(c.VkSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
    });

    check_vk(c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.upload_context.upload_fence)) catch @panic("Failed to submit to graphics queue");

    check_vk(c.vkWaitForFences(self.device, 1, &self.upload_context.upload_fence, c.VK_TRUE, 1_000_000_000)) catch @panic("Failed to wait for upload fence");
    check_vk(c.vkResetFences(self.device, 1, &self.upload_context.upload_fence)) catch @panic("Failed to reset upload fence");

    check_vk(c.vkResetCommandPool(self.device, self.upload_context.command_pool, 0)) catch @panic("Failed to reset command pool");
}

fn create_imgui_texture(self: *Self, filepath: []const u8) c.VkDescriptorSet {
    const img = texs.load_image_from_file(Self, self, filepath) catch @panic("Failed to load image");
    self.image_deletion_queue.append(VmaImageDeleter{ .image = img }) catch @panic("Out of memory");

    // Create the Image View
    var image_view: c.VkImageView = undefined;
    {
        const info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = img.image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = c.VK_FORMAT_R8G8B8A8_UNORM,
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .levelCount = 1,
                .layerCount = 1,
            },
        };
        check_vk(c.vkCreateImageView(self.device, &info, vk_alloc_cbs, &image_view)) catch @panic("Failed to create image view");
    }
    self.textures.put(filepath, Texture{ .image = img, .image_view = image_view }) catch @panic("OOM");
    self.deletion_queue.append(VulkanDeleter.make(image_view, c.vkDestroyImageView)) catch @panic("OOM");
    // Create Sampler
    var sampler: c.VkSampler = undefined;
    {
        const sampler_info = c.VkSamplerCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = c.VK_FILTER_LINEAR,
            .minFilter = c.VK_FILTER_LINEAR,
            .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
            .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT, // outside image bounds just use border color
            .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .minLod = -1000,
            .maxLod = 1000,
            .maxAnisotropy = 1.0,
        };
        check_vk(c.vkCreateSampler(self.device, &sampler_info, vk_alloc_cbs, &sampler)) catch @panic("Failed to create sampler");
    }
    self.deletion_queue.append(VulkanDeleter.make(sampler, c.vkDestroySampler)) catch @panic("OOM");
    return @ptrCast(edc.cImGui_ImplVulkan_AddTexture(@ptrCast(sampler), @ptrCast(image_view), c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL));
}

fn isInGameView(self: *Self, pos: edc.ImVec2) bool {
    return (pos.x > self.game_window_rect.x and pos.x < self.game_window_rect.z) and
        (pos.y > self.game_window_rect.y and pos.y < self.game_window_rect.w);
}

// Error checking for vulkan and SDL
//

fn check_sdl(res: c_int) void {
    if (res != 0) {
        log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}

fn check_sdl_bool(res: c.SDL_bool) void {
    if (res != c.SDL_TRUE) {
        log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}

var dockspace_flags: edc.ImGuiDockNodeFlags = 0;
var current_image_idx: u32 = 0;
