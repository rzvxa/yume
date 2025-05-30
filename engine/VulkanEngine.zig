const c = @import("clibs");

const std = @import("std");

const utils = @import("utils.zig");
const Uuid = @import("uuid.zig").Uuid;

const vki = @import("vulkan_init.zig");
const check_vk = vki.check_vk;

const assets = @import("assets.zig");

const math3d = @import("math3d.zig");
const Vec2 = math3d.Vec2;
const Vec3 = math3d.Vec3;
const Vec4 = math3d.Vec4;
const Mat4 = math3d.Mat4;

const components = @import("ecs.zig").components;
const Camera = components.Camera;
const Mesh = components.Mesh;
const Vertex = components.mesh.Vertex;
const BoundingBox = components.mesh.BoundingBox;
const Material = components.Material;

const Shader = @import("shading.zig").Shader;

const log = std.log.scoped(.vulkan_engine);

const Self = @This();

const MAX_OBJECTS = 10000;
pub const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;

pub const Error = vki.VulkanError;

pub const RenderCommand = c.VkCommandBuffer;
pub const ShaderModule = c.VkShaderModule;
pub const Pipeline = c.VkPipeline;
pub const PipelineLayout = c.VkPipelineLayout;
pub const DescriptorSet = c.VkDescriptorSet;

pub const Image = c.VkImage;
pub const ImageView = c.VkImageView;
pub const Sampler = c.VkSampler;

pub const GPUAllocation = c.VmaAllocation;

pub const AllocatedBuffer = extern struct {
    buffer: c.VkBuffer,
    allocation: GPUAllocation,
};

pub const AllocatedImage = extern struct {
    handle: assets.ImageHandle,
    image: Image,
    allocation: GPUAllocation,
};

const FrameData = extern struct {
    present_semaphore: c.VkSemaphore = null,
    render_semaphore: c.VkSemaphore = null,
    render_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    main_command_buffer: c.VkCommandBuffer = null,

    object_buffer: AllocatedBuffer = .{ .buffer = null, .allocation = null },
    object_descriptor_set: c.VkDescriptorSet = null,
};

pub const GPUCameraData = extern struct {
    view_proj: Mat4,
    pos: Vec3,

    fn fromCamera(cam: *const Camera, pos: Vec3) GPUCameraData {
        return GPUCameraData{
            .view_proj = cam.view_projection,
            .pos = pos,
        };
    }
};

pub const GPUSceneData = extern struct {
    pub const GPULightData = extern struct {
        pos: Vec3,
        range: f32,
        color: Vec3,
        intensity: f32,
    };
    point_lights: [4]GPULightData,
    directional_light: GPULightData,
    ambient_color: Vec4,
    exposure: f32,
    gamma: f32,
};

const GPUObjectData = struct {
    model_matrix: Mat4,
};

const UploadContext = struct {
    upload_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    command_buffer: c.VkCommandBuffer = null,
};

pub const FRAME_OVERLAP = 2;

// Data
//
frame_number: i32 = 0,
object_buffer_offset: usize = 0,

window: *c.SDL_Window = undefined,

// Keep this around for long standing allocations
allocator: std.mem.Allocator = undefined,

// Vulkan data
instance: c.VkInstance = null,
debug_messenger: c.VkDebugUtilsMessengerEXT = null,

physical_device: c.VkPhysicalDevice = null,
physical_device_properties: c.VkPhysicalDeviceProperties = undefined,

device: c.VkDevice = null,
surface: c.VkSurfaceKHR = null,

swapchain: c.VkSwapchainKHR = null,
swapchain_format: c.VkFormat = undefined,
swapchain_extent: c.VkExtent2D = undefined,
swapchain_images: []c.VkImage = undefined,
swapchain_image_views: []c.VkImageView = undefined,

graphics_queue: c.VkQueue = null,
graphics_queue_family: u32 = undefined,
present_queue: c.VkQueue = null,
present_queue_family: u32 = undefined,

