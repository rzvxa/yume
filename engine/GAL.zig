pub const RenderApi = @import("GAL/vulkan/RenderApi.zig");

pub const frame_overlap = RenderApi.frame_overlap;

pub const Error = RenderApi.Error;

pub const CommandBuffer = RenderApi.CommandBuffer;
pub const ShaderModule = RenderApi.ShaderModule;
pub const Pipeline = RenderApi.Pipeline;
pub const PipelineLayout = RenderApi.PipelineLayout;
pub const DescriptorSet = RenderApi.DescriptorSet;

pub const AllocationOptions = RenderApi.AllocationOptions;

pub const Image = RenderApi.Image;
pub const ImageView = RenderApi.ImageView;
pub const ImageTiling = RenderApi.ImageTiling;
pub const ImageUsageFlags = RenderApi.ImageUsageFlags;
pub const MemoryUsage = RenderApi.MemoryUsage;
pub const ImageCreateFlags = RenderApi.ImageUsageFlags;
pub const SampleCount = RenderApi.SampleCount;
pub const Sampler = RenderApi.Sampler;
pub const Format = RenderApi.Format;

pub const GPUAllocation = RenderApi.GPUAllocation;
pub const AllocatedBuffer = RenderApi.AllocatedBuffer;
pub const AllocatedImage_ = RenderApi.AllocatedImage_;

pub const GPUSceneData = RenderApi.GPUSceneData;
pub const GPUCameraData = RenderApi.GPUCameraData;

pub const MeshPushConstants = RenderApi.MeshPushConstants;
