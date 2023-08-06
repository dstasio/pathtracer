TIME :: 1;

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
    backbuffer := NewArray(WINDOW_WIDTH * WINDOW_HEIGHT, u32);

    Material_Type :: enum u8 {
        EMISSIVE;
        DIFFUSE;
    }

    Material :: struct {
        type     : Material_Type;
        color    : Vector3;
        specular : bool;
    }
    materials :: Material.[
        .{ .EMISSIVE, .{0.85, 0.86, 0.9}, false },
        .{ . DIFFUSE, .{0.85, 0.33, 0.2}, true  },
        .{ . DIFFUSE, .{0.28, 0.67, 0.9}, false },
    ];

    Sphere :: struct {
        center         : Vector3;
        radius         : float = 50;
        material_index : int;
    }

    Ray :: struct {
        origin: Vector3;
        dir   : Vector3;
    }

    spheres := Sphere.[
        .{.{   0, 100, 0 }, 50, 1 },
        .{.{ -70,  80, 0 }, 30, 2 },
    ];

    light_dir :: #run normalize(Vector3.{0.3, 1, -0.7});

    ray_to_sphere :: (r: Ray, s: Sphere) -> hit: bool, dist: float = -1 {
        assert(!is_approximately_zero(length_squared(r.dir)));

        co := r.origin - s.center;

        b := dot(r.dir, co);
        discriminant := b*b - (length_squared(co) - (s.radius * s.radius));

	if discriminant < 0 {
            return false;
	}

        d := -b;
        if !is_approximately_zero(discriminant) {
            discriminant = sqrt(discriminant);
            d -= discriminant;
            //d1 := -b + discriminant;
        }

        if d < 0
            return false, d;

        return true, d;
    }

    raycast :: (r: Ray) -> hit_sphere: *Sphere, dist: float #expand {
        least_dist := max_of_type(float);
        hit_sphere : *Sphere;
        for *`spheres {
            hit, dist := ray_to_sphere(r, it.*);

            if !hit continue;

            if dist < least_dist {
                least_dist = dist;
                hit_sphere = it;
            }
        }

        return hit_sphere, least_dist;
    }

    camera_pos  : Vector3;
    CAMERA_SIZE : float : 100;

    #if TIME {
       last_t := current_time_monotonic();
    current_t := last_t;
    dt_acc    : float64;
    frame_count := 0;
    FRAME_AVERAGE_AMOUNT :: 20;
    INV_FRAME_AVERAGE :: cast(float64)1.0 / FRAME_AVERAGE_AMOUNT;
    }

    quit := false;
    while !quit {
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

        memset(backbuffer.data, 0xcd, size_of(u32) * backbuffer.count);

        // ===========

        x : u32;
        y : u32;
        for *pixel: backbuffer {
            defer { x += 1; if x == WINDOW_WIDTH { y += 1; x  = 0; } }

            SAMPLE_COUNT :: 1;
            SAMPLE_CONTRIB :: 1.0 / cast(float)SAMPLE_COUNT;

            pixel_color : Vector3;

            fx := cast(float)x;
            fy := cast(float)y;

            fx -= 0.5*WINDOW_WIDTH;
            fy -= 0.5*WINDOW_HEIGHT;

            fx *= CAMERA_SIZE / WINDOW_HEIGHT;
            fy *= CAMERA_SIZE / WINDOW_HEIGHT;

            LOOK_DIR :: Vector3.{0, 1, 0};

            for 0..SAMPLE_COUNT-1 {
                ray             := Ray.{ origin = .{fx, 0, fy}, dir = LOOK_DIR, };
                reflected_color :  Vector3;
                attenuation     := Vector3.{1, 1, 1};

                MAX_BOUNCES :: 10;
                bounces := 0;
                while true {
                    defer bounces += 1;

                    if bounces >= MAX_BOUNCES  break;

                    hit_sphere, hit_dist := raycast(ray);

                    if !hit_sphere {
                        reflected_color += attenuation * materials[0].color;
                        break;
                    }

                    hit_pos    := ray.origin + ray.dir * hit_dist;
                    hit_normal := hit_pos - hit_sphere.center;
                    hit_normal /= hit_sphere.radius;

                    hit_material := *materials[hit_sphere.material_index];

                    if hit_material.type == {
                        case .EMISSIVE; reflected_color += attenuation * hit_material.color;
                        case .DIFFUSE;  attenuation      = attenuation * hit_material.color * max(0.0, dot(-ray.dir, hit_normal));
                    }

                    ray.origin = hit_pos;

                    rand_x := random_get_zero_to_one() * 2 - 1;
                    rand_y := random_get_zero_to_one() * 2 - 1;
                    rand_z := random_get_zero_to_one() * 2 - 1;

                    if hit_material.specular {
                        specular_bounce := ray.dir - 2 * hit_normal * dot(ray.dir, hit_normal);
                        ray.dir = specular_bounce;
                    } else {
                        scattered_bounce := normalize(hit_normal + .{rand_x, rand_y, rand_z});
                        ray.dir = scattered_bounce;
                    }

                }

                pixel_color += reflected_color * SAMPLE_CONTRIB;
            }

            r : u32 = cast(u8) (255 * pixel_color.x);
            g : u32 = cast(u8) (255 * pixel_color.y);
            b : u32 = cast(u8) (255 * pixel_color.z);

            pixel.* = 0xFF000000 | (r << 16) | (g << 8) | b;
        }


        // ===========
        StretchDIBits(window_dc, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
                                 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
                      backbuffer.data, *backbuffer_info, DIB_RGB_COLORS, .SRCCOPY);

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

SCALE :: 1;
WINDOW_WIDTH  :: 640 * SCALE;
WINDOW_HEIGHT :: 360 * SCALE;
the_window: Window_Type;

#scope_file
// missing stuff from windows module
gdi :: #system_library "Gdi32";
StretchDIBits :: (hdc: HDC, xDest: int, yDest: int, DestWidth: int, DestHeight: int,
                            xSrc:  int, ySrc:  int, SrcWidth:  int, SrcHeight:  int,
                  lpBits: *void, lpbmi: *BITMAPINFO, iUsage: u32, rop: ROP) -> s32 #foreign gdi;


