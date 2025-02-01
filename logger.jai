VERBOSE_LOGGING :: false;

my_logger :: (message: string, data: *void, info: Log_Info) {
    if !message then return;

    to_standard_error := (info.common_flags & .ERROR) != 0;

    log_color := Console_Color.WHITE;

    if info.common_flags & .ERROR {
        log_color = .RED;
    } else if info.common_flags & .WARNING {
        log_color = .YELLOW;
    } else if info.common_flags & .VERBOSE_ONLY == 0 {
        log_color = .CYAN;
    }

    log_code :: #code {
        if message[message.count-1] != #char "\n" {
            write_strings(message, "\n", to_standard_error = to_standard_error);
        } else {
            write_string(message, to_standard_error = to_standard_error);
        }
    }

    with_console_color(log_color, log_code, to_standard_error = to_standard_error);
}

log_verbose :: inline (format_string: string, args: .. Any, loc := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0, section : *Log_Section = null) {
    #if VERBOSE_LOGGING {
        new_flags := flags | .VERBOSE_ONLY;
        log(format_string, ..args, loc, new_flags, user_flags, section);
    }
} @PrintLike

#import "Print_Color";
