// Compiler Version 0.2.008

SCALE :: 2;
TIME  :: 1;
AA    :: 1;

USE_NONTEMPORAL_STORE :: false;
SIMD :: true;

#load "entity.jai";
#load "logger.jai";

PIXEL_COUNT :: WINDOW_WIDTH * WINDOW_HEIGHT;

THREAD_COUNT          :: 8;
PIXELS_PER_WORK_BLOCK :: 16;
#assert (PIXELS_PER_WORK_BLOCK * size_of(Vector3)) % 64 == 0;

BLOCK_COUNT       :: #run ceil(cast(float, PIXEL_COUNT) / PIXELS_PER_WORK_BLOCK);
BLOCKS_PER_THREAD :: cast(int, #run ceil(BLOCK_COUNT / THREAD_COUNT));

PIXELS_PER_SAMPLING_WINDOW :: BLOCKS_PER_THREAD * PIXELS_PER_WORK_BLOCK;
//PIXELS_PER_SAMPLING_WINDOW :: 512;
SAMPLING_WINDOW_COUNT      :: #run cast(int, ceil(cast(float, PIXEL_COUNT) / PIXELS_PER_SAMPLING_WINDOW));


main :: () {
    #assert(OS == .WINDOWS);
    context.logger = my_logger;

    the_window = create_window(WINDOW_WIDTH, WINDOW_HEIGHT, "Pathtracer");

    window_dc := GetDC(the_window);

    backbuffer_info: BITMAPINFO;
    backbuffer_info.bmiHeader.biSize        = size_of(BITMAPINFOHEADER);
    backbuffer_info.bmiHeader.biWidth       = WINDOW_WIDTH;
    backbuffer_info.bmiHeader.biHeight      = WINDOW_HEIGHT;
    backbuffer_info.bmiHeader.biPlanes      = 1;
    backbuffer_info.bmiHeader.biBitCount    = 32;
    backbuffer_info.bmiHeader.biCompression = BI_RGB;

    // format: 0xAARRGGBB
    backbuffer    := NewArray(PIXEL_COUNT, u32);
    interm_buffer := NewArray(PIXEL_COUNT, Vector3);

    sampling_windows  : [SAMPLING_WINDOW_COUNT][]Vector3;
    backbuffer_windows: [SAMPLING_WINDOW_COUNT][]u32;

    current_frame := 0;
    for window_index : 0..sampling_windows.count-1 {
        sampling_windows[window_index].data  = interm_buffer.data + window_index * PIXELS_PER_SAMPLING_WINDOW;
        sampling_windows[window_index].count = PIXELS_PER_SAMPLING_WINDOW;

        backbuffer_windows[window_index].data  = backbuffer.data + window_index * PIXELS_PER_SAMPLING_WINDOW;
        backbuffer_windows[window_index].count = PIXELS_PER_SAMPLING_WINDOW;
    }
    sampling_windows  [  sampling_windows.count-1].count = PIXEL_COUNT - (  sampling_windows.count - 1) * PIXELS_PER_SAMPLING_WINDOW;
    backbuffer_windows[backbuffer_windows.count-1].count = PIXEL_COUNT - (backbuffer_windows.count - 1) * PIXELS_PER_SAMPLING_WINDOW;

    sum := 0;
    for sampling_windows {
        log_verbose("Window.count: %\n", it.count);
        sum += it.count;
    }
    log_verbose("Windows: %\nSum: %\nTot: %\n", sampling_windows.count, sum, PIXEL_COUNT);


    Thread_Synch :: struct {
          sampling_windows: [][]Vector3;
        backbuffer_windows: [][]u32;
        entities          : []Entity;

        start_semaphore : Semaphore;
         done_semaphore : Semaphore;

        copy_to_backbuffer := false;
        sample_count       := 0;
    }
    thread_synchs := Thread_Synch.{sampling_windows = sampling_windows, backbuffer_windows = backbuffer_windows};
    init(*thread_synchs.start_semaphore);
    init(*thread_synchs. done_semaphore);

    thread_proc :: (thread: *Thread) -> s64 {
        data := cast(*Thread_Synch)thread.data;

        while true {
            wait_for(*data.start_semaphore);

            current_window_index := thread.index - 1;
            while current_window_index < data.sampling_windows.count {
                defer current_window_index += THREAD_COUNT;

                pixel_buffer := data.  sampling_windows[current_window_index];
                backbuffer   := data.backbuffer_windows[current_window_index];

                sample_window(current_window_index, pixel_buffer, data.entities);

                if data.copy_to_backbuffer {
                    copy_pixels(pixel_buffer, backbuffer, cast(float, data.sample_count));
                }
            }

            reset_temporary_storage();
            log_verbose("Thread done: %\n", thread.index);
            signal(*data.done_semaphore);
        }

        return 0;
    }

    threads: [THREAD_COUNT]Thread;
    for *threads {
        it.data = *thread_synchs;
        thread_init(it, thread_proc);
        thread_start(it);
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
    thread_synchs.entities = entities;

    light_dir :: #run normalize(Vector3.{0.3, 1, -0.7});

    #if TIME {
       last_t      := current_time_monotonic();
       current_t   := last_t;
       min_frame_t : float64 = 2000.0;
       dt_acc      : float64;
       frame_count := 0;
       FRAME_AVERAGE_AMOUNT :: 10;
       INV_FRAME_AVERAGE    :: cast(float64)1.0 / FRAME_AVERAGE_AMOUNT;
    }

    NUMBER_OF_SAMPLES_BETWEEN_RENDERS :: 2;
    frame_display_countdown := 1;

    quit := false;
    while !quit {
        defer reset_temporary_storage();

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

        frame_display_countdown -= 1;

        {
            thread_synchs.sample_count      += 1;
            thread_synchs.copy_to_backbuffer = frame_display_countdown == 0;
            sfence();

            for 0..THREAD_COUNT-1 {
                signal(*thread_synchs.start_semaphore);
            }

            log_verbose("All threads have started...");

            for 0..THREAD_COUNT-1 {
                wait_for(*thread_synchs.done_semaphore);
            }

            log_verbose("All threads are done!");
        }

        if frame_display_countdown == 0 {
            frame_display_countdown = NUMBER_OF_SAMPLES_BETWEEN_RENDERS;

            StretchDIBits(window_dc, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
                                     0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
                          backbuffer.data, *backbuffer_info, DIB_RGB_COLORS, .SRCCOPY);
        }

        #if TIME {
            frame_count += 1;

            current_t = current_time_monotonic();

            frame_t := to_float64_seconds(current_t - last_t);
            if frame_t < min_frame_t then min_frame_t = frame_t;
            dt_acc   += frame_t;
            last_t    = current_t;

            if frame_count >= FRAME_AVERAGE_AMOUNT {
                frame_count = 0;
                dt_acc *= INV_FRAME_AVERAGE;
                log("Average frame time: %;  FPS: %;   Min frame time: %\n", dt_acc, 1.0 / cast(float)dt_acc, min_frame_t);
                dt_acc = 0;
            }
        }
    }
}