render_pass: c.VkRenderPass = null,
no_clear_render_pass: c.VkRenderPass = null,
present_render_pass: c.VkRenderPass = null,
framebuffers: []c.VkFramebuffer = undefined,

depth_image_view: c.VkImageView = null,
depth_image: AllocatedImage = undefined,
depth_format: c.VkFormat = undefined,

upload_context: UploadContext = .{},

frames: [FRAME_OVERLAP]FrameData = .{FrameData{}} ** FRAME_OVERLAP,

camera_and_scene_set: c.VkDescriptorSet = null,
camera_and_scene_buffer: AllocatedBuffer = undefined,

global_set_layout: c.VkDescriptorSetLayout = null,
object_set_layout: c.VkDescriptorSetLayout = null,
texture_set_layout: c.VkDescriptorSetLayout = null,
shaders_set_layouts: std.AutoHashMap(u32, c.VkDescriptorSetLayout) = undefined,
descriptor_pool: c.VkDescriptorPool = null,

vma_allocator: c.VmaAllocator = undefined,

deletion_queue: std.ArrayList(VulkanDeleter) = undefined,
buffer_deletion_queue: std.ArrayList(VmaBufferDeleter) = undefined,
image_deletion_queue: std.ArrayList(VmaImageDeleter) = undefined,

current_image_idx: u32 = 0,

pub const MeshPushConstants = extern struct {
    render_matrix: Mat4,
};

pub const VulkanDeleter = struct {
    object: ?*anyopaque,
    delete_fn: *const fn (entry: *VulkanDeleter, self: *Self) void,

    pub fn delete(self: *VulkanDeleter, engine: *Self) void {
        self.delete_fn(self, engine);
    }

    pub fn make(object: anytype, func: anytype) VulkanDeleter {
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
                fn f(entry: *VulkanDeleter, self: *Self) void {
                    const obj: @TypeOf(object) = @ptrCast(entry.object);
                    func(self.device, obj, vk_alloc_cbs);
                }
            }.f,
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

    pub fn delete(self: *VmaImageDeleter, engine: *Self) void {
        c.vmaDestroyImage(engine.vma_allocator, self.image.image, self.image.allocation);
    }
};

pub fn init(a: std.mem.Allocator, window: *c.SDL_Window) Self {
    var engine = Self{
        .window = window,
        .allocator = a,
        .shaders_set_layouts = std.AutoHashMap(u32, c.VkDescriptorSetLayout).init(a),
        .deletion_queue = std.ArrayList(VulkanDeleter).init(a),
        .buffer_deletion_queue = std.ArrayList(VmaBufferDeleter).init(a),
        .image_deletion_queue = std.ArrayList(VmaImageDeleter).init(a),
    };

    engine.initInstance();

    // Create the window surface
    utils.checkSdl(c.SDL_Vulkan_CreateSurface(window, engine.instance, vk_alloc_cbs, &engine.surface));

    engine.initDevice();

    // Create a VMA allocator
    const allocator_ci = std.mem.zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = engine.physical_device,
        .device = engine.device,
        .instance = engine.instance,
    });
    check_vk(c.vmaCreateAllocator(&allocator_ci, &engine.vma_allocator)) catch @panic("Failed to create VMA allocator");

    engine.initSwapchain();
    engine.initDepthImage();
    engine.initCommands();
    engine.initDefaultRenderpass();
    engine.initFramebuffers();
    engine.initSyncStructures();
    engine.initDescriptors();

    return engine;
}

