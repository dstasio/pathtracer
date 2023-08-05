
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

       last_t := current_time_monotonic();
    current_t := last_t;
    dt_acc    : float64;
    frame_count := 0;
    FRAME_AVERAGE_AMOUNT :: 200;
    INV_FRAME_AVERAGE :: cast(float64)1.0 / FRAME_AVERAGE_AMOUNT;

    offs : u32;
    offs_delta := 1;
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

        x : u32;
        y : u32;
        for *pixel: backbuffer {
            mx : u32 = x % 50 + offs;
            my : u32 = y % 50 + offs;

            pixel.* = xx (mx << 8 | my);

            x += 1;
            if x == WINDOW_WIDTH {
                y += 1;
                x  = 0;
            }
        }
        offs = xx (offs + offs_delta);


        StretchDIBits(window_dc, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
                                 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
                      backbuffer.data, *backbuffer_info, DIB_RGB_COLORS, .SRCCOPY);

        frame_count += 1;

        current_t = current_time_monotonic();
        dt_acc   += to_float64_seconds(current_t - last_t);
        last_t    = current_t;

        if frame_count >= FRAME_AVERAGE_AMOUNT {
            offs_delta *= -1;
            frame_count = 0;
            dt_acc *= INV_FRAME_AVERAGE;
            print("Average frame time: %;  FPS: %\n", dt_acc, 1.0 / cast(float)dt_acc);
            dt_acc = 0;
        }
    }
}

#import "Basic";
#import "Windows";
#import "Window_Creation";
#import "Input";

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
