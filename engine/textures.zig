const std = @import("std");
const c = @import("clibs");

const assets = @import("assets.zig");
const GAL = @import("GAL.zig");
const check_vk = GAL.RenderApi.check_vk;
const Urn = @import("Uuid.zig").Urn;

const log = std.log.scoped(.textures);

pub const Texture = struct {
    handle: assets.TextureHandle,
    image: GAL.AllocatedImage,
    image_view: GAL.ImageView,
    sampler: GAL.Sampler,
};

pub fn loadImage(renderer: *GAL.RenderApi, buffer: []const u8) !GAL.AllocatedImage {
    var width: c_int = undefined;
    var height: c_int = undefined;
    var channels: c_int = undefined;
    const format = c.VK_FORMAT_R8G8B8A8_UNORM;

    const pixels = c.stbi_load_from_memory(buffer.ptr, @intCast(buffer.len), &width, &height, &channels, c.STBI_rgb_alpha);
    if (pixels == null) {
        return error.failed_to_load_image;
    }
    defer c.stbi_image_free(pixels);

    return loadImageFromPixels(renderer, pixels, @intCast(width), @intCast(height), format);
}

pub fn loadImageFromPixels(
    renderer: *GAL.RenderApi,
    pixels: [*]const u8,
    width: usize,
    height: usize,
    format: c.VkFormat,
) !GAL.AllocatedImage {
    const image_size = @as(c.VkDeviceSize, @intCast(width * height * 4));

    const staging_buffer = renderer.createBuffer(image_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VMA_MEMORY_USAGE_CPU_ONLY);
    defer c.vmaDestroyBuffer(renderer.vma_allocator, staging_buffer.buffer, staging_buffer.allocation);

    const pixels_slice = pixels[0..image_size];

    var data: ?*anyopaque = null;
    try check_vk(c.vmaMapMemory(renderer.vma_allocator, staging_buffer.allocation, &data));
    @memcpy(@as([*]u8, @ptrCast(data orelse unreachable)), pixels_slice);

    c.vmaUnmapMemory(renderer.vma_allocator, staging_buffer.allocation);

    const extent = c.VkExtent3D{
        .width = @as(c_uint, @intCast(width)),
        .height = @as(c_uint, @intCast(height)),
        .depth = 1,
    };

    const img_info = std.mem.zeroInit(
        c.VkImageCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .format = format,
            .extent = extent,
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .tiling = c.VK_IMAGE_TILING_OPTIMAL,
            .usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
        },
    );

    const alloc_ci = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
    });

    var image: c.VkImage = undefined;
    var allocation: c.VmaAllocation = undefined;
    try check_vk(c.vmaCreateImage(renderer.vma_allocator, &img_info, &alloc_ci, &image, &allocation, null));
    if (allocation == null) {
        return error.failed_to_create_image;
    }

    // Tranfer CPU memory to GPU memory
    //
    renderer.immediateSubmit(struct {
        image: c.VkImage,
        extent: c.VkExtent3D,
        staging_buffer: GAL.AllocatedBuffer,

        pub fn submit(self: @This(), cmd: c.VkCommandBuffer) void {
            const range = std.mem.zeroInit(c.VkImageSubresourceRange, .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            });

            const barrier_to_transfer = std.mem.zeroInit(c.VkImageMemoryBarrier, .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                .srcAccessMask = 0,
                .dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
                .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                .newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .image = self.image,
                .subresourceRange = range,
            });

            c.vkCmdPipelineBarrier(cmd, c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, c.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier_to_transfer);

            const copy_region = std.mem.zeroInit(c.VkBufferImageCopy, .{
                .bufferOffset = 0,
                .bufferRowLength = 0,
                .bufferImageHeight = 0,
                .imageSubresource = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = 0,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
                .imageExtent = self.extent,
            });

            c.vkCmdCopyBufferToImage(cmd, self.staging_buffer.buffer, self.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy_region);

            const barrier_to_shader_read = std.mem.zeroInit(c.VkImageMemoryBarrier, .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                .srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
                .dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT,
                .oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                .newLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .image = self.image,
                .subresourceRange = range,
            });

            c.vkCmdPipelineBarrier(cmd, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier_to_shader_read);
        }
    }{
        .image = image,
        .extent = extent,
        .staging_buffer = staging_buffer,
    });

    return .{ .image = image, .allocation = allocation };
}
