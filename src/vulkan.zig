const std = @import("std");
const c = @import("c.zig");
const print = std.debug.print;

pub const Context = struct {
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    graphics_family: u32,
    present_family: u32,

    pub fn init(window: *c.SDL_Window) !Context {
        // Instance extensions required by SDL.
        var extension_count: u32 = 0;
        const extensions = c.SDL_Vulkan_GetInstanceExtensions(&extension_count);

        if (extensions == null) {
            print("SDL Vulkan extensions failed: {s}\n", .{c.SDL_GetError()});
            return error.SDLExtensionsUnavailable;
        }

        // Check validation layer.
        const validation_layers = [_][*:0]const u8{
            "VK_LAYER_KHRONOS_validation",
        };

        var layer_count: u32 = 0;
        if (c.vkEnumerateInstanceLayerProperties(&layer_count, null) != c.VK_SUCCESS) {
            return error.LayerEnumerationFailed;
        }

        const layers = try std.heap.page_allocator.alloc(c.VkLayerProperties, layer_count);
        defer std.heap.page_allocator.free(layers);

        if (c.vkEnumerateInstanceLayerProperties(&layer_count, layers.ptr) != c.VK_SUCCESS) {
            return error.LayerEnumerationFailed;
        }

        var validation_found = false;
        for (layers) |layer| {
            const name = std.mem.sliceTo(&layer.layerName, 0);
            if (std.mem.eql(u8, name, "VK_LAYER_KHRONOS_validation")) {
                validation_found = true;
                break;
            }
        }

        if (!validation_found) return error.ValidationLayerNotFound;

        // Application information.
        const app_info: c.VkApplicationInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "Zag Engine",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "Zag Engine",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_0,
        };

        const instance_info: c.VkInstanceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 1,
            .ppEnabledLayerNames = @ptrCast(&validation_layers),
            .enabledExtensionCount = extension_count,
            .ppEnabledExtensionNames = extensions,
        };

        var instance: c.VkInstance = undefined;

        if (c.vkCreateInstance(&instance_info, null, &instance) != c.VK_SUCCESS) {
            return error.InstanceCreationFailed;
        }
        errdefer c.vkDestroyInstance(instance, null);

        print("Vulkan instance created.\n", .{});

        // SDL surface.
        var surface: c.VkSurfaceKHR = undefined;

        if (!c.SDL_Vulkan_CreateSurface(window, instance, null, &surface)) {
            print("Surface creation failed: {s}\n", .{c.SDL_GetError()});
            return error.SurfaceCreationFailed;
        }
        errdefer c.SDL_Vulkan_DestroySurface(instance, surface, null);

        print("Vulkan surface created.\n", .{});

        // Enumerate physical devices.
        var device_count: u32 = 0;

        if (c.vkEnumeratePhysicalDevices(instance, &device_count, null) != c.VK_SUCCESS or device_count == 0) {
            return error.NoVulkanDevices;
        }

        const physical_devices = try std.heap.page_allocator.alloc(c.VkPhysicalDevice, device_count);
        defer std.heap.page_allocator.free(physical_devices);

        if (c.vkEnumeratePhysicalDevices(instance, &device_count, physical_devices.ptr) != c.VK_SUCCESS) {
            return error.DeviceEnumerationFailed;
        }

        var selected_device: ?c.VkPhysicalDevice = null;
        var graphics_family: u32 = 0;
        var present_family: u32 = 0;

        // Find a device with graphics and presentation support.
        for (physical_devices) |physical_device| {
            var queue_count: u32 = 0;

            c.vkGetPhysicalDeviceQueueFamilyProperties(
                physical_device,
                &queue_count,
                null,
            );

            const queue_properties = try std.heap.page_allocator.alloc(
                c.VkQueueFamilyProperties,
                queue_count,
            );
            defer std.heap.page_allocator.free(queue_properties);

            c.vkGetPhysicalDeviceQueueFamilyProperties(
                physical_device,
                &queue_count,
                queue_properties.ptr,
            );

            var found_graphics: ?u32 = null;
            var found_present: ?u32 = null;

            for (queue_properties, 0..) |properties, index| {
                const family: u32 = @intCast(index);

                if ((properties.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
                    found_graphics = family;
                }

                var supports_present: c.VkBool32 = c.VK_FALSE;

                if (c.vkGetPhysicalDeviceSurfaceSupportKHR(
                    physical_device,
                    family,
                    surface,
                    &supports_present,
                ) == c.VK_SUCCESS and supports_present == c.VK_TRUE) {
                    found_present = family;
                }
            }

            if (found_graphics != null and found_present != null) {
                selected_device = physical_device;
                graphics_family = found_graphics.?;
                present_family = found_present.?;
                break;
            }
        }

        const physical_device = selected_device orelse return error.NoSuitableGPU;

        // Print selected GPU.
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(physical_device, &properties);

        const gpu_name = std.mem.sliceTo(&properties.deviceName, 0);
        print("Selected GPU: {s}\n", .{gpu_name});

        // Logical device queues.
        const priority: f32 = 1.0;

        var queue_infos: [2]c.VkDeviceQueueCreateInfo = undefined;

        queue_infos[0] = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = graphics_family,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        };

        var queue_info_count: u32 = 1;

        if (graphics_family != present_family) {
            queue_infos[1] = .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = present_family,
                .queueCount = 1,
                .pQueuePriorities = &priority,
            };
            queue_info_count = 2;
        }

        const device_extensions = [_][*:0]const u8{
            "VK_KHR_swapchain",
        };

        const device_info: c.VkDeviceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = queue_info_count,
            .pQueueCreateInfos = &queue_infos,
            .enabledExtensionCount = 1,
            .ppEnabledExtensionNames = @ptrCast(&device_extensions),
        };

        var device: c.VkDevice = undefined;

        if (c.vkCreateDevice(physical_device, &device_info, null, &device) != c.VK_SUCCESS) {
            return error.LogicalDeviceCreationFailed;
        }
        errdefer c.vkDestroyDevice(device, null);

        var graphics_queue: c.VkQueue = undefined;
        var present_queue: c.VkQueue = undefined;

        c.vkGetDeviceQueue(device, graphics_family, 0, &graphics_queue);
        c.vkGetDeviceQueue(device, present_family, 0, &present_queue);

        print("Logical device created.\n", .{});
        print("Graphics and presentation queues acquired.\n", .{});

        return .{
            .instance = instance,
            .surface = surface,
            .physical_device = physical_device,
            .device = device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .graphics_family = graphics_family,
            .present_family = present_family,
        };
    }

    pub fn deinit(self: *Context) void {
        _ = c.vkDeviceWaitIdle(self.device);
        c.vkDestroyDevice(self.device, null);
        c.SDL_Vulkan_DestroySurface(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
