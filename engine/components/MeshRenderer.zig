const Object = @import("../scene.zig").Object;
const Component = @import("../scene.zig").Component;
const Mesh = @import("../mesh.zig").Mesh;
const BoundingBox = @import("../mesh.zig").BoundingBox;
const Material = @import("../VulkanEngine.zig").Material;

const typeId = @import("../utils.zig").typeId;

const Self = @This();
object: *Object,
mesh: *Mesh,
material: *Material,

pub fn init(object: *Object, opts: struct { mesh: *Mesh, material: *Material }) Self {
    return .{
        .object = object,
        .mesh = opts.mesh,
        .material = opts.material,
    };
}

pub fn bounds(self: *const @This()) BoundingBox {
    return self.mesh.bounds;
}

pub fn worldBounds(self: *const @This()) BoundingBox {
    return self.bounds().translate(self.object.transform);
}

pub fn asComponent(self: *@This()) Component {
    return .{
        .type_id = typeId(@This()),
        .name = "Mesh Renderer",
        .ptr = self,
        .bounds = struct {
            fn bounds(ptr: *anyopaque) BoundingBox {
                return Self.bounds(@ptrCast(@alignCast(ptr)));
            }
        }.bounds,
    };
}
