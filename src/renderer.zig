const std = @import("std");
const c = @import("c.zig");
const vk = @import("vulkan.zig");

const frames_in_flight = 2;

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    context: *vk.Context,
    window: *c.SDL_Window,

    swapchain: c.VkSwapchainKHR = null,
    images: []c.VkImage = &.{},
    image_views: []c.VkImageView = &.{},
    framebuffers: []c.VkFramebuffer = &.{},

    surface_format: c.VkFormat = c.VK_FORMAT_UNDEFINED,
    extent: c.VkExtent2D = .{ .width = 0, .height = 0 },

    render_pass: c.VkRenderPass = null,
    pipeline_layout: c.VkPipelineLayout = null,
    pipeline: c.VkPipeline = null,

    command_pool: c.VkCommandPool = null,
    command_buffers: []c.VkCommandBuffer = &.{},

    // Per-frame synchronisation.
    image_available: [frames_in_flight]c.VkSemaphore = .{ null, null },
    in_flight: [frames_in_flight]c.VkFence = .{ null, null },

    // Per-swapchain-image synchronisation.
    // Presentation semaphores must not be reused until their
    // associated swapchain image has been acquired again.
    render_finished: []c.VkSemaphore = &.{},

    // Tracks which frame fence currently owns each swapchain image.
    images_in_flight: []c.VkFence = &.{},

    current_frame: usize = 0,

    pub fn init(
        window: *c.SDL_Window,
        context: *vk.Context,
    ) !Renderer {
        var self: Renderer = .{
            .allocator = std.heap.page_allocator,
            .context = context,
            .window = window,
        };

        errdefer self.deinit();

        try self.createCommandPool();
        try self.createSyncObjects();
        try self.createSwapchainResources();

        return self;
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.context.device);

        self.destroySwapchainResources();

        if (self.command_pool != null) {
            c.vkDestroyCommandPool(
                self.context.device,
                self.command_pool,
                null,
            );
            self.command_pool = null;
        }

        for (0..frames_in_flight) |i| {
            if (self.image_available[i] != null) {
                c.vkDestroySemaphore(
                    self.context.device,
                    self.image_available[i],
                    null,
                );
                self.image_available[i] = null;
            }

            if (self.in_flight[i] != null) {
                c.vkDestroyFence(
                    self.context.device,
                    self.in_flight[i],
                    null,
                );
                self.in_flight[i] = null;
            }
        }
    }

    // --------------------------------------------------
    // Command pool
    // --------------------------------------------------

    fn createCommandPool(self: *Renderer) !void {
        const info: c.VkCommandPoolCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = self.context.graphics_family,
        };

        if (c.vkCreateCommandPool(
            self.context.device,
            &info,
            null,
            &self.command_pool,
        ) != c.VK_SUCCESS) {
            return error.CommandPoolCreationFailed;
        }
    }

    // --------------------------------------------------
    // Per-frame synchronisation
    // --------------------------------------------------

    fn createSyncObjects(self: *Renderer) !void {
        const semaphore_info: c.VkSemaphoreCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const fence_info: c.VkFenceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (0..frames_in_flight) |i| {
            if (c.vkCreateSemaphore(
                self.context.device,
                &semaphore_info,
                null,
                &self.image_available[i],
            ) != c.VK_SUCCESS) {
                return error.SemaphoreCreationFailed;
            }

            if (c.vkCreateFence(
                self.context.device,
                &fence_info,
                null,
                &self.in_flight[i],
            ) != c.VK_SUCCESS) {
                return error.FenceCreationFailed;
            }
        }
    }

    // --------------------------------------------------
    // Swapchain resources
    // --------------------------------------------------

    fn createSwapchainResources(self: *Renderer) !void {
        try self.createSwapchain();
        errdefer self.destroySwapchainResources();

        try self.createRenderFinishedSemaphores();
        try self.createImagesInFlight();

        try self.createImageViews();
        try self.createRenderPass();
        try self.createGraphicsPipeline();
        try self.createFramebuffers();
        try self.createCommandBuffers();
    }

    // One render-finished semaphore per swapchain image.
    fn createRenderFinishedSemaphores(self: *Renderer) !void {
        self.render_finished = try self.allocator.alloc(
            c.VkSemaphore,
            self.images.len,
        );

        @memset(self.render_finished, null);

        const info: c.VkSemaphoreCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        for (self.render_finished) |*semaphore| {
            if (c.vkCreateSemaphore(
                self.context.device,
                &info,
                null,
                semaphore,
            ) != c.VK_SUCCESS) {
                return error.SemaphoreCreationFailed;
            }
        }
    }

    // Each swapchain image starts with no associated fence.
    fn createImagesInFlight(self: *Renderer) !void {
        self.images_in_flight = try self.allocator.alloc(
            c.VkFence,
            self.images.len,
        );

        @memset(self.images_in_flight, null);
    }

    fn createSwapchain(self: *Renderer) !void {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;

        if (c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            self.context.physical_device,
            self.context.surface,
            &capabilities,
        ) != c.VK_SUCCESS) {
            return error.SurfaceCapabilitiesFailed;
        }

        var format_count: u32 = 0;

        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(
            self.context.physical_device,
            self.context.surface,
            &format_count,
            null,
        );

        if (format_count == 0) return error.NoSurfaceFormats;

        const formats = try self.allocator.alloc(
            c.VkSurfaceFormatKHR,
            format_count,
        );
        defer self.allocator.free(formats);

        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(
            self.context.physical_device,
            self.context.surface,
            &format_count,
            formats.ptr,
        );

        var selected_format = formats[0];

        for (formats) |format| {
            if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
                format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            {
                selected_format = format;
                break;
            }
        }

        self.surface_format = selected_format.format;

        // Prefer the surface's current extent.
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            self.extent = capabilities.currentExtent;
        } else {
            var width: c_int = 0;
            var height: c_int = 0;

            if (!c.SDL_GetWindowSizeInPixels(
                self.window,
                &width,
                &height,
            )) {
                return error.WindowSizeFailed;
            }

            if (width <= 0 or height <= 0) {
                return error.WindowMinimized;
            }

            self.extent = .{
                .width = @max(
                    capabilities.minImageExtent.width,
                    @min(
                        @as(u32, @intCast(width)),
                        capabilities.maxImageExtent.width,
                    ),
                ),
                .height = @max(
                    capabilities.minImageExtent.height,
                    @min(
                        @as(u32, @intCast(height)),
                        capabilities.maxImageExtent.height,
                    ),
                ),
            };
        }

        var image_count = capabilities.minImageCount + 1;

        if (capabilities.maxImageCount > 0 and
            image_count > capabilities.maxImageCount)
        {
            image_count = capabilities.maxImageCount;
        }

        const queue_families = [_]u32{
            self.context.graphics_family,
            self.context.present_family,
        };

        var info: c.VkSwapchainCreateInfoKHR = .{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = self.context.surface,
            .minImageCount = image_count,
            .imageFormat = selected_format.format,
            .imageColorSpace = selected_format.colorSpace,
            .imageExtent = self.extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .preTransform = capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = c.VK_PRESENT_MODE_FIFO_KHR,
            .clipped = c.VK_TRUE,
        };

        if (self.context.graphics_family != self.context.present_family) {
            info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
            info.queueFamilyIndexCount = 2;
            info.pQueueFamilyIndices = @ptrCast(&queue_families);
        } else {
            info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
            info.queueFamilyIndexCount = 0;
            info.pQueueFamilyIndices = null;
        }

        if (c.vkCreateSwapchainKHR(
            self.context.device,
            &info,
            null,
            &self.swapchain,
        ) != c.VK_SUCCESS) {
            return error.SwapchainCreationFailed;
        }

        var actual_count: u32 = 0;

        _ = c.vkGetSwapchainImagesKHR(
            self.context.device,
            self.swapchain,
            &actual_count,
            null,
        );

        self.images = try self.allocator.alloc(
            c.VkImage,
            actual_count,
        );

        if (c.vkGetSwapchainImagesKHR(
            self.context.device,
            self.swapchain,
            &actual_count,
            self.images.ptr,
        ) != c.VK_SUCCESS) {
            return error.SwapchainImagesFailed;
        }
    }

    // --------------------------------------------------
    // Image views
    // --------------------------------------------------

    fn createImageViews(self: *Renderer) !void {
        self.image_views = try self.allocator.alloc(
            c.VkImageView,
            self.images.len,
        );

        @memset(self.image_views, null);

        for (self.images, 0..) |image, i| {
            const info: c.VkImageViewCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.surface_format,
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            if (c.vkCreateImageView(
                self.context.device,
                &info,
                null,
                &self.image_views[i],
            ) != c.VK_SUCCESS) {
                return error.ImageViewCreationFailed;
            }
        }
    }

    // --------------------------------------------------
    // Render pass
    // --------------------------------------------------

    fn createRenderPass(self: *Renderer) !void {
        const attachment: c.VkAttachmentDescription = .{
            .format = self.surface_format,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const attachment_ref: c.VkAttachmentReference = .{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const subpass: c.VkSubpassDescription = .{
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments = &attachment_ref,
        };

        const dependency: c.VkSubpassDependency = .{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        };

        const info: c.VkRenderPassCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = 1,
            .pAttachments = &attachment,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 1,
            .pDependencies = &dependency,
        };

        if (c.vkCreateRenderPass(
            self.context.device,
            &info,
            null,
            &self.render_pass,
        ) != c.VK_SUCCESS) {
            return error.RenderPassCreationFailed;
        }
    }

    // --------------------------------------------------
    // Graphics pipeline
    // --------------------------------------------------

    fn createGraphicsPipeline(self: *Renderer) !void {
        const vertex_bytes align(4) = @embedFile("triangle_vert").*;
        const fragment_bytes align(4) = @embedFile("triangle_frag").*;

        const vertex_words: [*]const u32 = @ptrCast(&vertex_bytes);
        const fragment_words: [*]const u32 = @ptrCast(&fragment_bytes);

        const vertex_module = try self.createShaderModule(
            vertex_words[0 .. vertex_bytes.len / @sizeOf(u32)],
        );
        defer c.vkDestroyShaderModule(
            self.context.device,
            vertex_module,
            null,
        );

        const fragment_module = try self.createShaderModule(
            fragment_words[0 .. fragment_bytes.len / @sizeOf(u32)],
        );
        defer c.vkDestroyShaderModule(
            self.context.device,
            fragment_module,
            null,
        );

        const stages = [_]c.VkPipelineShaderStageCreateInfo{
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                .module = vertex_module,
                .pName = "main",
            },
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .module = fragment_module,
                .pName = "main",
            },
        };

        const vertex_input: c.VkPipelineVertexInputStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        };

        const input_assembly: c.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const viewport_state: c.VkPipelineViewportStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
        };

        const rasterizer: c.VkPipelineRasterizationStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .cullMode = c.VK_CULL_MODE_NONE,
            .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .depthBiasEnable = c.VK_FALSE,
            .lineWidth = 1.0,
        };

        const multisampling: c.VkPipelineMultisampleStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .sampleShadingEnable = c.VK_FALSE,
        };

        const color_attachment: c.VkPipelineColorBlendAttachmentState = .{
            .blendEnable = c.VK_FALSE,
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT |
                c.VK_COLOR_COMPONENT_G_BIT |
                c.VK_COLOR_COMPONENT_B_BIT |
                c.VK_COLOR_COMPONENT_A_BIT,
        };

        const color_blending: c.VkPipelineColorBlendStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.VK_FALSE,
            .attachmentCount = 1,
            .pAttachments = &color_attachment,
        };

        const dynamic_states = [_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state: c.VkPipelineDynamicStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = 2,
            .pDynamicStates = @ptrCast(&dynamic_states),
        };

        const layout_info: c.VkPipelineLayoutCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        };

        if (c.vkCreatePipelineLayout(
            self.context.device,
            &layout_info,
            null,
            &self.pipeline_layout,
        ) != c.VK_SUCCESS) {
            return error.PipelineLayoutCreationFailed;
        }

        const pipeline_info: c.VkGraphicsPipelineCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount = 2,
            .pStages = &stages,
            .pVertexInputState = &vertex_input,
            .pInputAssemblyState = &input_assembly,
            .pViewportState = &viewport_state,
            .pRasterizationState = &rasterizer,
            .pMultisampleState = &multisampling,
            .pColorBlendState = &color_blending,
            .pDynamicState = &dynamic_state,
            .layout = self.pipeline_layout,
            .renderPass = self.render_pass,
            .subpass = 0,
            .basePipelineIndex = -1,
        };

        if (c.vkCreateGraphicsPipelines(
            self.context.device,
            null,
            1,
            &pipeline_info,
            null,
            &self.pipeline,
        ) != c.VK_SUCCESS) {
            return error.GraphicsPipelineCreationFailed;
        }
    }

    fn createShaderModule(
        self: *Renderer,
        code: []const u32,
    ) !c.VkShaderModule {
        const info: c.VkShaderModuleCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = code.len * @sizeOf(u32),
            .pCode = code.ptr,
        };

        var module: c.VkShaderModule = null;

        if (c.vkCreateShaderModule(
            self.context.device,
            &info,
            null,
            &module,
        ) != c.VK_SUCCESS) {
            return error.ShaderModuleCreationFailed;
        }

        return module;
    }

    // --------------------------------------------------
    // Framebuffers
    // --------------------------------------------------

    fn createFramebuffers(self: *Renderer) !void {
        self.framebuffers = try self.allocator.alloc(
            c.VkFramebuffer,
            self.image_views.len,
        );

        @memset(self.framebuffers, null);

        for (self.image_views, 0..) |image_view, i| {
            const attachments = [_]c.VkImageView{image_view};

            const info: c.VkFramebufferCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = self.render_pass,
                .attachmentCount = 1,
                .pAttachments = &attachments,
                .width = self.extent.width,
                .height = self.extent.height,
                .layers = 1,
            };

            if (c.vkCreateFramebuffer(
                self.context.device,
                &info,
                null,
                &self.framebuffers[i],
            ) != c.VK_SUCCESS) {
                return error.FramebufferCreationFailed;
            }
        }
    }

    // --------------------------------------------------
    // Command buffers
    // --------------------------------------------------

    fn createCommandBuffers(self: *Renderer) !void {
        self.command_buffers = try self.allocator.alloc(
            c.VkCommandBuffer,
            self.framebuffers.len,
        );

        const info: c.VkCommandBufferAllocateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = self.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(self.command_buffers.len),
        };

        if (c.vkAllocateCommandBuffers(
            self.context.device,
            &info,
            self.command_buffers.ptr,
        ) != c.VK_SUCCESS) {
            return error.CommandBufferAllocationFailed;
        }
    }

    fn recordCommandBuffer(
        self: *Renderer,
        command_buffer: c.VkCommandBuffer,
        image_index: u32,
    ) !void {
        const begin_info: c.VkCommandBufferBeginInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        };

        if (c.vkBeginCommandBuffer(
            command_buffer,
            &begin_info,
        ) != c.VK_SUCCESS) {
            return error.CommandBufferBeginFailed;
        }

        var clear_value: c.VkClearValue = std.mem.zeroes(c.VkClearValue);
        clear_value.color.float32[0] = 0.025;
        clear_value.color.float32[1] = 0.035;
        clear_value.color.float32[2] = 0.055;
        clear_value.color.float32[3] = 1.0;

        const render_info: c.VkRenderPassBeginInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = self.render_pass,
            .framebuffer = self.framebuffers[image_index],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.extent,
            },
            .clearValueCount = 1,
            .pClearValues = &clear_value,
        };

        c.vkCmdBeginRenderPass(
            command_buffer,
            &render_info,
            c.VK_SUBPASS_CONTENTS_INLINE,
        );

        c.vkCmdBindPipeline(
            command_buffer,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.pipeline,
        );

        const viewport: c.VkViewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.extent.width),
            .height = @floatFromInt(self.extent.height),
            .minDepth = 0,
            .maxDepth = 1,
        };

        const scissor: c.VkRect2D = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.extent,
        };

        c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);
        c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

        // Three vertices, generated by gl_VertexIndex.
        c.vkCmdDraw(command_buffer, 3, 1, 0, 0);

        c.vkCmdEndRenderPass(command_buffer);

        if (c.vkEndCommandBuffer(command_buffer) != c.VK_SUCCESS) {
            return error.CommandBufferEndFailed;
        }
    }

    // --------------------------------------------------
    // Frame rendering
    // --------------------------------------------------

    pub fn drawFrame(self: *Renderer) !void {
        const device = self.context.device;
        const frame = self.current_frame;

        // Wait until this frame slot's previous submission has finished.
        if (c.vkWaitForFences(
            device,
            1,
            &self.in_flight[frame],
            c.VK_TRUE,
            std.math.maxInt(u64),
        ) != c.VK_SUCCESS) {
            return error.FenceWaitFailed;
        }

        var image_index: u32 = 0;

        const acquire_result = c.vkAcquireNextImageKHR(
            device,
            self.swapchain,
            std.math.maxInt(u64),
            self.image_available[frame],
            null,
            &image_index,
        );

        if (acquire_result == c.VK_ERROR_OUT_OF_DATE_KHR) {
            return error.SwapchainOutOfDate;
        }

        if (acquire_result != c.VK_SUCCESS and
            acquire_result != c.VK_SUBOPTIMAL_KHR)
        {
            return error.ImageAcquisitionFailed;
        }

        // If this image was previously used by another frame,
        // wait until that frame has finished before reusing its command buffer.
        const previous_fence = self.images_in_flight[image_index];

        if (previous_fence != null) {
            if (c.vkWaitForFences(
                device,
                1,
                &self.images_in_flight[image_index],
                c.VK_TRUE,
                std.math.maxInt(u64),
            ) != c.VK_SUCCESS) {
                return error.FenceWaitFailed;
            }
        }

        if (c.vkResetCommandBuffer(
            self.command_buffers[image_index],
            0,
        ) != c.VK_SUCCESS) {
            return error.CommandBufferResetFailed;
        }

        try self.recordCommandBuffer(
            self.command_buffers[image_index],
            image_index,
        );

        if (c.vkResetFences(
            device,
            1,
            &self.in_flight[frame],
        ) != c.VK_SUCCESS) {
            return error.FenceResetFailed;
        }

        const wait_stages = [_]c.VkPipelineStageFlags{
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        };

        // The render-finished semaphore belongs to the acquired image,
        // not to the current frame slot.
        const render_semaphore = self.render_finished[image_index];

        const submit_info: c.VkSubmitInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.image_available[frame],
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffers[image_index],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &self.render_finished[image_index],
        };

        if (c.vkQueueSubmit(
            self.context.graphics_queue,
            1,
            &submit_info,
            self.in_flight[frame],
        ) != c.VK_SUCCESS) {
            return error.QueueSubmissionFailed;
        }

        // This image is now associated with this frame's fence.
        self.images_in_flight[image_index] = self.in_flight[frame];

        const present_info: c.VkPresentInfoKHR = .{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.render_finished[image_index],
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain,
            .pImageIndices = &image_index,
        };

        const present_result = c.vkQueuePresentKHR(
            self.context.present_queue,
            &present_info,
        );

        self.current_frame = (self.current_frame + 1) % frames_in_flight;

        if (present_result == c.VK_ERROR_OUT_OF_DATE_KHR or
            present_result == c.VK_SUBOPTIMAL_KHR or
            acquire_result == c.VK_SUBOPTIMAL_KHR)
        {
            return error.SwapchainOutOfDate;
        }

        if (present_result != c.VK_SUCCESS) {
            return error.PresentationFailed;
        }

        // Keep the local alive as a useful reminder of which semaphore
        // was signalled for this image.
        _ = render_semaphore;
    }

    // --------------------------------------------------
    // Swapchain recreation
    // --------------------------------------------------

    pub fn recreate(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.device);

        self.destroySwapchainResources();

        try self.createSwapchainResources();
    }

    // --------------------------------------------------
    // Cleanup
    // --------------------------------------------------

    fn destroySwapchainResources(self: *Renderer) void {
        const device = self.context.device;

        if (self.command_buffers.len > 0) {
            c.vkFreeCommandBuffers(
                device,
                self.command_pool,
                @intCast(self.command_buffers.len),
                self.command_buffers.ptr,
            );

            self.allocator.free(self.command_buffers);
            self.command_buffers = &.{};
        }

        for (self.framebuffers) |framebuffer| {
            if (framebuffer != null) {
                c.vkDestroyFramebuffer(device, framebuffer, null);
            }
        }

        if (self.framebuffers.len > 0) {
            self.allocator.free(self.framebuffers);
            self.framebuffers = &.{};
        }

        if (self.pipeline != null) {
            c.vkDestroyPipeline(device, self.pipeline, null);
            self.pipeline = null;
        }

        if (self.pipeline_layout != null) {
            c.vkDestroyPipelineLayout(
                device,
                self.pipeline_layout,
                null,
            );
            self.pipeline_layout = null;
        }

        if (self.render_pass != null) {
            c.vkDestroyRenderPass(
                device,
                self.render_pass,
                null,
            );
            self.render_pass = null;
        }

        for (self.image_views) |image_view| {
            if (image_view != null) {
                c.vkDestroyImageView(device, image_view, null);
            }
        }

        if (self.image_views.len > 0) {
            self.allocator.free(self.image_views);
            self.image_views = &.{};
        }

        // These semaphores are owned by the swapchain resources.
        for (self.render_finished) |semaphore| {
            if (semaphore != null) {
                c.vkDestroySemaphore(device, semaphore, null);
            }
        }

        if (self.render_finished.len > 0) {
            self.allocator.free(self.render_finished);
            self.render_finished = &.{};
        }

        // These are references to frame fences, not owned fences.
        if (self.images_in_flight.len > 0) {
            self.allocator.free(self.images_in_flight);
            self.images_in_flight = &.{};
        }

        if (self.images.len > 0) {
            self.allocator.free(self.images);
            self.images = &.{};
        }

        if (self.swapchain != null) {
            c.vkDestroySwapchainKHR(
                device,
                self.swapchain,
                null,
            );
            self.swapchain = null;
        }
    }
};
