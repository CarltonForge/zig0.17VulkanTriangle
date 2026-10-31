const std = @import("std");
const print = std.debug.print;

const c = @import("c.zig");
const vk = @import("vulkan.zig");
const renderer_mod = @import("renderer.zig");

pub fn main() !void {
    print("Starting Zag Engine...\n", .{});

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        print("SDL initialisation failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "Zag Engine",
        800,
        800,
        c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        print("Window creation failed: {s}\n", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    if (!c.SDL_ShowWindow(window)) {
        print("Window display failed: {s}\n", .{c.SDL_GetError()});
        return error.WindowDisplayFailed;
    }

    print("Window created.\n", .{});

    var context = try vk.Context.init(window);
    defer context.deinit();

    var renderer = try renderer_mod.Renderer.init(window, &context);
    defer renderer.deinit();

    print("Zag Engine renderer ready.\n", .{});

    var running = true;

    while (running) {
        var event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                running = false;
            }

            if (event.type == c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) {
                try renderer.recreate();
            }
        }

        if (!running) break;

        renderer.drawFrame() catch |err| {
            if (err == error.SwapchainOutOfDate) {
                try renderer.recreate();
            } else {
                return err;
            }
        };
    }
}