fn initInstance(self: *Self) void {
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

fn initDevice(self: *Self) void {
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

fn initSwapchain(self: *Self) void {
    var win_width: c_int = undefined;
    var win_height: c_int = undefined;
    utils.checkSdl(c.SDL_GetWindowSize(self.window, &win_width, &win_height));

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

    log.info("Created swapchain", .{});
}

fn deinitSwapchain(self: *Self) void {
    for (self.swapchain_image_views) |view|
        c.vkDestroyImageView(self.device, view, vk_alloc_cbs);
    c.vkDestroySwapchainKHR(self.device, self.swapchain, vk_alloc_cbs);

    self.allocator.free(self.swapchain_image_views);
    self.allocator.free(self.swapchain_images);
}

fn initDepthImage(self: *Self) void {
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

    log.info("Created depth image", .{});
}

fn deinitDepthImage(self: *Self) void {
    c.vkDestroyImageView(self.device, self.depth_image_view, vk_alloc_cbs);
    c.vmaDestroyImage(self.vma_allocator, self.depth_image.image, self.depth_image.allocation);
}

fn recreateSwapchain(self: *Self) void {
    check_vk(c.vkDeviceWaitIdle(self.device)) catch @panic("Failed to wait device idle");
    self.deinitSwapchain();
    self.deinitDepthImage();
    self.deinitFramebuffers();

    self.initSwapchain();
    self.initDepthImage();
    self.initFramebuffers();
}

fn initCommands(self: *Self) void {
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

fn initDefaultRenderpass(self: *Self) void {
    // Color attachement
    const color_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.swapchain_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
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

    // Color attachement
    const no_clear_color_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.swapchain_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .finalLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    });

    const no_clear_color_attachment_ref = std.mem.zeroInit(c.VkAttachmentReference, .{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    });

    // Depth attachment
    const no_clear_depth_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.depth_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });

    const no_clear_depth_attachement_ref = std.mem.zeroInit(c.VkAttachmentReference, .{
        .attachment = 1,
        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });

    // Subpass
    const no_clear_subpass = std.mem.zeroInit(c.VkSubpassDescription, .{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &no_clear_color_attachment_ref,
        .pDepthStencilAttachment = &no_clear_depth_attachement_ref,
    });

    const no_clear_attachment_descriptions = [_]c.VkAttachmentDescription{
        no_clear_color_attachment,
        no_clear_depth_attachment,
    };

    const no_clear_render_pass_create_info = std.mem.zeroInit(c.VkRenderPassCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = @as(u32, @intCast(no_clear_attachment_descriptions.len)),
        .pAttachments = no_clear_attachment_descriptions[0..].ptr,
        .subpassCount = 1,
        .pSubpasses = &no_clear_subpass,
        .dependencyCount = @as(u32, @intCast(dependecies.len)),
        .pDependencies = &dependecies[0],
    });

    check_vk(c.vkCreateRenderPass(self.device, &no_clear_render_pass_create_info, vk_alloc_cbs, &self.no_clear_render_pass)) catch @panic("Failed to create render pass");
    self.deletion_queue.append(VulkanDeleter.make(self.no_clear_render_pass, c.vkDestroyRenderPass)) catch @panic("Out of memory");

    // Color attachement
    const present_color_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.swapchain_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    });

    const present_color_attachment_ref = std.mem.zeroInit(c.VkAttachmentReference, .{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    });

    // Depth attachment
    const present_depth_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.depth_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });

    const present_depth_attachement_ref = std.mem.zeroInit(c.VkAttachmentReference, .{
        .attachment = 1,
        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });

    // Subpass
    const present_subpass = std.mem.zeroInit(c.VkSubpassDescription, .{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &present_color_attachment_ref,
        .pDepthStencilAttachment = &present_depth_attachement_ref,
    });

    const present_attachment_descriptions = [_]c.VkAttachmentDescription{
        present_color_attachment,
        present_depth_attachment,
    };

    const present_render_pass_create_info = std.mem.zeroInit(c.VkRenderPassCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = @as(u32, @intCast(present_attachment_descriptions.len)),
        .pAttachments = present_attachment_descriptions[0..].ptr,
        .subpassCount = 1,
        .pSubpasses = &present_subpass,
        .dependencyCount = @as(u32, @intCast(dependecies.len)),
        .pDependencies = &dependecies[0],
    });

    check_vk(c.vkCreateRenderPass(self.device, &present_render_pass_create_info, vk_alloc_cbs, &self.present_render_pass)) catch @panic("Failed to create render pass");
    self.deletion_queue.append(VulkanDeleter.make(self.present_render_pass, c.vkDestroyRenderPass)) catch @panic("Out of memory");

    log.info("Created render pass", .{});
}

