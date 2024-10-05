const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");
const Allocator = std.mem.Allocator;

const List = @import("../../collections/List.zig").List;
const VulkanWindow = @import("../../window/vulkan/VulkanWindow.zig");

const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

const apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = .{
            .createInstance = true,
            // .getInstanceProcAddr = true,
            // .enumerateInstanceLayerProperties = true,
            // .enumerateInstanceExtensionProperties = true,
        },
        .instance_commands = .{
            .createDevice = true,
        },
    },
    vk.features.version_1_0,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
    // vk.extensions.ext_debug_utils,
};

const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);
const DeviceDispatch = vk.DeviceWrapper(apis);

pub const Instance = vk.InstanceProxy(apis);
const Device = vk.DeviceProxy(apis);

const Self = @This();
// const device_extensions = .{ VK_KHR_SWAPCHAIN_EXTENSION_NAME };
allocator: Allocator,

vkb: BaseDispatch,

instance: Instance,
physical_device: vk.PhysicalDevice,
command_pool: vk.CommandPool,

device: Device,
surface: vk.SurfaceKHR,
graphics_queue: vk.Queue,
present_queue: vk.Queue,

properties: vk.PhysicalDeviceProperties,

window: *VulkanWindow,
options: VulkanDeviceOptions,

pub fn init(allocator: Allocator, window: *VulkanWindow, comptime options: VulkanDeviceOptions) !Self {
    var vkb = try BaseDispatch.load(
        &struct {
            fn call(vk_instance: vk.Instance, proc_name: [*:0]const u8) callconv(vk.vulkan_call_conv) ?glfw.VKProc {
                var instance = vk_instance;
                return glfw.getInstanceProcAddress(@as(?*anyopaque, @ptrCast(&instance)), proc_name);
            }
        }.call,
    );
    var instance = try createInstance(allocator, &vkb, options);
    errdefer instance.destroyInstance(null);

    var surface: vk.SurfaceKHR = undefined;
    try window.createWindowSurface(instance.handle, &surface);

    const candidate = try pickPhysicalDevice(allocator, instance, &surface);
    const physical_device = candidate.device;
    const properties = candidate.props;
    const queues = candidate.queues;

    const logical_device = try createLogicalDevice(instance, &candidate);
    const vkd = try allocator.create(DeviceDispatch);
    errdefer allocator.destroy(vkd);
    vkd.* = try DeviceDispatch.load(logical_device, instance.wrapper.dispatch.vkGetDeviceProcAddr);
    const device = Device.init(logical_device, vkd);
    errdefer device.destroyDevice(null);

    const graphics_queue = device.getDeviceQueue(queues.graphics_family, 0);
    const present_queue = device.getDeviceQueue(queues.present_family, 0);

    const command_pool = try createCommandPool(device, queues.graphics_family);

    return Self{
        .allocator = allocator,

        .vkb = vkb,

        .instance = instance,
        .physical_device = physical_device,
        .command_pool = command_pool,

        .device = device,
        .surface = surface,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,

        .properties = properties,

        .window = window,
        .options = options,
    };
}

pub fn deinit(self: *Self) void {
    self.device.destroyCommandPool(self.command_pool, null);
    self.device.destroyDevice(null);

    if (self.options.enable_validation_layers) {
        // TODO: destroy debug utils messenger ext
    }

    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
}

pub fn createBuffer(
    self: *Self,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    properties: vk.MemoryPropertyFlags,
) !struct {
    buf: vk.Buffer,
    mem: vk.DeviceMemory,
} {
    const buffer_info = vk.BufferCreateInfo{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    };

    const buffer = try self.device.createBuffer(&buffer_info, null);

    const memory_requirements = self.device.getBufferMemoryRequirements(buffer);
    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = memory_requirements.size,
        .memory_type_index = try self.findMemoryType(memory_requirements.memory_type_bits, properties),
    };

    const buffer_memory = try self.device.allocateMemory(&alloc_info, null);
    try self.device.bindBufferMemory(buffer, buffer_memory, 0);
    return .{ .buf = buffer, .mem = buffer_memory };
}

fn findMemoryType(self: *Self, type_filter: u32, properties: vk.MemoryPropertyFlags) !u32 {
    const memory_properties = self.instance.getPhysicalDeviceMemoryProperties(self.physical_device);
    for (0..memory_properties.memory_type_count) |i| {
        if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
            (memory_properties.memory_types[i].property_flags.intersect(properties).toInt() != 0))
        {
            return @as(u32, @truncate(i));
        }
    }

    return error.UnableToFindSuitableMemoryType;
}

