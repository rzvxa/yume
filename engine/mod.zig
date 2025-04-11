pub const version = @import("cfg").version;

pub const Uuid = @import("uuid.zig").Uuid;

pub const ecs = @import("ecs.zig");
pub const components = @import("components.zig");
pub const systems = @import("systems.zig");

pub const GameApp = @import("GameApp.zig");
pub const VulkanEngine = @import("VulkanEngine.zig");
pub const Mesh = @import("mesh.zig");
pub const vki = @import("vulkan_init.zig");
pub const textures = @import("textures.zig");

pub const assets = @import("assets.zig");
pub const AssetsDatabase = assets.AssetsDatabase;
pub const AssetHandle = assets.AssetHandle;

pub const scene_graph = @import("scene.zig");
pub const Object = scene_graph.Object;
pub const Component = scene_graph.Component;

pub const math3d = @import("math3d.zig");
pub const Vec2 = math3d.Vec2;
pub const Vec3 = math3d.Vec3;
pub const Vec4 = math3d.Vec4;
pub const Mat4 = math3d.Mat4;
pub const Quat = math3d.Quat;
pub const Rect = math3d.Rect;

pub const AllocatedBuffer = VulkanEngine.AllocatedBuffer;
pub const FRAME_OVERLAP = VulkanEngine.FRAME_OVERLAP;
pub const GPUCameraData = VulkanEngine.GPUCameraData;
pub const GPUSceneData = VulkanEngine.GPUSceneData;
pub const VmaImageDeleter = VulkanEngine.VmaImageDeleter;
pub const VmaBufferDeleter = VulkanEngine.VmaBufferDeleter;
pub const VulkanDeleter = VulkanEngine.VulkanDeleter;

pub const inputs = @import("inputs.zig");

pub const utils = @import("utils.zig");
pub const TypeId = utils.TypeId;
pub const typeId = utils.typeId;

pub const Camera = @import("components/Camera.zig");
pub const MeshRenderer = @import("components/MeshRenderer.zig");