fn initFramebuffers(self: *Self) void {
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
    }

    log.info("Created {} framebuffers", .{self.framebuffers.len});
}

fn deinitFramebuffers(self: *Self) void {
    for (self.framebuffers) |framebuffer| {
        c.vkDestroyFramebuffer(self.device, framebuffer, vk_alloc_cbs);
    }

    self.allocator.free(self.framebuffers);
}

fn initSyncStructures(self: *Self) void {
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

pub const PipelineBuilder = struct {
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

    pub fn build(self: PipelineBuilder, device: c.VkDevice, render_pass: c.VkRenderPass) c.VkPipeline {
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
            .basePipelineHandle = null,
        });

        var pipeline: c.VkPipeline = undefined;
        check_vk(c.vkCreateGraphicsPipelines(device, null, 1, &pipeline_ci, vk_alloc_cbs, &pipeline)) catch {
            log.err("Failed to create graphics pipeline", .{});
            return null;
        };

        return pipeline;
    }
};

fn initDescriptors(self: *Self) void {
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
        .flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT, // TODO: only apply this in editor, runtime can precalculate the pool size
        .maxSets = 32,
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
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
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
        FRAME_OVERLAP * self.padUniformBufferSize(@sizeOf(GPUCameraData)) +
        FRAME_OVERLAP * self.padUniformBufferSize(@sizeOf(GPUSceneData));

    self.camera_and_scene_buffer = self.createBuffer(camera_and_scene_buffer_size, c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
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

    check_vk(c.vkCreateDescriptorSetLayout(self.device, &texture_set_ci, vk_alloc_cbs, &self.texture_set_layout)) catch @panic("Failed to create texture descriptor set layout");

    self.deletion_queue.append(VulkanDeleter.make(self.texture_set_layout, c.vkDestroyDescriptorSetLayout)) catch @panic("Out of memory");

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
        self.frames[i].object_buffer = self.createBuffer(
            MAX_OBJECTS * @sizeOf(GPUObjectData),
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
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

pub fn createShaderModule(self: *Self, code: []const u8) ?c.VkShaderModule {
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

pub fn deinit(self: *Self) void {
    check_vk(c.vkDeviceWaitIdle(self.device)) catch @panic("Failed to wait for device idle");

    self.shaders_set_layouts.deinit();

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

    self.deinitSwapchain();
    self.deinitDepthImage();
    self.deinitFramebuffers();

    c.vmaDestroyAllocator(self.vma_allocator);

    c.vkDestroyDevice(self.device, vk_alloc_cbs);
    c.vkDestroySurfaceKHR(self.instance, self.surface, vk_alloc_cbs);

    if (self.debug_messenger != null) {
        const destroy_fn = vki.get_destroy_debug_utils_messenger_fn(self.instance).?;
        destroy_fn(self.instance, self.debug_messenger, vk_alloc_cbs);
    }

    c.vkDestroyInstance(self.instance, vk_alloc_cbs);
    c.SDL_DestroyWindow(self.window);
}

pub fn uploadMesh(self: *Self, mesh: *Mesh) void {
    // Create a cpu buffer for staging
    const staging_buffer_ci = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = mesh.vertices_count * @sizeOf(Vertex),
        .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
    });

    const staging_buffer_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_CPU_ONLY,
    });

    var staging_buffer: AllocatedBuffer = undefined;
    check_vk(c.vmaCreateBuffer(self.vma_allocator, &staging_buffer_ci, &staging_buffer_ai, &staging_buffer.buffer, &staging_buffer.allocation, null)) catch @panic("Failed to create vertex buffer");

    log.info("Created staging buffer {}", .{@intFromPtr(mesh.vertex_buffer.buffer)});

    var data: ?*align(@alignOf(Vertex)) anyopaque = undefined;
    check_vk(c.vmaMapMemory(self.vma_allocator, staging_buffer.allocation, &data)) catch @panic("Failed to map vertex buffer");
    @memcpy(@as([*]Vertex, @ptrCast(data)), mesh.vertices[0..mesh.vertices_count]);
    c.vmaUnmapMemory(self.vma_allocator, staging_buffer.allocation);

    log.info("Copied mesh data into staging buffer", .{});

    const gpu_buffer_ci = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = mesh.vertices_count * @sizeOf(Vertex),
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
    self.immediateSubmit(struct {
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
        .size = mesh.vertices_count * @sizeOf(Vertex),
    });

    // We can free the staging buffer at this point.
    c.vmaDestroyBuffer(self.vma_allocator, staging_buffer.buffer, staging_buffer.allocation);
}