fn createInstance(allocator: Allocator, vkb: *BaseDispatch, comptime options: VulkanDeviceOptions) !Instance {
    if (options.enable_validation_layers and !try checkValidationLayerSupport(allocator, vkb)) {
        return error.ValidationLayerUnsupported;
    }
    const app_info = vk.ApplicationInfo{
        .p_application_name = "YumeEngine",
        .application_version = vk.makeApiVersion(0, 1, 0, 0),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(0, 1, 0, 0),
        .api_version = vk.makeApiVersion(0, 1, 0, 0),
    };

    const extensions = getRequiredExtensions(allocator, options) catch return error.OutOfMemory;
    defer extensions.deinit();

    var create_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = @as(u32, @truncate(extensions.items.len)),
        .pp_enabled_extension_names = extensions.items.ptr,
    };

    if (options.enable_validation_layers) {
        create_info.enabled_layer_count = validation_layers.len;
        create_info.pp_enabled_layer_names = &validation_layers;
        const debug_create_info = vk.DebugUtilsMessengerCreateInfoEXT{
            .message_severity = .{ .warning_bit_ext = true },
            .message_type = .{ .general_bit_ext = true },
            .pfn_user_callback = &debug_callback,
        };
        create_info.p_next = &debug_create_info;
    } else {
        create_info.enabled_layer_count = 0;
        create_info.p_next = null;
    }

    const instance = try vkb.createInstance(&create_info, null);
    const vki = try allocator.create(InstanceDispatch);
    errdefer allocator.destroy(vki);
    vki.* = try InstanceDispatch.load(instance, vkb.dispatch.vkGetInstanceProcAddr);

    try ensureGlfwRequiredInstanceExtentions(allocator, vkb, options);

    switch (instance) {
        .null_handle => return error.InstanceInitializationFailed,
        else => return Instance.init(instance, vki),
    }
}

fn checkValidationLayerSupport(allocator: Allocator, vkb: *BaseDispatch) !bool {
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(allocator);

    for (validation_layers) |layer_name| {
        var layer_found = false;
        for (available_layers) |layer_props| {
            std.debug.print("eql?: {s} == {s}\n", .{ std.mem.span(layer_name), &layer_props.layer_name });
            if (std.mem.eql(u8, std.mem.span(layer_name), &layer_props.layer_name)) {
                layer_found = true;
                break;
            }
        }

        if (!layer_found) {
            return false;
        }
    }

    return true;
}

fn getRequiredExtensions(allocator: Allocator, comptime options: VulkanDeviceOptions) error{ VulkanUnavailable, OutOfMemory }!List([*:0]const u8) {
    const glfw_extensions: [][*:0]const u8 = glfw.getRequiredInstanceExtensions() orelse return error.VulkanUnavailable;
    var extensions = List([*:0]const u8).initCapacity(allocator, glfw_extensions.len + 1) catch return error.OutOfMemory;
    extensions.appendSliceAssumeCapacity(glfw_extensions);

    if (options.enable_validation_layers) {
        extensions.appendAssumeCapacity("VK_EXT_debug_utils");
    }

    return extensions;
}

pub const VulkanDeviceOptions = struct {
    enable_validation_layers: bool = true,
};

fn ensureGlfwRequiredInstanceExtentions(allocator: Allocator, vkb: *BaseDispatch, comptime options: VulkanDeviceOptions) !void {
    const extensions = try vkb.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
    std.debug.print("available extensions:\n", .{});
    var available = std.StringHashMap(void).init(allocator);
    defer {
        var keys = available.keyIterator();
        while (keys.next()) |key| {
            allocator.free(key.*);
        }
        available.deinit();
    }
    for (extensions) |extension| {
        const p = std.mem.span(@as([*:0]const u8, @ptrCast(&extension.extension_name)));
        const copy = try allocator.dupe(u8, p);
        std.debug.print("\t {s}\n", .{copy});
        try available.put(copy, {});
    }

    std.debug.print("required extensions:\n", .{});
    const required_extensions = try getRequiredExtensions(allocator, options);
    defer required_extensions.deinit();

    for (required_extensions.items) |required| {
        std.debug.print("\t {s}\n", .{required});
        if (!available.contains(std.mem.span(required))) {
            return error.MissingGLFWRequiredExt;
        }
    }
}

fn pickPhysicalDevice(allocator: Allocator, instance: Instance, surface: *vk.SurfaceKHR) !DeviceCandidate {
    const devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    std.debug.print("Device count: {}\n", .{devices.len});

    for (devices) |device| {
        const queues = try findQueueFamilies(device, instance, surface, allocator);
        if (try isDeviceSuitable(device, &queues, instance, surface, allocator)) {
            const props = instance.getPhysicalDeviceProperties(device);
            std.debug.print("{s}\n", .{props.device_name});
            return .{ .device = device, .props = props, .queues = queues };
        }
    }

    return error.NoSuitableDevice;
}

