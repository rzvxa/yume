pub const RenderApi = @import("GAL/vulkan/RenderApi.zig");

pub const frame_overlap = RenderApi.frame_overlap;

pub const Error = RenderApi.Error;

pub const CommandBuffer = RenderApi.CommandBuffer;
pub const ShaderModule = RenderApi.ShaderModule;
pub const Pipeline = RenderApi.Pipeline;
pub const PipelineLayout = RenderApi.PipelineLayout;
pub const DescriptorSet = RenderApi.DescriptorSet;

pub const Image = RenderApi.Image;
pub const ImageView = RenderApi.ImageView;
pub const Sampler = RenderApi.Sampler;

pub const GPUAllocation = RenderApi.GPUAllocation;
pub const AllocatedBuffer = RenderApi.AllocatedBuffer;
pub const AllocatedImage = RenderApi.AllocatedImage;

pub const GPUSceneData = RenderApi.GPUSceneData;
pub const GPUCameraData = RenderApi.GPUCameraData;

pub const MeshPushConstants = RenderApi.MeshPushConstants;