fn getCurrentFrame(self: *Self) FrameData {
    return self.frames[@intCast(@mod(self.frame_number, FRAME_OVERLAP))];
}

pub fn beginFrame(self: *Self) RenderCommand {
    // Wait until the GPU has finished rendering the last frame
    const timeout: u64 = 1_000_000_000; // 1 second in nanonesconds
    const frame = self.getCurrentFrame();

    check_vk(c.vkWaitForFences(self.device, 1, &frame.render_fence, c.VK_TRUE, timeout)) catch @panic("Failed to wait for render fence");
    check_vk(c.vkResetFences(self.device, 1, &frame.render_fence)) catch @panic("Failed to reset render fence");

    var swapchain_image_index: u32 = undefined;
    check_vk(c.vkAcquireNextImageKHR(
        self.device,
        self.swapchain,
        timeout,
        frame.present_semaphore,
        null,
        &swapchain_image_index,
    )) catch |err| switch (err) {
        error.vk_error_out_of_date_khr => {
            self.recreateSwapchain();
            return self.beginFrame();
        },
        else => @panic("Failed to acquire swapchain image"),
    };

    self.current_image_idx = swapchain_image_index;
    const cmd = frame.main_command_buffer;

    check_vk(c.vkResetCommandBuffer(cmd, 0)) catch @panic("Failed to reset command buffer");

    const cmd_begin_info = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });

    check_vk(c.vkBeginCommandBuffer(cmd, &cmd_begin_info)) catch @panic("Failed to begin command buffer");

    // Make a claer color that changes with each frame (120*pi frame period)
    // 0.11 and 0.12 fix for change in fabs
    const color = @abs(std.math.sin(@as(f32, @floatFromInt(self.frame_number)) / 120.0));

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

    return cmd;
}

pub fn endFrame(self: *Self, cmd: RenderCommand) void {
    const frame = self.getCurrentFrame();
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
        .pImageIndices = &self.current_image_idx,
    });

    check_vk(c.vkQueuePresentKHR(self.present_queue, &present_info)) catch |err| switch (err) {
        error.vk_error_out_of_date_khr => self.recreateSwapchain(),
        else => @panic("Failed to present swapchain image"),
    };
    self.frame_number +%= 1;
    self.object_buffer_offset = 0;
}

pub fn beginAdditiveRenderPass(self: *Self, cmd: RenderCommand, opts: struct { render_area: ?c.VkRect2D, clear_color: ?[4]f32 = null }) void {
    const color_clear: c.VkClearValue = .{
        .color = .{ .float32 = opts.clear_color orelse [_]f32{0} ** 4 },
    };

    const depth_clear = c.VkClearValue{
        .depthStencil = .{
            .depth = 1.0,
            .stencil = 1,
        },
    };

    const clear_values = [_]c.VkClearValue{
        color_clear,
        depth_clear,
    };
    const render_pass_begin_info = std.mem.zeroInit(c.VkRenderPassBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = if (opts.clear_color == null) self.no_clear_render_pass else self.render_pass,
        .framebuffer = self.framebuffers[self.current_image_idx],
        .renderArea = opts.render_area orelse c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        },
        .clearValueCount = @as(u32, @intCast(clear_values.len)),
        .pClearValues = &clear_values[0],
    });
    c.vkCmdEndRenderPass(cmd);
    c.vkCmdBeginRenderPass(cmd, &render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
}

