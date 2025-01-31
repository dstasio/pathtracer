
Sphere :: struct {
    center         : Vector3;
    radius         : float;
}

Plane :: struct {
    normal         : Vector3;
    distance       : float;
}

Mesh :: struct {
    origin    :   Vector3;
    scale     :   float;

    vertices  : []Vector3;
    normals   : []Vector3;
    triangles : []Triangle;

    Triangle :: struct {
        i0 : u32;
        i1 : u32;
        i2 : u32;
        n  : u32;
    }
}

Entity :: struct {
    type: enum {
        SPHERE;
        PLANE;
        MESH;
    };

    union {
        sphere: Sphere = ---;
        plane : Plane  = ---;
        mesh  : Mesh;
    }

    material_index : int;
}

Ray :: struct {
    origin: Vector3;
    dir   : Vector3;
}


Material_Type :: enum u8 {
    EMISSIVE;
    DIFFUSE;
}

Material :: struct {
    type         : Material_Type;
    color        : Vector3;
    scatter      : float;
    transmissive : bool;
}
materials :: Material.[
    .{ .EMISSIVE, .{0.85, 0.86, 0.90}, 1.0, false },
    .{ . DIFFUSE, .{0.84, 0.94, 0.39}, 0.0, false },
    .{ . DIFFUSE, .{0.28, 0.67, 0.90}, 1.0, false },
    .{ . DIFFUSE, .{0.54, 0.94, 0.79}, 0.3, false },
    .{ . DIFFUSE, .{0.85, 0.33, 0.20}, 0.2, true },
];