fn checkDeviceExtensionSupport(device: vk.PhysicalDevice, instance: Instance, allocator: Allocator) !bool {
    const available_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(device, null, allocator);
    var required_extensions = std.StringHashMap(void).init(allocator);
    defer required_extensions.deinit();

    for (device_extensions) |ext| {
        try required_extensions.put(std.mem.span(ext), {});
    }

    for (available_extensions) |ext| {
        const p = std.mem.span(@as([*:0]const u8, @ptrCast(&ext.extension_name)));
        _ = required_extensions.remove(p);
        if (required_extensions.count() == 0) {
            break;
        }
    }

    return required_extensions.count() == 0;
}

fn isDeviceSuitable(device: vk.PhysicalDevice, queues: *const QueueFamilyIndices, instance: Instance, surface: *vk.SurfaceKHR, allocator: Allocator) !bool {
    if (!queues.isComplete()) {
        return false;
    }

    const extensions_supported = try checkDeviceExtensionSupport(device, instance, allocator);
    var swap_chain_adequate = false;
    if (extensions_supported) {
        const swap_chain_support = try querySwapChainSupport(device, instance, surface, allocator);
        swap_chain_adequate = swap_chain_support.formats.len != 0 and swap_chain_support.present_modes.len != 0;
    }

    const supported_features = instance.getPhysicalDeviceFeatures(device);

    return extensions_supported and swap_chain_adequate and supported_features.sampler_anisotropy == vk.TRUE;
}

fn querySwapChainSupport(device: vk.PhysicalDevice, instance: Instance, surface: *vk.SurfaceKHR, allocator: Allocator) !SwapChainSupportDetails {
    const capabilities = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(device, surface.*);
    const formats = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(device, surface.*, allocator);
    const present_modes = try instance.getPhysicalDeviceSurfacePresentModesAllocKHR(device, surface.*, allocator);
    return .{
        .capabilities = capabilities,
        .formats = formats,
        .present_modes = present_modes,
    };
}

fn findQueueFamilies(device: vk.PhysicalDevice, instance: Instance, surface: *vk.SurfaceKHR, allocator: Allocator) !QueueFamilyIndices {
    const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, allocator);
    var queues: QueueFamilyIndices = undefined;

    for (queue_families, 0..) |queue_family, i| {
        const i_32 = @as(u32, @truncate(i));
        if (queue_family.queue_count > 0 and queue_family.queue_flags.contains(.{ .graphics_bit = true })) {
            queues.graphics_family = i_32;
            queues.graphics_family_has_value = true;
        }

        const present_support = try instance.getPhysicalDeviceSurfaceSupportKHR(device, i_32, surface.*);
        if (queue_family.queue_count > 0 and present_support == vk.TRUE) {
            queues.present_family = i_32;
            queues.present_family_has_value = true;
        }
        if (queues.isComplete()) {
            break;
        }
    }

    return queues;
}

fn createLogicalDevice(instance: Instance, candidate: *const DeviceCandidate) !vk.Device {
    const queue_priority = [_]f32{1};
    const queue_create_infos = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &queue_priority,
        },
        .{
            .queue_family_index = candidate.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &queue_priority,
        },
    };
    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family) 1 else 2;
    return try instance.createDevice(candidate.device, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &queue_create_infos,
        .enabled_extension_count = device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&device_extensions),
    }, null);
}

fn createCommandPool(device: Device, queue_family_index: u32) !vk.CommandPool {
    const pool_info = vk.CommandPoolCreateInfo{
        .queue_family_index = queue_family_index,
        .flags = vk.CommandPoolCreateFlags{
            .transient_bit = true,
            .reset_command_buffer_bit = true,
        },
    };
    return try device.createCommandPool(&pool_info, null);
}

const DeviceCandidate = struct {
    device: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueFamilyIndices,
};

const QueueFamilyIndices = struct {
    graphics_family: u32,
    present_family: u32,
    graphics_family_has_value: bool = false,
    present_family_has_value: bool = false,

    fn isComplete(self: *const QueueFamilyIndices) bool {
        return self.graphics_family_has_value and self.present_family_has_value;
    }
};

const SwapChainSupportDetails = struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
};

fn debug_callback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_severity;
    _ = message_types;
    _ = p_user_data;
    std.debug.print("{?s}\n", .{p_callback_data.?.p_message});
    return vk.FALSE;
}