pub fn beginPresentRenderPass(self: *Self, cmd: RenderCommand) void {
    const color_clear: c.VkClearValue = .{
        .color = .{ .float32 = [_]f32{ 0, 0, 0, 0 } },
    };

    const depth_clear = c.VkClearValue{
        .depthStencil = .{
            .depth = 1.0,
            .stencil = 1,
        },
    };

    const clear_values = [_]c.VkClearValue{
        color_clear,
        depth_clear,
    };
    const render_pass_begin_info = std.mem.zeroInit(c.VkRenderPassBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = self.present_render_pass,
        .framebuffer = self.framebuffers[self.current_image_idx],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        },
        .clearValueCount = @as(u32, @intCast(clear_values.len)),
        .pClearValues = &clear_values[0],
    });
    c.vkCmdEndRenderPass(cmd);
    c.vkCmdBeginRenderPass(cmd, &render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
}

pub fn drawObjects(
    self: *Self,
    cmd: c.VkCommandBuffer,
    opts: struct {
        transforms: []components.WorldTransform,
        meshes: []components.Mesh,
        materials: []components.Material,
        ubo_buf: AllocatedBuffer,
        ubo_set: c.VkDescriptorSet,
        cam: *const Camera,
        cam_pos: Vec3,
        point_lights: [4]GPUSceneData.GPULightData,
        directional_light: GPUSceneData.GPULightData = std.mem.zeroes(GPUSceneData.GPULightData),
    },
) void {
    // ----- Camera & Scene Data Setup -----
    const curr_camera_data = GPUCameraData.fromCamera(opts.cam, opts.cam_pos);
    const frame_index: usize = @intCast(@mod(self.frame_number, FRAME_OVERLAP));

    const padded_camera_data_size = self.padUniformBufferSize(@sizeOf(GPUCameraData));
    const scene_data_base_offset = padded_camera_data_size * FRAME_OVERLAP;
    const padded_scene_data_size = self.padUniformBufferSize(@sizeOf(GPUSceneData));

    const camera_data_offset = padded_camera_data_size * frame_index;
    const scene_data_offset = scene_data_base_offset + padded_scene_data_size * frame_index;

    var data: ?*align(@alignOf(GPUCameraData)) anyopaque = undefined;
    check_vk(c.vmaMapMemory(self.vma_allocator, opts.ubo_buf.allocation, &data)) catch @panic("Failed to map camera buffer");

    const camera_data: *GPUCameraData = @ptrFromInt(@intFromPtr(data) + camera_data_offset);
    const scene_data: *GPUSceneData = @ptrFromInt(@intFromPtr(data) + scene_data_offset);
    camera_data.* = curr_camera_data;
    scene_data.point_lights = opts.point_lights;
    scene_data.directional_light = opts.directional_light;
    scene_data.ambient_color = Vec3.scalar(1).toVec4(0.01);
    scene_data.exposure = 4.5;
    scene_data.gamma = 2.2;

    c.vmaUnmapMemory(self.vma_allocator, opts.ubo_buf.allocation);

    // ----- Object Buffer Batch Setup -----
    var currentFrame = self.getCurrentFrame();
    const batch_offset = self.object_buffer_offset;

    const num_objects = opts.transforms.len;
    std.debug.assert(batch_offset + num_objects <= MAX_OBJECTS);

    // Map the object buffer and write GPUObjectData for the objects in this batch.
    var object_data: ?*align(@alignOf(GPUObjectData)) anyopaque = undefined;
    check_vk(c.vmaMapMemory(self.vma_allocator, currentFrame.object_buffer.allocation, &object_data)) catch @panic("Failed to map object buffer");

    // Cast the pointer to an array pointer. We assume that object_buffer is large enough.
    var object_data_arr: [*]GPUObjectData = @ptrCast(object_data orelse unreachable);
    for (opts.transforms, 0..) |*transform, index| {
        // Write into the region starting at the batch_offset.
        object_data_arr[batch_offset + index] = GPUObjectData{
            .model_matrix = transform.matrix,
        };
    }
    c.vmaUnmapMemory(self.vma_allocator, currentFrame.object_buffer.allocation);

    // Advance the offset for subsequent batches in this frame.
    self.object_buffer_offset += num_objects;

    // ----- Issue Draw Calls Using the Correct Buffer Region -----
    for (opts.materials, opts.meshes, 0..) |material, *mesh, index| {
        if (index == 0 or material.ref != opts.materials[index - 1].ref) {
            c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, material.ref.pipeline);

            const uniform_offsets = [_]u32{
                @as(u32, @intCast(camera_data_offset)),
                @as(u32, @intCast(scene_data_offset)),
            };

            c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, material.ref.pipeline_layout, 0, 1, &opts.ubo_set, @as(u32, @intCast(uniform_offsets.len)), &uniform_offsets[0]);

            c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, material.ref.pipeline_layout, 1, 1, &currentFrame.object_descriptor_set, 0, null);
        }

        if (material.ref.rsc_descriptor_set != null) {
            c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, material.ref.pipeline_layout, 2, 1, &material.ref.rsc_descriptor_set, 0, null);
        }

        // const push_constants = MeshPushConstants{
        //     .render_matrix = ltw.value.mul(matrix.value),
        // };
        //
        // c.vkCmdPushConstants(cmd, material.ref.pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(MeshPushConstants), &push_constants);

        if (index == 0 or mesh != &opts.meshes[index - 1]) {
            const offset: c.VkDeviceSize = 0;
            c.vkCmdBindVertexBuffers(cmd, 0, 1, &mesh.vertex_buffer.buffer, &offset);
        }

        // we add batch_offset to the instance index.
        c.vkCmdDraw(cmd, @as(u32, @intCast(mesh.vertices_count)), 1, 0, @intCast(batch_offset + index));
    }
}

