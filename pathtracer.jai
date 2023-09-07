SCALE :: 2;
TIME  :: 1;
AA    :: 1;

main :: () {
    #assert(OS == .WINDOWS);

    the_window = create_window(WINDOW_WIDTH, WINDOW_HEIGHT, "Window Creation");

    window_dc := GetDC(the_window);

    backbuffer_info: BITMAPINFO;
    backbuffer_info.bmiHeader.biSize        = size_of(BITMAPINFOHEADER);
    backbuffer_info.bmiHeader.biWidth       = WINDOW_WIDTH;
    backbuffer_info.bmiHeader.biHeight      = WINDOW_HEIGHT;
    backbuffer_info.bmiHeader.biPlanes      = 1;
    backbuffer_info.bmiHeader.biBitCount    = 32;
    backbuffer_info.bmiHeader.biCompression = BI_RGB;

    // format: 0xAARRGGBB
    backbuffer    := NewArray(WINDOW_WIDTH * WINDOW_HEIGHT, u32);
    interm_buffer := NewArray(WINDOW_WIDTH * WINDOW_HEIGHT, Vector3);

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

    S :: 0.5;

    CUBE_NORMALS :: Vector3.[
    ];
    cube :: Mesh.{
        origin = .{50, 70, 10},
        scale  = 50,

        vertices = .[
            .{-S, -S, -S}, // 0
            .{ S, -S, -S}, // 1
            .{ S,  S, -S}, // 2
            .{-S,  S, -S}, // 3

            .{-S, -S,  S}, // 4
            .{ S, -S,  S}, // 5
            .{ S,  S,  S}, // 6
            .{-S,  S,  S}, // 7
        ],
        normals = .[
            .{-1,  0,  0}, // 0
            .{ 1,  0,  0}, // 1
            .{ 0, -1,  0}, // 2
            .{ 0,  1,  0}, // 3
            .{ 0,  0, -1}, // 4
            .{ 0,  0,  1}, // 5
        ],
        triangles = .[
            .{0, 1, 2,  4}, // Bottom face
            .{2, 3, 0,  4},

            .{0, 4, 3,  0}, // Left face
            .{3, 4, 7,  0},

            .{7, 4, 6,  5}, // Top face
            .{6, 4, 5,  5},

            .{5, 4, 0,  2}, // Front face
            .{0, 1, 5,  2},

            .{5, 1, 6,  1}, // Right face
            .{6, 1, 2,  1},

            .{2, 3, 6,  0}, // Left face
            .{6, 3, 4,  0},
        ],
    };

    entities := Entity.[
        .{ type = .SPHERE, sphere = .{ .{   0, 100,  0 }, 50}, material_index = 1 },
        .{ type = .SPHERE, sphere = .{ .{ -70,  80, 20 }, 30}, material_index = 2 },
        .{ type = .SPHERE, sphere = .{ .{  70,  50, 50 }, 10}, material_index = 2 },
        .{ type = . PLANE,  plane = .{ .{   0,   0,  1 },  0}, material_index = 3 },
        .{ type = .SPHERE, sphere = .{ .{  50,  30, 50 },  7}, material_index = 4 },
        .{ type = .  MESH,   mesh =                      cube, material_index = 2 },
    ];

    light_dir :: #run normalize(Vector3.{0.3, 1, -0.7});

    ray_to_entity :: (r: Ray, e: Entity) -> hit: bool, dist: float = -1, impact: Vector3 = .{}, normal: Vector3 = .{} {
        if e.type == {
            case .SPHERE;
                s := *e.sphere;
                assert(!is_approximately_zero(length_squared(r.dir)));

                co := r.origin - s.center;

                b := dot(r.dir, co);
                discriminant := b*b - (length_squared(co) - (s.radius * s.radius));

                if discriminant < 0 {
                    return false;
                }

                dist := -b;
                if !is_approximately_zero(discriminant) {
                    discriminant = sqrt(discriminant);
                    dist -= discriminant;
                }

                impact := r.origin + r.dir * dist;
                return dist >= 0, dist, impact, (impact - s.center) / s.radius;

            case .PLANE;
                p := *e.plane;

                denom             := dot(r.dir, p.normal);
                if is_approximately_zero(denom) return false;

                relative_distance := p.distance - dot(r.origin, p.normal);

                dist   := relative_distance / denom;
                impact := r.origin + r.dir * dist;
                return dist >= 0.05, dist, impact, p.normal;

            case .MESH;
                m := *e.mesh;

                hit_found     := false;
                impact_dist   := max_of_type(float);
                impact_point  :  Vector3;
                impact_normal :  Vector3;
                for m.triangles {
                    using it;

                    v0 := m.origin + m.scale * m.vertices[i0];
                    v1 := m.origin + m.scale * m.vertices[i1];
                    v2 := m.origin + m.scale * m.vertices[i2];

                    p_normal   := m.normals[n];
                    p_distance := dot(v0, p_normal);

                    denom := dot(r.dir, p_normal);
                    if denom > -0.01 continue; // we only want to hit triangles that are facing the ray

                    relative_distance := p_distance - dot(r.origin, p_normal);

                    test_dist   := relative_distance / denom;
                    test_impact := r.origin + r.dir * test_dist;
                    if test_dist >= 0.02 && test_dist < impact_dist {
                        if dot(cross(v1 - v0, test_impact - v0), r.dir) > 0 continue;
                        if dot(cross(v2 - v1, test_impact - v1), r.dir) > 0 continue;
                        if dot(cross(v0 - v2, test_impact - v2), r.dir) > 0 continue;

                        hit_found     = true;
                        impact_dist   = test_dist;
                        impact_point  = test_impact;
                        impact_normal = p_normal;
                    }
                }
                return hit_found, impact_dist, impact_point, impact_normal;
            }

        return false;
    }

    CAMERA_ZOOM : float : 1.5;

    #if TIME {
       last_t := current_time_monotonic();
       current_t := last_t;
       dt_acc    : float64;
       frame_count := 0;
       FRAME_AVERAGE_AMOUNT :: 10;
       INV_FRAME_AVERAGE :: cast(float64)1.0 / FRAME_AVERAGE_AMOUNT;
    }

    sample_count      := 0;

    NUMBER_OF_SAMPLES_BETWEEN_RENDERS :: 2;
    frame_display_countdown := 1;

    quit := false;
    while !quit {
        sample_count += 1;
        update_window_events();

        for events_this_frame {
            if it.type == .QUIT then quit = true;

            if it.type == .KEYBOARD {
                if it.key_pressed == 0 continue;

                if it.key_code == .ESCAPE {
                    quit = true;
                }
            }
        }

        // ===========

        x : u32;
        y : u32;
        for *interm_pixel: interm_buffer {

            defer { x += 1; if x == WINDOW_WIDTH { y += 1; x  = 0; } }

            fx := cast(float)x;
            fy := cast(float)y;

            #if AA {
                fx += random_get_zero_to_one();
                fy += random_get_zero_to_one();
            }

            fx -= 0.5*WINDOW_WIDTH;  fx /= WINDOW_HEIGHT;
            fy -= 0.5*WINDOW_HEIGHT; fy /= WINDOW_HEIGHT;

            camera_center  :: Vector3.{0, -100, 100};
            camera_forward :: #run normalize(Vector3.{0, 100, 0} - camera_center);
            camera_right   :: #run normalize(cross(camera_forward, Vector3.{0, 0, 1}));
            camera_up      :: #run normalize(cross(camera_\ right, camera_forward));

            deprojected_pixel := camera_center + fx * camera_right + fy * camera_up + camera_forward * CAMERA_ZOOM;
            look_dir := normalize(deprojected_pixel - camera_center);

            ray             := Ray.{ origin = camera_center, dir = look_dir, };
            reflected_color :  Vector3;
            attenuation     := Vector3.{1, 1, 1};

            MAX_BOUNCES :: 10;
            bounces := 0;
            while true {
                defer bounces += 1;

                if bounces >= MAX_BOUNCES  break;

                hit_dist   := max_of_type(float);
                hit_entity : *Entity;
                hit_impact : Vector3 = ---;
                hit_normal : Vector3 = ---;

                for *entities {
                    hit, dist, impact, normal := ray_to_entity(ray, it.*);

                    if !hit continue;

                    if dist < hit_dist {
                        hit_dist   = dist;
                        hit_entity = it;
                        hit_impact = impact;
                        hit_normal = normal;
                    }
                }

                if !hit_entity {
                    reflected_color += attenuation * materials[0].color;
                    break;
                }

                hit_material := *materials[hit_entity.material_index];

                ray.origin = hit_impact;

                //if hit_material.transmissive {
                    //ray.origin = 
                    //continue;
                //}

                if hit_material.type == {
                    case .EMISSIVE; reflected_color += attenuation * hit_material.color;
                    case .DIFFUSE;  attenuation      = attenuation * hit_material.color * max(0.0, dot(-ray.dir, hit_normal));
                }

                rand_x := random_get_zero_to_one() * 2 - 1;
                rand_y := random_get_zero_to_one() * 2 - 1;
                rand_z := random_get_zero_to_one() * 2 - 1;

                specular_bounce := ray.dir - 2 * hit_normal * dot(ray.dir, hit_normal);
                scattered_bounce := normalize(hit_normal + .{rand_x, rand_y, rand_z});

                ray.dir = lerp(specular_bounce, scattered_bounce, hit_material.scatter);

            }

            interm_pixel.* += reflected_color;
        }

        frame_display_countdown -= 1;

        if frame_display_countdown == 0 {
            frame_display_countdown = NUMBER_OF_SAMPLES_BETWEEN_RENDERS;

            memset(backbuffer.data, 0xcd, size_of(u32) * backbuffer.count);

            interm_pixel := interm_buffer.data;
            for *pixel: backbuffer {
                defer interm_pixel += 1;

                linear_to_srgb :: (l: float) -> float #expand {
                    if l < 0 return 0;
                    if l > 1 return 1;

                    s := l * 12.92;
                    if l > 0.0031308 then s = 1.055 * pow(l, 1 / 2.4) - 0.055;

                    return s;
                }

                srgb_pixel : Vector3 = ---;

                denom := 1.0 / cast(float)sample_count;
                srgb_pixel.x = linear_to_srgb(interm_pixel.x * denom);
                srgb_pixel.y = linear_to_srgb(interm_pixel.y * denom);
                srgb_pixel.z = linear_to_srgb(interm_pixel.z * denom);

                r : u32 = cast(u8) (255 * srgb_pixel.x);
                g : u32 = cast(u8) (255 * srgb_pixel.y);
                b : u32 = cast(u8) (255 * srgb_pixel.z);

                pixel.* = 0xFF000000 | (r << 16) | (g << 8) | b;
            }


            // ===========
            StretchDIBits(window_dc, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
                                     0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
                          backbuffer.data, *backbuffer_info, DIB_RGB_COLORS, .SRCCOPY);
        }

        #if TIME {
        frame_count += 1;

        current_t = current_time_monotonic();
        dt_acc   += to_float64_seconds(current_t - last_t);
        last_t    = current_t;

        if frame_count >= FRAME_AVERAGE_AMOUNT {
            frame_count = 0;
            dt_acc *= INV_FRAME_AVERAGE;
            print("Average frame time: %;  FPS: %\n", dt_acc, 1.0 / cast(float)dt_acc);
            dt_acc = 0;
        }
        }
    }
}

#import "Basic";
#import "Windows";
#import "Window_Creation";
#import "Input";
#import "Math";
#import "Sloppy_Math";
#import "Random";

WINDOW_WIDTH  :: 640 * SCALE;
WINDOW_HEIGHT :: 360 * SCALE;
the_window: Window_Type;

#scope_file
// missing stuff from windows module
gdi :: #system_library "Gdi32";
StretchDIBits :: (hdc: HDC, xDest: int, yDest: int, DestWidth: int, DestHeight: int,
                            xSrc:  int, ySrc:  int, SrcWidth:  int, SrcHeight:  int,
                  lpBits: *void, lpbmi: *BITMAPINFO, iUsage: u32, rop: ROP) -> s32 #foreign gdi;