sample_window :: (window_index: int, window: []Vector3, entities: []Entity) {
    window_start_x := PIXELS_PER_SAMPLING_WINDOW * window_index;
    window_start_y := window_start_x / WINDOW_WIDTH;
    window_start_x -= window_start_y * WINDOW_WIDTH;

    //log("Sampling % out of %\n", window_index, sampling_windows.count);
    sample_pixels(window_start_x, window_start_y, window, entities);
}

sample_pixels :: (start_x: int, start_y: int, pixel_buffer : []Vector3, entities : []Entity) {
    x, y := cast(u32, start_x), cast(u32, start_y);
    for *interm_pixel: pixel_buffer {

        defer { x += 1; if x == WINDOW_WIDTH { y += 1; x  = 0; } }

        fx := cast(float, x);
        fy := cast(float, y);

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

        CAMERA_ZOOM : float : 0.5;
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

            // if hit_material.transmissive {
            //     ray.origin = ;
            //     continue;
            // }

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
}

copy_pixels :: (source_buffer: []Vector3, dest_buffer: []u32, samples_so_far: float) {
    #if SIMD {
        pixel_index := 0;

        while pixel_index < dest_buffer.count-1 {
            defer pixel_index += 2;

             src_pixel := source_buffer.data + pixel_index;
            dest_pixel :=   dest_buffer.data + pixel_index;

            denoms : [8]float = ---;
            denoms[0] = 1.0 / samples_so_far;
            denoms[1] = denoms[0];
            denoms[2] = denoms[0];
            denoms[3] = denoms[0];
            denoms[4] = denoms[0];
            denoms[5] = denoms[0];
            denoms[6] = denoms[0];
            denoms[7] = denoms[0];
            denoms_data := denoms.data;

            #asm AVX, AVX2 {
                // @speed: Could use movaps here, if we pad the RGB values into a Vector4...
                movups.256 packed_denom     :, [denoms_data];
                movups.256 packed_src_pixels:, [src_pixel];

                mulps.256 packed_src_pixels, packed_src_pixels, packed_denom;
            }

            denoms[0], denoms[1], denoms[2], denoms[3], denoms[4], denoms[5], denoms[6], denoms[7] = 512.0;

            u8_masks : [8]u32 = ---;
            u8_masks[0], u8_masks[1], u8_masks[2], u8_masks[3], u8_masks[4], u8_masks[5], u8_masks[6], u8_masks[7] = 0xFF;
            u8_masks_data := u8_masks.data;

            results: [8]u32 = ---;
            results_data := results.data;
            #asm AVX, AVX2 {
                movups.256 packed_denom, [denoms_data];

                mulps.256 packed_src_pixels, packed_src_pixels, packed_denom;
                cvtps2dq.256 packed_int_pixels:, packed_src_pixels; // convert floats to s32's

                pand.256   packed_int_pixels, packed_int_pixels, [u8_masks_data];

                movups.256 [results_data], packed_int_pixels;
            }

            dest_pixel[0] = (results[2] << 0) | (results[3] << 8) | (results[4] << 16);
            dest_pixel[1] = (results[5] << 0) | (results[6] << 8) | (results[7] << 16);
        }
    } else {
        src_pixel := source_buffer.data;
        denom := 1.0 / samples_so_far;
        for *dest_pixel: dest_buffer {
            defer src_pixel += 1;

            linear_to_srgb :: (l: float) -> float #expand {
                return l;
                if l < 0 return 0;
                if l > 1 return 1;

                s := l * 12.92;
                if l > 0.0031308 then s = 1.055 * pow(l, 1 / 2.4) - 0.055;

                return s;
            }

            srgb_pixel : Vector3 = ---;

            srgb_pixel.x = linear_to_srgb(src_pixel.x * denom);
            srgb_pixel.y = linear_to_srgb(src_pixel.y * denom);
            srgb_pixel.z = linear_to_srgb(src_pixel.z * denom);

            r : u32 = cast(u8) (255 * srgb_pixel.x);
            g : u32 = cast(u8) (255 * srgb_pixel.y);
            b : u32 = cast(u8) (255 * srgb_pixel.z);

            pixel_value : u32 = 0xFF000000 | (r << 16) | (g << 8) | b; 
            #if USE_NONTEMPORAL_STORE {
                #asm {
                    movnt.32 [dest_pixel], pixel_value;
                }
            } else {
                dest_pixel.* = pixel_value;
            }
        }
    }
}

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

#import "Basic";
#import "Windows";
#import "Window_Creation";
#import "Input";
#import "Math";
#import "Sloppy_Math";
#import "Random";
#import "Thread";
#import "Machine_X64";
#import "Print_Vars";

WINDOW_WIDTH  :: 640 * SCALE;
WINDOW_HEIGHT :: 360 * SCALE;
the_window: Window_Type;

#scope_file
// missing stuff from windows module
gdi :: #system_library "Gdi32";
StretchDIBits :: (hdc: HDC, xDest: int, yDest: int, DestWidth: int, DestHeight: int,
                            xSrc:  int, ySrc:  int, SrcWidth:  int, SrcHeight:  int,
                  lpBits: *void, lpbmi: *BITMAPINFO, iUsage: u32, rop: ROP) -> s32 #foreign gdi;


