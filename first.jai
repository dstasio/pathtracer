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

    Sphere :: struct {
        center: Vector3;
        radius: float = 50;
    };

    Ray :: struct {
        origin: Vector3;
        dir   : Vector3;
    };

    sphere : Sphere;

    ray_to_sphere :: (r: Ray, s: Sphere) -> hit: bool, p: Vector3 = .{}, n: Vector3 = .{} {
        assert(!is_approximately_zero(length_squared(r.dir)));

        co := r.origin - s.center;

        b := dot(r.dir, co);
        discriminant := b*b - (length_squared(co) - (s.radius * s.radius));

	if discriminant < 0 {
            return false;
	}

        d0 := -b;
        if !is_approximately_zero(discriminant) {
            discriminant = sqrt(discriminant);
            d0 -= discriminant;
            //d1 := -b + discriminant;
        }

        p0 := r.origin + r.dir * d0;
        normal := p0 - s.center;
        normalize(*normal);

        return true, p0, normal;
    }

    camera_pos  : Vector3;
    CAMERA_SIZE : float : 100;

    #if TIME {
       last_t := current_time_monotonic();
    current_t := last_t;
    dt_acc    : float64;
    frame_count := 0;
    FRAME_AVERAGE_AMOUNT :: 50;
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

        for *pixel: backbuffer  pixel.* = 0xcdcdcd;

        // ===========

        x : u32;
        y : u32;
        for *pixel: backbuffer {
            defer { x += 1; if x == WINDOW_WIDTH { y += 1; x  = 0; } }

            fx := cast(float)x;
            fy := cast(float)y;

            fx -= 0.5*WINDOW_WIDTH;
            fy -= 0.5*WINDOW_HEIGHT;

            fx *= CAMERA_SIZE / WINDOW_HEIGHT;
            fy *= CAMERA_SIZE / WINDOW_HEIGHT;

            LOOK_DIR :: Vector3.{1, 0, 0};
            look := Ray.{
                origin = .{0, fx, fy},
                dir    = LOOK_DIR,
            };

            hit, hitp, hitn := ray_to_sphere(look, sphere);
            if hit {
                r : u32 = cast(u8) (255 * (hitn.x + 1) * 0.5);
                g : u32 = cast(u8) (255 * (hitn.y + 1) * 0.5);
                b : u32 = cast(u8) (255 * (hitn.z + 1) * 0.5);

                pixel.* = 0xFF000000 | (r << 16) | (g << 8) | b;
            }
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

WINDOW_WIDTH  :: 1280;
WINDOW_HEIGHT :: 720;
the_window: Window_Type;

#scope_file
// missing stuff from windows module
gdi :: #system_library "Gdi32";
StretchDIBits :: (hdc: HDC, xDest: int, yDest: int, DestWidth: int, DestHeight: int,
                            xSrc:  int, ySrc:  int, SrcWidth:  int, SrcHeight:  int,
                  lpBits: *void, lpbmi: *BITMAPINFO, iUsage: u32, rop: ROP) -> s32 #foreign gdi;

#run {
    #import "Compiler";
    set_build_options_dc(.{output_executable_name = "pathtracer", output_path = "build"});
}