pub fn createBuffer(self: *Self, alloc_size: usize, usage: c.VkBufferUsageFlags, memory_usage: c.VmaMemoryUsage) AllocatedBuffer {
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

pub fn padUniformBufferSize(self: *Self, original_size: usize) usize {
    const min_ubo_alignment = @as(usize, @intCast(self.physical_device_properties.limits.minUniformBufferOffsetAlignment));
    const aligned_size = (original_size + min_ubo_alignment - 1) & ~(min_ubo_alignment - 1);
    return aligned_size;
}

pub fn immediateSubmit(self: *Self, submit_ctx: anytype) void {
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

pub fn getDescriptorSetLayout(self: *Self, layout: []const Shader.Def.Uniform) !c.VkDescriptorSetLayout {
    const pattern = Shader.Def.Uniform.bindingLayoutHash(layout);
    const entry = try self.shaders_set_layouts.getOrPut(pattern);
    if (entry.found_existing) {
        return entry.value_ptr.*;
    }

    const bindings = try self.allocator.alloc(c.VkDescriptorSetLayoutBinding, layout.len);
    defer self.allocator.free(bindings);

    for (layout, 0..) |uniform, i| {
        bindings[i] = switch (uniform.kind) {
            .texture => std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{
                .binding = @as(u32, @intCast(i)),
                .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            }),
            .cube => @panic("TODO"),
        };
    }

    const set_ci = std.mem.zeroInit(c.VkDescriptorSetLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = @as(u32, @intCast(bindings.len)),
        .pBindings = bindings.ptr,
    });

    check_vk(c.vkCreateDescriptorSetLayout(self.device, &set_ci, vk_alloc_cbs, entry.value_ptr)) catch @panic("Failed to create texture descriptor set layout");

    self.deletion_queue.append(VulkanDeleter.make(entry.value_ptr.*, c.vkDestroyDescriptorSetLayout)) catch @panic("Out of memory");
    return entry.value_ptr.*;
}
