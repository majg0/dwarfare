const std = @import("std");
const builtin = @import("builtin");
const xcb = @import("./xcb.zig");
const m = @import("./math.zig");
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("xcb/xcb.h");
    @cInclude("vulkan/vulkan_xcb.h");
});

// DOCS: https://docs.vulkan.org/spec/latest/index.html

// TODO: use standard buffer alignment instead
const Vertex = extern struct {
    pos: m.Vec2 align(vkBaseAlign(m.Vec2)),
    color: m.Vec3 align(vkBaseAlign(m.Vec3)),
    uv: m.Vec2 align(vkBaseAlign(m.Vec2)),
};

const UniformBufferObject = extern struct {
    model: m.Mat4,
    view: m.Mat4,
    proj: m.Mat4,
};

const Geometry = extern struct {
    vertices: [4]Vertex align(vkBaseAlign([4]Vertex)),
    indices: [6]u16 align(vkBaseAlign([6]u16)),
};

pub fn RgbaImage(comptime T: type, comptime width: comptime_int, comptime height: comptime_int) type {
    return extern struct {
        const size = width * height;
        pixels: [size]@Vector(4, T),
    };
}

const StagingData = extern struct {
    image: RgbaImage(u8, 2, 2),
    buffer: Geometry,
};

const RgbaU8 = @Vector(4, u8);
const black = RgbaU8{ 0, 0, 0, 255 };
const white = RgbaU8{ 255, 255, 255, 255 };

const staging_data = StagingData{
    .image = RgbaImage(u8, 2, 2){
        .pixels = .{
            black, white,
            white, black,
        },
    },
    .buffer = Geometry{
        .vertices = [_]Vertex{
            Vertex{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 0, 0 }, .uv = .{ 1, 0 } },
            Vertex{ .pos = .{ 0.5, -0.5 }, .color = .{ 0, 1, 0 }, .uv = .{ 0, 0 } },
            Vertex{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 0, 1 }, .uv = .{ 0, 1 } },
            Vertex{ .pos = .{ -0.5, 0.5 }, .color = .{ 1, 1, 1 }, .uv = .{ 1, 1 } },
        },
        .indices = [_]u16{
            0, 1, 2,
            2, 3, 0,
        },
    },
};

///////////////////////////

const int_invalid = 0xDEAD;

const instance_layer_enable = if (builtin.mode == std.builtin.Mode.Debug)
    [_][*c]const u8{
        "VK_LAYER_KHRONOS_validation",
    }
else
    [_][*c]const u8{};
const instance_extension_enable = [_][*c]const u8{
    c.VK_KHR_SURFACE_EXTENSION_NAME,
    if (builtin.os.tag == std.Target.Os.Tag.linux)
        c.VK_KHR_XCB_SURFACE_EXTENSION_NAME
    else
        @compileError("unsupported os"),
};
const device_extension_enable = [_][*c]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};
const dynamic_state: [2]c.VkDynamicState align(4) = .{
    c.VK_DYNAMIC_STATE_VIEWPORT,
    c.VK_DYNAMIC_STATE_SCISSOR,
};

const instance_extension_count_max = 64;
const instance_layer_count_max = 64;
const physical_device_count_max = 8;
const queue_family_count_max = 16;
const device_extension_count_max = 512;
const surface_format_count_max = 8;
const surface_present_mode_count_max = 8;
const swapchain_image_count_max = 4;
const shader_size_max = 2048;
const shader_count = 2;
const semaphore_count = 2;
const timeout_half_second = 500e6;
const fence_count = 1;
const command_pool_count = 2;
const command_pool_index_staging = 0;
const command_pool_index_swapchain = 1;
const buffer_count_max = 8;
const image_count_max = 1;
const device_memory_count = 2;
const device_memory_index_device_local = 0;
const device_memory_index_host_staging = 1;

fn initArray(comptime T: type, comptime size: usize, comptime value: T) [size]T {
    var array: [size]T = undefined;
    inline for (&array) |*elem| {
        elem.* = value;
    }
    return array;
}

// TODO: move somewhere else if reused
const Slice = struct {
    offset: usize,
    size: usize,
};

pub const Vulkan = struct {
    instance_version: u32 = int_invalid,
    instance_extension_count: u32 = instance_extension_count_max,
    instance_extension: [instance_extension_count_max]c.VkExtensionProperties = undefined,
    instance_layer_count: u32 = instance_layer_count_max,
    instance_layer: [instance_layer_count_max]c.VkLayerProperties = undefined,
    instance: c.VkInstance = null,
    physical_device_count: u32 = physical_device_count_max,
    physical_device: [physical_device_count_max]c.VkPhysicalDevice = initArray(
        c.VkPhysicalDevice,
        physical_device_count_max,
        null,
    ),
    physical_device_properties: [physical_device_count_max]c.VkPhysicalDeviceProperties = undefined,
    physical_device_features: [physical_device_count_max]c.VkPhysicalDeviceFeatures = undefined,
    physical_device_memory_properties: [physical_device_count_max]c.VkPhysicalDeviceMemoryProperties = undefined,
    physical_device_index_gpu: usize = int_invalid,
    queue_family_count: u32 = queue_family_count_max,
    queue_family: [queue_family_count_max]c.VkQueueFamilyProperties = undefined,
    queue_family_index_graphics: u32 = int_invalid,
    queue: c.VkQueue = null,
    device_extension_count: u32 = device_extension_count_max,
    device_extension: [device_extension_count_max]c.VkExtensionProperties = undefined,
    device: c.VkDevice = null,
    queue_index_graphics: u32 = 0,
    surface: c.VkSurfaceKHR = null,
    surface_capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    surface_format_count: u32 = surface_format_count_max,
    surface_format: [surface_format_count_max]c.VkSurfaceFormatKHR = undefined,
    surface_format_index_bgra_srgb: usize = int_invalid,
    surface_present_mode_count: u32 = surface_format_count_max,
    surface_present_mode: [surface_present_mode_count_max]c.VkPresentModeKHR = initArray(
        c.VkPresentModeKHR,
        surface_present_mode_count_max,
        c.VK_PRESENT_MODE_MAX_ENUM_KHR,
    ),
    surface_present_mode_index_vsync: usize = int_invalid,
    swapchain: c.VkSwapchainKHR = null,
    swapchain_image_count: u32 = swapchain_image_count_max,
    swapchain_image: [swapchain_image_count_max]c.VkImage = initArray(
        c.VkImage,
        swapchain_image_count_max,
        null,
    ),
    swapchain_image_view: [swapchain_image_count_max]c.VkImageView = initArray(
        c.VkImageView,
        swapchain_image_count_max,
        null,
    ),
    shader_name: [shader_count][]const u8 = .{
        "shaders/shader.vert.spv",
        "shaders/shader.frag.spv",
    },
    shader_size: [shader_count]usize = initArray(usize, shader_count, shader_size_max),
    shader_module: [shader_count]c.VkShaderModule = initArray(
        c.VkShaderModule,
        shader_count,
        null,
    ),
    shader_code: [shader_count][shader_size_max]u8 align(4) = initArray(
        [shader_size_max]u8,
        shader_count,
        undefined,
    ),
    shader_index_vert: usize = 0,
    shader_index_frag: usize = 1,
    descriptor_set_layout: c.VkDescriptorSetLayout = null,
    pipeline_layout: c.VkPipelineLayout = null,
    render_pass: c.VkRenderPass = null,
    pipeline_graphics: c.VkPipeline = null,
    framebuffer: [swapchain_image_count_max]c.VkFramebuffer = initArray(
        c.VkFramebuffer,
        swapchain_image_count_max,
        null,
    ),
    command_pool: [command_pool_count]c.VkCommandPool = initArray(
        c.VkCommandPool,
        command_pool_count,
        null,
    ),
    command_buffer: [swapchain_image_count_max]c.VkCommandBuffer = initArray(
        c.VkCommandBuffer,
        swapchain_image_count_max,
        null,
    ),
    semaphore: [swapchain_image_count_max][semaphore_count]c.VkSemaphore = initArray(
        [semaphore_count]c.VkSemaphore,
        swapchain_image_count_max,
        initArray(c.VkSemaphore, semaphore_count, null),
    ),
    semaphore_index_surface_image_acquired: usize = 0,
    semaphore_index_render_finished: usize = 1,
    fence: [swapchain_image_count_max][fence_count]c.VkFence = initArray(
        [fence_count]c.VkFence,
        swapchain_image_count_max,
        initArray(c.VkFence, fence_count, null),
    ),
    fence_index_queue_submitted: u32 = 0,
    swapchain_frame_index_draw: usize = 0,
    sampler: c.VkSampler = null,
    image_count: usize = 0,
    image: [image_count_max]c.VkImage = initArray(
        c.VkImage,
        image_count_max,
        null,
    ),
    image_view: [image_count_max]c.VkImageView = initArray(
        c.VkImageView,
        image_count_max,
        null,
    ),
    image_mapping: [image_count_max]Slice = initArray(
        Slice,
        image_count_max,
        Slice{ .offset = 0, .size = 0 },
    ),
    image_index_checkerboard: usize = 0,
    image_memory_requirements: [image_count_max]c.VkMemoryRequirements = undefined,
    buffer_count: usize = 0,
    buffer: [buffer_count_max]c.VkBuffer = initArray(
        c.VkBuffer,
        buffer_count_max,
        null,
    ),
    buffer_mapping: [buffer_count_max]Slice = initArray(
        Slice,
        buffer_count_max,
        Slice{ .offset = 0, .size = 0 },
    ),
    buffer_index_device: usize = 0,
    buffer_index_staging: usize = 0,
    buffer_index_uniform: Slice = Slice{ .offset = 0, .size = 0 },
    buffer_memory_requirements: [buffer_count_max]c.VkMemoryRequirements = undefined,
    device_memory: [device_memory_count]c.VkDeviceMemory = initArray(
        c.VkDeviceMemory,
        device_memory_count,
        null,
    ),
    device_memory_image_index: [device_memory_count]Slice = initArray(
        Slice,
        device_memory_count,
        Slice{ .offset = 0, .size = 0 },
    ),
    device_memory_buffer_index: [device_memory_count]Slice = initArray(
        Slice,
        device_memory_count,
        Slice{ .offset = 0, .size = 0 },
    ),
    mapped_memory_ubo: [swapchain_image_count_max]?*anyopaque = initArray(
        ?*anyopaque,
        swapchain_image_count_max,
        null,
    ),
    descriptor_pool: c.VkDescriptorPool = null,
    descriptor_set: [swapchain_image_count_max]c.VkDescriptorSet = initArray(
        c.VkDescriptorSet,
        swapchain_image_count_max,
        null,
    ),

    pub fn kill(self: Vulkan) void {
        _ = c.vkDeviceWaitIdle(self.device);
        self.swapchainKill();
        c.vkDestroySampler(self.device, self.sampler, null);
        for (0..self.image_count) |index| {
            c.vkDestroyImageView(self.device, self.image_view[index], null);
            c.vkDestroyImage(self.device, self.image[index], null);
        }
        for (0..self.buffer_count) |index| {
            c.vkDestroyBuffer(self.device, self.buffer[index], null);
        }
        for (0..device_memory_count) |index| {
            c.vkFreeMemory(self.device, self.device_memory[index], null);
        }
        c.vkDestroyDescriptorPool(self.device, self.descriptor_pool, null);
        c.vkDestroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
        for (0..self.swapchain_image_count) |swapchain_image_index| {
            for (0..fence_count) |index| {
                c.vkDestroyFence(self.device, self.fence[swapchain_image_index][index], null);
            }
            for (0..semaphore_count) |index| {
                c.vkDestroySemaphore(self.device, self.semaphore[swapchain_image_index][index], null);
            }
        }
        for (0..command_pool_count) |index| {
            c.vkDestroyCommandPool(self.device, self.command_pool[index], null);
        }
        c.vkDestroyPipeline(self.device, self.pipeline_graphics, null);
        c.vkDestroyRenderPass(self.device, self.render_pass, null);
        c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
        for (self.shader_module) |shader_module| {
            c.vkDestroyShaderModule(self.device, shader_module, null);
        }
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroyInstance(self.instance, null);
    }

    fn swapchainKill(self: Vulkan) void {
        for (0..self.swapchain_image_count) |index| {
            c.vkDestroyFramebuffer(self.device, self.framebuffer[index], null);
            c.vkDestroyImageView(self.device, self.swapchain_image_view[index], null);
        }
        c.vkDestroySwapchainKHR(self.device, self.swapchain, null);
    }

    pub fn swapchainInit(self: *Vulkan, comptime initial_init: bool) !void {
        try errCheck(c.vkDeviceWaitIdle(self.device));

        std.debug.print("\nCreating Swapchain\n", .{});

        // TODO: create new swapchain from old swapchain instead when possible
        self.swapchainKill();

        // create swapchain
        {
            // surface capabilities
            {
                try errCheck(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
                    self.physical_device[self.physical_device_index_gpu],
                    self.surface,
                    &self.surface_capabilities,
                ));

                const caps = self.surface_capabilities;
                std.debug.print("\nAvailable Surface Capabilities\n  - currentExtent:({},{})\n  - minImageExtent:({},{})\n  - maxImageExtent:({},{})\n  - imageCount:[{},{}]\n", .{
                    caps.currentExtent.width,
                    caps.currentExtent.height,
                    caps.minImageExtent.width,
                    caps.minImageExtent.height,
                    caps.maxImageExtent.width,
                    caps.maxImageExtent.height,
                    caps.minImageCount,
                    caps.maxImageCount,
                });
            }

            // surface formats
            {
                try errCheckAllowIncomplete(c.vkGetPhysicalDeviceSurfaceFormatsKHR(
                    self.physical_device[self.physical_device_index_gpu],
                    self.surface,
                    &self.surface_format_count,
                    &self.surface_format,
                ));
                std.debug.assert(self.surface_format_count != 0);

                for (0..self.surface_format_count) |index| {
                    const surface_format = self.surface_format[index];
                    if (surface_format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
                        surface_format.colorSpace == c.VK_COLORSPACE_SRGB_NONLINEAR_KHR)
                    {
                        self.surface_format_index_bgra_srgb = index;
                        break;
                    }
                }
                std.debug.assert(self.surface_format_index_bgra_srgb != int_invalid);

                std.debug.print("\nAvailable Surface Formats: ({})\n", .{self.surface_format_count});
                for (0..self.surface_format_count) |index| {
                    const surface_format = self.surface_format[index];
                    std.debug.print("  - format:{}, colorSpace:{}{s}\n", .{
                        surface_format.format,
                        surface_format.colorSpace,
                        if (index == self.surface_format_index_bgra_srgb) " [Selected]" else "",
                    });
                }
            }

            // present modes
            {
                try errCheckAllowIncomplete(c.vkGetPhysicalDeviceSurfacePresentModesKHR(
                    self.physical_device[self.physical_device_index_gpu],
                    self.surface,
                    &self.surface_present_mode_count,
                    &self.surface_present_mode,
                ));
                std.debug.assert(self.surface_present_mode_count != 0);

                for (0..self.surface_present_mode_count) |index| {
                    std.debug.assert(self.surface_present_mode[index] != c.VK_PRESENT_MODE_MAX_ENUM_KHR);
                }

                for (0..self.surface_present_mode_count) |index| {
                    const present_mode = self.surface_present_mode[index];
                    if (present_mode == c.VK_PRESENT_MODE_FIFO_KHR) {
                        self.surface_present_mode_index_vsync = index;
                        break;
                    }
                }
                std.debug.assert(self.surface_present_mode_index_vsync != int_invalid);

                std.debug.print("\nAvailable Surface Present Modes: ({})\n", .{self.surface_present_mode_count});
                for (0..self.surface_present_mode_count) |index| {
                    const present_mode = self.surface_present_mode[index];
                    std.debug.print("  - {s}{s}\n", .{
                        switch (present_mode) {
                            c.VK_PRESENT_MODE_IMMEDIATE_KHR => "Immediate",
                            c.VK_PRESENT_MODE_MAILBOX_KHR => "Mailbox",
                            c.VK_PRESENT_MODE_FIFO_KHR => "FIFO",
                            c.VK_PRESENT_MODE_FIFO_RELAXED_KHR => "FIFO Relaxed",
                            c.VK_PRESENT_MODE_SHARED_DEMAND_REFRESH_KHR => "Shared Demand Refresh",
                            c.VK_PRESENT_MODE_SHARED_CONTINUOUS_REFRESH_KHR => "Shared Continuous Refresh",
                            else => "Unknown",
                        },
                        if (index == self.surface_present_mode_index_vsync) " [Selected]" else "",
                    });
                }
            }

            // maxImageCount=0 means no max
            const image_count = if (self.surface_capabilities.maxImageCount > 0 and
                self.surface_capabilities.minImageCount + 1 > self.surface_capabilities.maxImageCount)
                self.surface_capabilities.maxImageCount
            else
                // NOTE: +1 avoids stalling on driver to complete internal operations before we can acquire a new image to render to
                self.surface_capabilities.minImageCount + 1;
            std.debug.assert(image_count != 0);
            std.debug.print("\nSwapchain Image Count: {}\n", .{image_count});

            {
                const surface_format = self.surface_format[self.surface_format_index_bgra_srgb];
                const swapchain_create_info = c.VkSwapchainCreateInfoKHR{
                    .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
                    .pNext = null,
                    .flags = 0,
                    .surface = self.surface,
                    .minImageCount = image_count,
                    .imageFormat = surface_format.format,
                    .imageColorSpace = surface_format.colorSpace,
                    .imageExtent = self.surface_capabilities.currentExtent,
                    .imageArrayLayers = 1,
                    // TODO: may want to change this to transfer from compute later
                    .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,

                    // TODO: change necessary if graphics and presentation are separate queue families
                    .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                    .queueFamilyIndexCount = 0,
                    .pQueueFamilyIndices = null,

                    .preTransform = self.surface_capabilities.currentTransform,
                    .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
                    .presentMode = self.surface_present_mode[self.surface_present_mode_index_vsync],
                    .clipped = c.VK_TRUE,
                    // TODO: recreate swapchain from old swapchain on resize
                    .oldSwapchain = null,
                };

                try errCheck(c.vkCreateSwapchainKHR(
                    self.device,
                    &swapchain_create_info,
                    null,
                    &self.swapchain,
                ));
                std.debug.assert(self.swapchain != null);
            }

            {
                try errCheck(c.vkGetSwapchainImagesKHR(
                    self.device,
                    self.swapchain,
                    &self.swapchain_image_count,
                    &self.swapchain_image,
                ));
                std.debug.assert(self.swapchain_image_count == image_count);
                for (0..self.swapchain_image_count) |index| {
                    std.debug.assert(self.swapchain_image[index] != null);
                }
            }
        }

        // create image views for swapchain
        {
            for (0..self.swapchain_image_count) |index| {
                const image_view_create_info = c.VkImageViewCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .image = self.swapchain_image[index],
                    .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                    .format = self.surface_format[self.surface_format_index_bgra_srgb].format,
                    .components = c.VkComponentMapping{
                        .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                        .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                        .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                        .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    },
                    .subresourceRange = c.VkImageSubresourceRange{
                        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                        .baseMipLevel = 0,
                        .levelCount = 1,
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                    },
                };

                try errCheck(c.vkCreateImageView(
                    self.device,
                    &image_view_create_info,
                    null,
                    &self.swapchain_image_view[index],
                ));
                std.debug.assert(self.swapchain_image_view[index] != null);
            }
        }

        if (initial_init) {
            // create render pass
            {
                const attachment_description_color = c.VkAttachmentDescription{
                    .flags = 0,
                    .format = self.surface_format[self.surface_format_index_bgra_srgb].format,
                    .samples = c.VK_SAMPLE_COUNT_1_BIT,
                    .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                    .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                    .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                    .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                    .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                    .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                };

                const attachment_reference_color = c.VkAttachmentReference{
                    .attachment = 0,
                    .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                };

                const subpass_description = c.VkSubpassDescription{
                    .flags = 0,
                    .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                    .inputAttachmentCount = 0,
                    .pInputAttachments = null,
                    .colorAttachmentCount = 1,
                    .pColorAttachments = &attachment_reference_color,
                    .pResolveAttachments = null,
                    .pDepthStencilAttachment = null,
                    .preserveAttachmentCount = 0,
                    .pPreserveAttachments = null,
                };

                const subpass_dependency = c.VkSubpassDependency{
                    .srcSubpass = c.VK_SUBPASS_EXTERNAL,
                    .dstSubpass = 0,
                    .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                    .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                    .srcAccessMask = 0,
                    .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                };

                const render_pass_create_info = c.VkRenderPassCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .attachmentCount = 1,
                    .pAttachments = &attachment_description_color,
                    .subpassCount = 1,
                    .pSubpasses = &subpass_description,
                    .dependencyCount = 1,
                    .pDependencies = &subpass_dependency,
                };

                try errCheck(c.vkCreateRenderPass(
                    self.device,
                    &render_pass_create_info,
                    null,
                    &self.render_pass,
                ));
                std.debug.assert(self.render_pass != null);
            }

            // create shader modules
            {
                for (
                    self.shader_name,
                    &self.shader_size,
                    &self.shader_code,
                    &self.shader_module,
                ) |name, *size, *code, *module| {
                    {
                        const file = try std.fs.cwd().openFile(name, .{ .mode = .read_only });
                        defer file.close();
                        size.* = try file.readAll(code);
                    }

                    {
                        const shader_module_create_info = c.VkShaderModuleCreateInfo{
                            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                            .pNext = null,
                            .flags = 0,
                            .codeSize = size.*,
                            .pCode = @ptrCast(code),
                        };
                        try errCheck(c.vkCreateShaderModule(
                            self.device,
                            &shader_module_create_info,
                            null,
                            module,
                        ));
                        std.debug.assert(module.* != null);
                    }
                }
            }

            // create descriptor set layout
            {
                const descriptor_set_layout_binding = [2]c.VkDescriptorSetLayoutBinding{
                    c.VkDescriptorSetLayoutBinding{
                        .binding = 0,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .descriptorCount = 1,
                        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
                        .pImmutableSamplers = null,
                    },
                    c.VkDescriptorSetLayoutBinding{
                        .binding = 1,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                        .descriptorCount = 1,
                        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                        .pImmutableSamplers = null,
                    },
                };
                try errCheck(c.vkCreateDescriptorSetLayout(
                    self.device,
                    &c.VkDescriptorSetLayoutCreateInfo{
                        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .bindingCount = descriptor_set_layout_binding.len,
                        .pBindings = &descriptor_set_layout_binding,
                    },
                    null,
                    &self.descriptor_set_layout,
                ));
                std.debug.assert(self.descriptor_set_layout != null);
            }

            // create pipeline layout
            {
                try errCheck(c.vkCreatePipelineLayout(
                    self.device,
                    &.{
                        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .setLayoutCount = 1,
                        .pSetLayouts = &self.descriptor_set_layout,
                        .pushConstantRangeCount = 0,
                        .pPushConstantRanges = null,
                    },
                    null,
                    &self.pipeline_layout,
                ));
                std.debug.assert(self.pipeline_layout != null);
            }

            // create graphics pipeline
            {
                const pipeline_shader_stage_create_info = [shader_count]c.VkPipelineShaderStageCreateInfo{
                    c.VkPipelineShaderStageCreateInfo{
                        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                        .module = self.shader_module[self.shader_index_vert],
                        .pName = "main",
                        .pSpecializationInfo = null,
                    },
                    c.VkPipelineShaderStageCreateInfo{
                        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                        .module = self.shader_module[self.shader_index_frag],
                        .pName = "main",
                        .pSpecializationInfo = null,
                    },
                };

                const pipeline_dynamic_state_create_info = c.VkPipelineDynamicStateCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .dynamicStateCount = dynamic_state.len,
                    .pDynamicStates = &dynamic_state,
                };

                const pipeline_vertex_input_state_create_info = blk: {
                    const vertex_input_binding_description = [_]c.VkVertexInputBindingDescription{
                        c.VkVertexInputBindingDescription{
                            .binding = 0,
                            .stride = @sizeOf(Vertex),
                            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
                        },
                    };

                    const vertex_input_attribute_description = [_]c.VkVertexInputAttributeDescription{
                        c.VkVertexInputAttributeDescription{
                            .location = 0,
                            .binding = 0,
                            .format = c.VK_FORMAT_R32G32_SFLOAT,
                            .offset = @offsetOf(Vertex, "pos"),
                        },
                        c.VkVertexInputAttributeDescription{
                            .location = 1,
                            .binding = 0,
                            .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                            .offset = @offsetOf(Vertex, "color"),
                        },
                        c.VkVertexInputAttributeDescription{
                            .location = 2,
                            .binding = 0,
                            .format = c.VK_FORMAT_R32G32_SFLOAT,
                            .offset = @offsetOf(Vertex, "uv"),
                        },
                    };

                    break :blk c.VkPipelineVertexInputStateCreateInfo{
                        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .vertexBindingDescriptionCount = vertex_input_binding_description.len,
                        .pVertexBindingDescriptions = &vertex_input_binding_description,
                        .vertexAttributeDescriptionCount = vertex_input_attribute_description.len,
                        .pVertexAttributeDescriptions = &vertex_input_attribute_description,
                    };
                };

                const pipeline_input_assembly_state_create_info = c.VkPipelineInputAssemblyStateCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
                    .primitiveRestartEnable = c.VK_FALSE,
                };

                const pipeline_viewport_state_create_info = c.VkPipelineViewportStateCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .viewportCount = 1,
                    .pViewports = null,
                    .scissorCount = 1,
                    .pScissors = null,
                };

                const pipeline_rasterization_state_create_info = c.VkPipelineRasterizationStateCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .depthClampEnable = c.VK_FALSE,
                    .rasterizerDiscardEnable = c.VK_FALSE,
                    .polygonMode = c.VK_POLYGON_MODE_FILL,
                    .cullMode = c.VK_CULL_MODE_BACK_BIT,
                    .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
                    .depthBiasEnable = c.VK_FALSE,
                    .depthBiasConstantFactor = 0,
                    .depthBiasClamp = 0,
                    .depthBiasSlopeFactor = 0,
                    .lineWidth = 1,
                };

                const pipeline_multisample_state_create_info = c.VkPipelineMultisampleStateCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
                    .sampleShadingEnable = c.VK_FALSE,
                    .minSampleShading = 1,
                    .pSampleMask = null,
                    .alphaToCoverageEnable = c.VK_FALSE,
                    .alphaToOneEnable = c.VK_FALSE,
                };

                const pipeline_color_blend_attachment_state = c.VkPipelineColorBlendAttachmentState{
                    .blendEnable = c.VK_FALSE,
                    .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                    .colorBlendOp = c.VK_BLEND_OP_ADD,
                    .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                    .alphaBlendOp = c.VK_BLEND_OP_ADD,
                    .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT |
                        c.VK_COLOR_COMPONENT_G_BIT |
                        c.VK_COLOR_COMPONENT_B_BIT |
                        c.VK_COLOR_COMPONENT_A_BIT,
                };

                const pipeline_color_blend_state_create_info = c.VkPipelineColorBlendStateCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .logicOpEnable = c.VK_FALSE,
                    .logicOp = c.VK_LOGIC_OP_COPY,
                    .attachmentCount = 1,
                    .pAttachments = &pipeline_color_blend_attachment_state,
                    .blendConstants = .{ 0, 0, 0, 0 },
                };

                const graphics_pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stageCount = pipeline_shader_stage_create_info.len,
                    .pStages = &pipeline_shader_stage_create_info,
                    .pVertexInputState = &pipeline_vertex_input_state_create_info,
                    .pInputAssemblyState = &pipeline_input_assembly_state_create_info,
                    .pTessellationState = null,
                    .pViewportState = &pipeline_viewport_state_create_info,
                    .pRasterizationState = &pipeline_rasterization_state_create_info,
                    .pMultisampleState = &pipeline_multisample_state_create_info,
                    .pDepthStencilState = null,
                    .pColorBlendState = &pipeline_color_blend_state_create_info,
                    .pDynamicState = &pipeline_dynamic_state_create_info,
                    .layout = self.pipeline_layout,
                    .renderPass = self.render_pass,
                    .subpass = 0,
                    .basePipelineHandle = null,
                    .basePipelineIndex = 0,
                };

                try errCheck(c.vkCreateGraphicsPipelines(
                    self.device,
                    null,
                    1,
                    &graphics_pipeline_create_info,
                    null,
                    &self.pipeline_graphics,
                ));
                std.debug.assert(self.pipeline_graphics != null);
            }
        }

        // create framebuffers
        {
            for (0..self.swapchain_image_count) |index| {
                const image_view_attachments = [_]c.VkImageView{
                    self.swapchain_image_view[index],
                };

                const extent = self.surface_capabilities.currentExtent;
                const framebuffer_create_info = c.VkFramebufferCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .renderPass = self.render_pass,
                    .attachmentCount = image_view_attachments.len,
                    .pAttachments = &image_view_attachments,
                    .width = extent.width,
                    .height = extent.height,
                    .layers = 1,
                };

                try errCheck(c.vkCreateFramebuffer(
                    self.device,
                    &framebuffer_create_info,
                    null,
                    &self.framebuffer[index],
                ));
                std.debug.assert(self.framebuffer[index] != null);
            }
        }
    }

    pub fn frameDraw(self: *Vulkan, t: f32) !void {
        // poll readiness
        {
            const fence_status = c.vkGetFenceStatus(self.device, self.fence[self.swapchain_frame_index_draw][self.fence_index_queue_submitted]);
            if (fence_status == c.VK_NOT_READY) {
                return;
            }
            try errCheck(fence_status);
        }

        // swapchain image index
        var swapchain_image_index_draw: u32 = int_invalid;
        {
            const result = c.vkAcquireNextImageKHR(
                self.device,
                self.swapchain,
                timeout_half_second,
                self.semaphore[self.swapchain_frame_index_draw][self.semaphore_index_surface_image_acquired],
                null,
                &swapchain_image_index_draw,
            );

            switch (result) {
                c.VK_ERROR_OUT_OF_DATE_KHR => {
                    try self.swapchainInit(false);
                    return;
                },
                c.VK_SUBOPTIMAL_KHR => {},
                else => {
                    try errCheck(result);
                },
            }

            std.debug.assert(swapchain_image_index_draw != int_invalid);
        }

        // update uniform buffer
        {
            // std.time.nanoTimestamp();
            const extent = self.surface_capabilities.currentExtent;
            const cam_right = m.Vec4{ 1, 0, 0, 0 };
            const cam_up = m.Vec4{ 0, 1, 0, 0 };
            const cam_forward = m.Vec4{ 0, 0, 1, 0 };
            const cam_position = m.Vec4{ 0, 0, 3, 1 };
            const cam_translation = m.Vec4{
                -m.dot(cam_position, cam_right),
                -m.dot(cam_position, cam_up),
                -m.dot(cam_position, cam_forward),
                1,
            };
            const ubo = UniformBufferObject{
                .model = m.Mat4{
                    @cos(t),  @sin(t), 0, 0,
                    -@sin(t), @cos(t), 0, 0,
                    0,        0,       1, 0,
                    0,        0,       0, 1,
                },
                .view = m.Mat4{
                    cam_right[0],       cam_up[0],          cam_forward[0],     0,
                    cam_right[1],       cam_up[1],          cam_forward[1],     0,
                    cam_right[2],       cam_up[2],          cam_forward[2],     0,
                    cam_translation[0], cam_translation[1], cam_translation[2], 1,
                },
                .proj = m.perspective(
                    std.math.pi / 4.0,
                    @as(f32, @floatFromInt(extent.width)) / @as(f32, @floatFromInt(extent.height)),
                    0.1,
                    1000,
                ),
            };

            vkMemcpy(self.mapped_memory_ubo[self.swapchain_frame_index_draw], &ubo);
            std.debug.assert(self.device_memory[device_memory_index_host_staging] != null);
        }

        // NOTE: reset fence once we know we will perform work
        try errCheck(c.vkResetFences(
            self.device,
            1,
            &self.fence[self.swapchain_frame_index_draw][self.fence_index_queue_submitted],
        ));

        // command render pass
        {
            const command_buffer = self.command_buffer[self.swapchain_frame_index_draw];

            try errCheck(
                c.vkResetCommandBuffer(command_buffer, 0),
            );

            try errCheck(c.vkBeginCommandBuffer(
                command_buffer,
                &c.VkCommandBufferBeginInfo{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                    .pNext = null,
                    .flags = 0,
                    .pInheritanceInfo = null,
                },
            ));

            c.vkCmdBeginRenderPass(
                command_buffer,
                &c.VkRenderPassBeginInfo{
                    .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                    .pNext = null,
                    .renderPass = self.render_pass,
                    .framebuffer = self.framebuffer[swapchain_image_index_draw],
                    .renderArea = .{
                        .offset = .{ .x = 0, .y = 0 },
                        .extent = self.surface_capabilities.currentExtent,
                    },
                    .clearValueCount = 1,
                    .pClearValues = &c.VkClearValue{
                        .color = .{
                            .float32 = m.Vec4{ 0, 0, 0, 1 },
                        },
                    },
                },
                c.VK_SUBPASS_CONTENTS_INLINE,
            );

            c.vkCmdBindPipeline(
                command_buffer,
                c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                self.pipeline_graphics,
            );

            c.vkCmdSetViewport(
                command_buffer,
                0,
                1,
                &c.VkViewport{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(self.surface_capabilities.currentExtent.width),
                    .height = @floatFromInt(self.surface_capabilities.currentExtent.height),
                    .minDepth = 0,
                    .maxDepth = 1,
                },
            );

            c.vkCmdSetScissor(
                command_buffer,
                0,
                1,
                &c.VkRect2D{
                    .offset = c.VkOffset2D{ .x = 0, .y = 0 },
                    .extent = self.surface_capabilities.currentExtent,
                },
            );

            c.vkCmdBindVertexBuffers(
                command_buffer,
                0,
                1,
                &self.buffer[self.buffer_index_device],
                &@as(u64, 0),
            );

            c.vkCmdBindIndexBuffer(
                command_buffer,
                self.buffer[self.buffer_index_device],
                @offsetOf(Geometry, "indices"),
                c.VK_INDEX_TYPE_UINT16,
            );

            c.vkCmdBindDescriptorSets(
                command_buffer,
                c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                self.pipeline_layout,
                0,
                1,
                &self.descriptor_set[self.swapchain_frame_index_draw],
                0,
                null,
            );
            c.vkCmdDrawIndexed(
                command_buffer,
                staging_data.buffer.indices.len,
                1,
                0,
                0,
                0,
            );

            c.vkCmdEndRenderPass(command_buffer);

            try errCheck(c.vkEndCommandBuffer(command_buffer));
        }

        try errCheck(c.vkQueueSubmit(
            self.queue,
            1,
            &c.VkSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .pNext = null,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &self.semaphore[self.swapchain_frame_index_draw][self.semaphore_index_surface_image_acquired],
                .pWaitDstStageMask = &@as(u32, c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
                .commandBufferCount = 1,
                .pCommandBuffers = &self.command_buffer[self.swapchain_frame_index_draw],
                .signalSemaphoreCount = 1,
                .pSignalSemaphores = &self.semaphore[self.swapchain_frame_index_draw][self.semaphore_index_render_finished],
            },
            self.fence[self.swapchain_frame_index_draw][self.fence_index_queue_submitted],
        ));

        // presentation
        {
            const result = c.vkQueuePresentKHR(self.queue, &c.VkPresentInfoKHR{
                .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .pNext = null,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &self.semaphore[self.swapchain_frame_index_draw][self.semaphore_index_render_finished],
                .swapchainCount = 1,
                .pSwapchains = &self.swapchain,
                .pImageIndices = &swapchain_image_index_draw,
                .pResults = null,
            });

            switch (result) {
                c.VK_ERROR_OUT_OF_DATE_KHR => try self.swapchainInit(false),
                c.VK_SUBOPTIMAL_KHR => try self.swapchainInit(false),
                else => try errCheck(result),
            }
        }

        self.swapchain_frame_index_draw = (self.swapchain_frame_index_draw + 1) % self.swapchain_image_count;
    }

    pub fn init(self: *Vulkan, ui: xcb.XcbUi) !void {
        self.* = .{};

        std.debug.print("\n=== Vulkan ===\n", .{});

        // query instance version
        {
            try errCheck(c.vkEnumerateInstanceVersion(&self.instance_version));
            std.debug.assert(self.instance_version != int_invalid);

            std.debug.print("\nSupported API Version: {}.{}.{}\n", .{
                c.VK_VERSION_MAJOR(self.instance_version),
                c.VK_VERSION_MINOR(self.instance_version),
                c.VK_VERSION_PATCH(self.instance_version),
            });
        }

        // query instance extensions
        {
            try errCheckAllowIncomplete(c.vkEnumerateInstanceExtensionProperties(
                null,
                &self.instance_extension_count,
                &self.instance_extension,
            ));
            std.debug.assert(self.instance_extension_count != 0);

            std.debug.print("\nAvailable Instance Extensions ({}):\n", .{self.instance_extension_count});
            for (0..self.instance_extension_count) |index| {
                const extension = self.instance_extension[index];
                std.debug.print("- {s} (v{})\n", .{
                    extension.extensionName,
                    extension.specVersion,
                });
            }
        }

        // query instance layers
        {
            try errCheckAllowIncomplete(c.vkEnumerateInstanceLayerProperties(
                &self.instance_layer_count,
                &self.instance_layer,
            ));
            std.debug.assert(self.instance_layer_count != 0);

            std.debug.print("\nAvailable Instance Layers ({}):\n", .{self.instance_layer_count});
            for (0..self.instance_layer_count) |index| {
                const layer = self.instance_layer[index];
                std.debug.print("- {s} ({s})\n", .{
                    layer.layerName,
                    layer.description,
                });
            }
        }

        // create instance
        // DOCS: https://docs.vulkan.org/spec/latest/chapters/initialization.html#initialization-instances
        {
            try errCheck(c.vkCreateInstance(
                &c.VkInstanceCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                    .pNext = null,
                    .pApplicationInfo = &c.VkApplicationInfo{
                        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                        .pApplicationName = "Dwarfare",
                        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
                        .pEngineName = "No Engine",
                        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
                        .apiVersion = c.VK_MAKE_VERSION(1, 1, 0),
                    },
                    .enabledLayerCount = instance_layer_enable.len,
                    .ppEnabledLayerNames = &instance_layer_enable,
                    .enabledExtensionCount = instance_extension_enable.len,
                    .ppEnabledExtensionNames = &instance_extension_enable,
                },
                null,
                &self.instance,
            ));
            std.debug.assert(self.instance != null);
        }

        // create surface
        if (builtin.os.tag == std.Target.Os.Tag.linux) {
            try errCheck(c.vkCreateXcbSurfaceKHR(
                self.instance,
                &c.VkXcbSurfaceCreateInfoKHR{
                    .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
                    .pNext = null,
                    .flags = 0,
                    .connection = @ptrCast(ui.connection),
                    .window = ui.window,
                },
                null,
                &self.surface,
            ));
            std.debug.assert(self.surface != null);
        } else {
            @compileError("unsupported os");
        }

        // query physical devices
        // DOCS: https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html#devsandqueues-physical-device-enumeration
        {
            try errCheckAllowIncomplete(c.vkEnumeratePhysicalDevices(
                self.instance,
                &self.physical_device_count,
                &self.physical_device,
            ));
            std.debug.assert(self.physical_device_count != 0);

            for (0..self.physical_device_count) |index| {
                std.debug.assert(self.physical_device[index] != null);
            }

            // fill
            for (0..self.physical_device_count) |index| {
                const physical_device = self.physical_device[index];
                c.vkGetPhysicalDeviceProperties(
                    physical_device,
                    &self.physical_device_properties[index],
                );
                c.vkGetPhysicalDeviceFeatures(
                    physical_device,
                    &self.physical_device_features[index],
                );
                c.vkGetPhysicalDeviceMemoryProperties(
                    physical_device,
                    &self.physical_device_memory_properties[index],
                );
            }

            // pick
            for (0..self.physical_device_count) |index| {
                const properties = self.physical_device_properties[index];
                if (properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                    self.physical_device_index_gpu = index;
                    break;
                }
            }
            std.debug.assert(self.physical_device_index_gpu != int_invalid);

            // print
            std.debug.print("\nAvailable Physical Devices ({})\n", .{self.physical_device_count});
            for (0..self.physical_device_count) |index| {
                const properties = self.physical_device_properties[index];
                std.debug.print("- {s} ({s}){s}\n", .{
                    properties.deviceName,
                    switch (properties.deviceType) {
                        c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "Integrated GPU",
                        c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "Discrete GPU",
                        c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "Virtual GPU",
                        c.VK_PHYSICAL_DEVICE_TYPE_CPU => "CPU",
                        else => "Unknown",
                    },
                    if (index == self.physical_device_index_gpu) " [Selected GPU]" else "",
                });
            }
        }

        // query queue families
        {
            // fill
            c.vkGetPhysicalDeviceQueueFamilyProperties(
                self.physical_device[self.physical_device_index_gpu],
                &self.queue_family_count,
                &self.queue_family,
            );
            std.debug.assert(self.queue_family_count != 0);

            // pick
            for (0..self.queue_family_count) |index| {
                const queue_family = self.queue_family[index];
                const mask = c.VK_QUEUE_GRAPHICS_BIT | c.VK_QUEUE_COMPUTE_BIT | c.VK_QUEUE_TRANSFER_BIT;
                if ((queue_family.queueFlags & mask) != 0) {
                    self.queue_family_index_graphics = @intCast(index);
                    break;
                }
            }
            std.debug.assert(self.queue_family_index_graphics != int_invalid);

            // print
            std.debug.print("\nAvailable Queue Families ({})\n", .{self.queue_family_count});
            for (0..self.queue_family_count) |index| {
                const queue_family = self.queue_family[index];
                std.debug.print("  - {b:9}{s}\n", .{
                    queue_family.queueFlags,
                    if (index == self.queue_family_index_graphics) " [Selected]" else "",
                });
            }
        }

        // query device extensions
        {
            try errCheckAllowIncomplete(c.vkEnumerateDeviceExtensionProperties(
                self.physical_device[self.physical_device_index_gpu],
                null,
                &self.device_extension_count,
                &self.device_extension,
            ));
            std.debug.assert(self.device_extension_count != 0);

            std.debug.print("\nAvailable Device Extensions ({}):\n", .{self.device_extension_count});
            for (0..self.device_extension_count) |index| {
                const extension = self.device_extension[index];
                // TODO: not sure why names end with �
                std.debug.print("- {s} (v{})\n", .{
                    extension.extensionName,
                    extension.specVersion,
                });
            }
        }

        // create device
        {
            const features_available = self.physical_device_features[self.physical_device_index_gpu];
            try errCheck(c.vkCreateDevice(
                self.physical_device[self.physical_device_index_gpu],
                &c.VkDeviceCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .queueCreateInfoCount = 1,
                    .pQueueCreateInfos = &c.VkDeviceQueueCreateInfo{
                        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .queueFamilyIndex = self.queue_family_index_graphics,
                        .queueCount = 1,
                        .pQueuePriorities = &@as(f32, 1.0),
                    },
                    .enabledLayerCount = 0,
                    .ppEnabledLayerNames = null,
                    .enabledExtensionCount = device_extension_enable.len,
                    .ppEnabledExtensionNames = &device_extension_enable,
                    .pEnabledFeatures = &c.VkPhysicalDeviceFeatures{
                        .robustBufferAccess = 0,
                        .fullDrawIndexUint32 = 0,
                        .imageCubeArray = 0,
                        .independentBlend = 0,
                        .geometryShader = 0,
                        .tessellationShader = 0,
                        .sampleRateShading = 0,
                        .dualSrcBlend = 0,
                        .logicOp = 0,
                        .multiDrawIndirect = 0,
                        .drawIndirectFirstInstance = 0,
                        .depthClamp = 0,
                        .depthBiasClamp = 0,
                        .fillModeNonSolid = 0,
                        .depthBounds = 0,
                        .wideLines = 0,
                        .largePoints = 0,
                        .alphaToOne = 0,
                        .multiViewport = 0,
                        .samplerAnisotropy = features_available.samplerAnisotropy & c.VK_TRUE,
                        .textureCompressionETC2 = 0,
                        .textureCompressionASTC_LDR = 0,
                        .textureCompressionBC = 0,
                        .occlusionQueryPrecise = 0,
                        .pipelineStatisticsQuery = 0,
                        .vertexPipelineStoresAndAtomics = 0,
                        .fragmentStoresAndAtomics = 0,
                        .shaderTessellationAndGeometryPointSize = 0,
                        .shaderImageGatherExtended = 0,
                        .shaderStorageImageExtendedFormats = 0,
                        .shaderStorageImageMultisample = 0,
                        .shaderStorageImageReadWithoutFormat = 0,
                        .shaderStorageImageWriteWithoutFormat = 0,
                        .shaderUniformBufferArrayDynamicIndexing = 0,
                        .shaderSampledImageArrayDynamicIndexing = 0,
                        .shaderStorageBufferArrayDynamicIndexing = 0,
                        .shaderStorageImageArrayDynamicIndexing = 0,
                        .shaderClipDistance = 0,
                        .shaderCullDistance = 0,
                        .shaderFloat64 = 0,
                        .shaderInt64 = 0,
                        .shaderInt16 = 0,
                        .shaderResourceResidency = 0,
                        .shaderResourceMinLod = 0,
                        .sparseBinding = 0,
                        .sparseResidencyBuffer = 0,
                        .sparseResidencyImage2D = 0,
                        .sparseResidencyImage3D = 0,
                        .sparseResidency2Samples = 0,
                        .sparseResidency4Samples = 0,
                        .sparseResidency8Samples = 0,
                        .sparseResidency16Samples = 0,
                        .sparseResidencyAliased = 0,
                        .variableMultisampleRate = 0,
                        .inheritedQueries = 0,
                    },
                },
                null,
                &self.device,
            ));
            std.debug.assert(self.device != null);
        }

        // queue
        {
            c.vkGetDeviceQueue(
                self.device,
                self.queue_family_index_graphics,
                self.queue_index_graphics,
                &self.queue,
            );
            std.debug.assert(self.queue != null);
        }

        // check physical device surface support
        {
            var supported = c.VK_FALSE;
            try errCheck(c.vkGetPhysicalDeviceSurfaceSupportKHR(
                self.physical_device[self.physical_device_index_gpu],
                self.queue_family_index_graphics,
                self.surface,
                &supported,
            ));
            if (supported != c.VK_TRUE) {
                return error.VkErrorMissingSurfaceSupport;
            }
        }

        // TODO: consider hi-DPI support
        try self.swapchainInit(true);

        // create command pool
        {
            var command_pool_create_info: [command_pool_count]c.VkCommandPoolCreateInfo = undefined;
            command_pool_create_info[command_pool_index_staging] = .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .pNext = null,
                .flags = c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
                .queueFamilyIndex = self.queue_family_index_graphics,
            };
            command_pool_create_info[command_pool_index_swapchain] = .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .pNext = null,
                .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                .queueFamilyIndex = self.queue_family_index_graphics,
            };

            inline for (0..command_pool_count) |index| {
                try errCheck(c.vkCreateCommandPool(
                    self.device,
                    &command_pool_create_info[index],
                    null,
                    &self.command_pool[index],
                ));
                std.debug.assert(self.command_pool[index] != null);
            }
        }

        // create samplers
        {
            const anisotropy_support = self.physical_device_features[self.physical_device_index_gpu].samplerAnisotropy;
            try errCheck(c.vkCreateSampler(
                self.device,
                &c.VkSamplerCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .magFilter = c.VK_FILTER_NEAREST,
                    .minFilter = c.VK_FILTER_NEAREST,
                    .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
                    .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                    .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                    .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                    .mipLodBias = 0,
                    .anisotropyEnable = anisotropy_support & c.VK_TRUE,
                    .maxAnisotropy = self.physical_device_properties[self.physical_device_index_gpu].limits.maxSamplerAnisotropy,
                    .compareEnable = c.VK_FALSE,
                    .compareOp = c.VK_COMPARE_OP_NEVER,
                    .minLod = 0,
                    .maxLod = 0,
                    .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
                    .unnormalizedCoordinates = c.VK_FALSE,
                },
                null,
                &self.sampler,
            ));
            std.debug.assert(self.sampler != null);
        }

        // create images
        {
            // setup pointers
            {
                // NOTE: required to be laid out grouped by expected memory properties and in the order of matching device_memory_index_*s

                {
                    // DEVICE_LOCAL
                    std.debug.assert(device_memory_index_device_local == 0);
                    {
                        self.image_index_checkerboard = 0;
                    }
                    self.device_memory_image_index[device_memory_index_device_local] = Slice{
                        .offset = 0,
                        .size = 1,
                    };
                }

                self.image_count = 1;
                std.debug.assert(self.image_count <= image_count_max);
            }

            var image_create_info: [image_count_max]c.VkImageCreateInfo = undefined;
            image_create_info[self.image_index_checkerboard] = c.VkImageCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .imageType = c.VK_IMAGE_TYPE_2D,
                .format = c.VK_FORMAT_R8G8B8A8_SRGB,
                .extent = c.VkExtent3D{
                    .width = 2,
                    .height = 2,
                    .depth = 1,
                },
                .mipLevels = 1,
                .arrayLayers = 1,
                .samples = c.VK_SAMPLE_COUNT_1_BIT,
                .tiling = c.VK_IMAGE_TILING_OPTIMAL,
                .usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
                .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            };

            for (0..self.image_count) |index| {
                try errCheck(c.vkCreateImage(
                    self.device,
                    &image_create_info[index],
                    null,
                    &self.image[index],
                ));
                std.debug.assert(self.image[index] != null);
            }
        }

        // query image memory requirements
        {
            std.debug.print("\nImages: ({})\n", .{self.image_count});
            for (0..self.image_count) |index| {
                const req = &self.image_memory_requirements[index];
                c.vkGetImageMemoryRequirements(
                    self.device,
                    self.image[index],
                    req,
                );
                std.debug.print("  - size:{}, alignment:{}, memoryTypeBits:0b{b}\n", .{
                    req.size,
                    req.alignment,
                    req.memoryTypeBits,
                });
            }
        }

        // create buffers
        {
            // setup pointers
            {
                // NOTE: required to be laid out grouped by expected memory properties and in the order of matching device_memory_index_*s

                {
                    // DEVICE_LOCAL
                    std.debug.assert(device_memory_index_device_local == 0);
                    {
                        self.buffer_index_device = 0;
                    }
                    self.device_memory_buffer_index[device_memory_index_device_local] = Slice{
                        .offset = 0,
                        .size = 1,
                    };
                }

                {
                    // HOST_VISIBLE | HOST_COHERENT
                    std.debug.assert(device_memory_index_host_staging == 1);
                    {
                        self.buffer_index_staging = 1;
                        self.buffer_index_uniform = Slice{
                            .offset = 2,
                            .size = self.swapchain_image_count,
                        };
                    }
                    self.device_memory_buffer_index[device_memory_index_host_staging] = Slice{
                        .offset = 1,
                        .size = 1 + self.swapchain_image_count,
                    };
                }

                self.buffer_count = 2 + self.swapchain_image_count;
                std.debug.assert(self.buffer_count <= buffer_count_max);
            }

            var buffer_create_info: [buffer_count_max]c.VkBufferCreateInfo = undefined;
            buffer_create_info[self.buffer_index_staging] = c.VkBufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .size = @sizeOf(StagingData),
                .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
            };
            buffer_create_info[self.buffer_index_device] = c.VkBufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .size = @sizeOf(Geometry),
                .usage = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
            };
            for (0..self.buffer_index_uniform.size) |index| {
                buffer_create_info[self.buffer_index_uniform.offset + index] = c.VkBufferCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .size = @sizeOf(UniformBufferObject),
                    .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                    .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                    .queueFamilyIndexCount = 0,
                    .pQueueFamilyIndices = null,
                };
            }

            for (0..self.buffer_count) |index| {
                try errCheck(c.vkCreateBuffer(
                    self.device,
                    &buffer_create_info[index],
                    null,
                    &self.buffer[index],
                ));
                std.debug.assert(self.buffer[index] != null);
            }
        }

        // query buffer memory requirements
        {
            std.debug.print("\nBuffers: ({})\n", .{self.buffer_count});
            for (0..self.buffer_count) |index| {
                const req = &self.buffer_memory_requirements[index];
                c.vkGetBufferMemoryRequirements(
                    self.device,
                    self.buffer[index],
                    req,
                );
                std.debug.print("  - size:{}, alignment:{}, memoryTypeBits:0b{b}\n", .{
                    req.size,
                    req.alignment,
                    req.memoryTypeBits,
                });
            }
        }

        // allocate memory
        {
            var memory_properties_required: [device_memory_count]u32 = undefined;
            memory_properties_required[device_memory_index_device_local] = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
            memory_properties_required[device_memory_index_host_staging] = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;

            std.debug.print("\nDevice Memory ({}):\n", .{device_memory_count});
            for (0..device_memory_count) |device_memory_index| {
                const device_properties_required = memory_properties_required[device_memory_index];
                std.debug.print("  - properties: 0b{b:0>9}\n", .{device_properties_required});
                const device_properties = self.physical_device_memory_properties[self.physical_device_index_gpu];

                var allocation_size: u64 = 0;
                var memory_type_index: u32 = 0;

                std.debug.print("    images:\n", .{});
                const image_batch = self.device_memory_image_index[device_memory_index];
                for (0..image_batch.size) |image_index_batch| {
                    const image_index = image_batch.offset + image_index_batch;
                    const memory_requirements = self.image_memory_requirements[image_index];
                    allocation_size = std.mem.alignForward(
                        usize,
                        allocation_size,
                        memory_requirements.alignment,
                    );
                    std.debug.print("      - index:{}, offset:{}, size:{}\n", .{ image_index, allocation_size, memory_requirements.size });
                    self.image_mapping[image_index] = .{
                        .offset = allocation_size,
                        .size = memory_requirements.size,
                    };
                    allocation_size += memory_requirements.size;
                    memory_type_index = blk: {
                        for (0..device_properties.memoryTypeCount) |index| {
                            const memory_type_required = (memory_requirements.memoryTypeBits & std.math.shl(u32, 1, index)) != 0;
                            const properties_satisfied = (device_properties.memoryTypes[index].propertyFlags & device_properties_required) == device_properties_required;
                            if (memory_type_required and properties_satisfied) {
                                break :blk @intCast(index);
                            }
                        }
                        return error.VkMemoryTypeIndexNotFound;
                    };
                }

                std.debug.print("    buffers:\n", .{});
                const buffer_batch = self.device_memory_buffer_index[device_memory_index];
                for (0..buffer_batch.size) |buffer_index_batch| {
                    const buffer_index = buffer_batch.offset + buffer_index_batch;
                    const memory_requirements = self.buffer_memory_requirements[buffer_index];
                    allocation_size = std.mem.alignForward(
                        usize,
                        allocation_size,
                        memory_requirements.alignment,
                    );
                    std.debug.print("      - index:{}, offset:{}, size:{}, alignment:{}\n", .{
                        buffer_index,
                        allocation_size,
                        memory_requirements.size,
                        memory_requirements.alignment,
                    });
                    self.buffer_mapping[buffer_index] = .{
                        .offset = allocation_size,
                        .size = memory_requirements.size,
                    };
                    allocation_size += memory_requirements.size;
                    memory_type_index = blk: {
                        for (0..device_properties.memoryTypeCount) |index| {
                            const memory_type_required = (memory_requirements.memoryTypeBits & std.math.shl(u32, 1, index)) != 0;
                            const properties_satisfied = (device_properties.memoryTypes[index].propertyFlags & device_properties_required) == device_properties_required;
                            if (memory_type_required and properties_satisfied) {
                                break :blk @intCast(index);
                            }
                        }
                        return error.VkMemoryTypeIndexNotFound;
                    };
                }

                std.debug.print("    size: {}\n", .{allocation_size});

                try errCheck(c.vkAllocateMemory(
                    self.device,
                    &c.VkMemoryAllocateInfo{
                        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                        .pNext = null,
                        .allocationSize = allocation_size,
                        .memoryTypeIndex = memory_type_index,
                    },
                    null,
                    &self.device_memory[device_memory_index],
                ));
                std.debug.assert(self.device_memory[device_memory_index] != null);
            }
        }

        // bind memory
        {
            inline for (0..device_memory_count) |device_memory_index| {
                const image_batch = self.device_memory_image_index[device_memory_index];
                for (0..image_batch.size) |image_index_batch| {
                    const image_index = image_batch.offset + image_index_batch;
                    try errCheck(c.vkBindImageMemory(
                        self.device,
                        self.image[image_index],
                        self.device_memory[device_memory_index],
                        self.image_mapping[image_index].offset,
                    ));
                }

                const buffer_batch = self.device_memory_buffer_index[device_memory_index];
                for (0..buffer_batch.size) |buffer_index_batch| {
                    const buffer_index = buffer_batch.offset + buffer_index_batch;
                    try errCheck(c.vkBindBufferMemory(
                        self.device,
                        self.buffer[buffer_index],
                        self.device_memory[device_memory_index],
                        self.buffer_mapping[buffer_index].offset,
                    ));
                }
            }
        }

        // create image views
        {
            for (0..self.image_count) |index| {
                try errCheck(c.vkCreateImageView(
                    self.device,
                    &c.VkImageViewCreateInfo{
                        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .image = self.image[index],
                        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                        .format = c.VK_FORMAT_R8G8B8A8_SRGB,
                        .components = c.VkComponentMapping{
                            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                        },
                        .subresourceRange = c.VkImageSubresourceRange{
                            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                            .baseMipLevel = 0,
                            .levelCount = 1,
                            .baseArrayLayer = 0,
                            .layerCount = 1,
                        },
                    },
                    null,
                    &self.image_view[index],
                ));
                std.debug.assert(self.image_view[index] != null);
            }
        }

        // write staging memory
        {
            const mapping = self.buffer_mapping[self.buffer_index_staging];
            var data: ?*anyopaque = null;
            try errCheck(c.vkMapMemory(
                self.device,
                self.device_memory[device_memory_index_host_staging],
                mapping.offset,
                mapping.size,
                0,
                &data,
            ));
            std.debug.assert(data != null);
            vkMemcpy(data, &staging_data);
            c.vkUnmapMemory(self.device, self.device_memory[device_memory_index_host_staging]);
        }

        // copy from staging memory to device local memory
        {
            var command_buffer: c.VkCommandBuffer = null;
            {
                try errCheck(c.vkAllocateCommandBuffers(
                    self.device,
                    &c.VkCommandBufferAllocateInfo{
                        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                        .pNext = null,
                        .commandPool = self.command_pool[command_pool_index_staging],
                        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                        .commandBufferCount = 1,
                    },
                    &command_buffer,
                ));
                std.debug.assert(command_buffer != null);
            }

            try errCheck(c.vkBeginCommandBuffer(
                command_buffer,
                &c.VkCommandBufferBeginInfo{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                    .pNext = null,
                    .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
                    .pInheritanceInfo = null,
                },
            ));

            // copy buffer from host to device
            c.vkCmdCopyBuffer(
                command_buffer,
                self.buffer[self.buffer_index_staging],
                self.buffer[self.buffer_index_device],
                1,
                &c.VkBufferCopy{
                    .srcOffset = @offsetOf(StagingData, "buffer"),
                    .dstOffset = 0,
                    .size = self.buffer_mapping[self.buffer_index_device].size,
                },
            );

            // transition image layout for copying into
            c.vkCmdPipelineBarrier(
                command_buffer,
                c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                c.VK_PIPELINE_STAGE_TRANSFER_BIT,
                0,
                0,
                null,
                0,
                null,
                1,
                &c.VkImageMemoryBarrier{
                    .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                    .pNext = null,
                    .srcAccessMask = 0,
                    .dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
                    .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                    .newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                    .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                    .image = self.image[self.image_index_checkerboard],
                    .subresourceRange = c.VkImageSubresourceRange{
                        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                        .baseMipLevel = 0,
                        .levelCount = 1,
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                    },
                },
            );

            // copy image from host to device
            c.vkCmdCopyBufferToImage(
                command_buffer,
                self.buffer[self.buffer_index_staging],
                self.image[self.image_index_checkerboard],
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                1,
                &c.VkBufferImageCopy{
                    .bufferOffset = self.buffer_mapping[self.buffer_index_staging].offset +
                        @offsetOf(StagingData, "image"),
                    .bufferRowLength = 0, // tightly packed
                    .bufferImageHeight = 0, // tightly packed
                    .imageSubresource = c.VkImageSubresourceLayers{
                        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                        .mipLevel = 0,
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                    },
                    .imageOffset = c.VkOffset3D{ .x = 0, .y = 0, .z = 0 },
                    .imageExtent = c.VkExtent3D{ .width = 2, .height = 2, .depth = 1 },
                },
            );

            // transition image layout for reading from fragment shader
            c.vkCmdPipelineBarrier(
                command_buffer,
                c.VK_PIPELINE_STAGE_TRANSFER_BIT,
                c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                0,
                0,
                null,
                0,
                null,
                1,
                &c.VkImageMemoryBarrier{
                    .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                    .pNext = null,
                    .srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
                    .dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT,
                    .oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    .newLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                    .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                    .image = self.image[self.image_index_checkerboard],
                    .subresourceRange = c.VkImageSubresourceRange{
                        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                        .baseMipLevel = 0,
                        .levelCount = 1,
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                    },
                },
            );

            try errCheck(c.vkEndCommandBuffer(command_buffer));

            try errCheck(c.vkQueueSubmit(
                self.queue,
                1,
                &.{
                    .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                    .pNext = null,
                    .waitSemaphoreCount = 0,
                    .pWaitSemaphores = null,
                    .pWaitDstStageMask = null,
                    .commandBufferCount = 1,
                    .pCommandBuffers = &command_buffer,
                    .signalSemaphoreCount = 0,
                    .pSignalSemaphores = null,
                },
                null,
            ));
            try errCheck(c.vkQueueWaitIdle(self.queue));

            c.vkFreeCommandBuffers(
                self.device,
                self.command_pool[command_pool_index_staging],
                1,
                &command_buffer,
            );
        }

        // persistent mapping of uniforms
        {
            const mapping = self.buffer_mapping[self.buffer_index_uniform.offset];
            try errCheck(c.vkMapMemory(
                self.device,
                self.device_memory[device_memory_index_host_staging],
                mapping.offset,
                mapping.size * self.buffer_index_uniform.size,
                0,
                &self.mapped_memory_ubo[0],
            ));
            std.debug.assert(self.mapped_memory_ubo[0] != null);
            for (1..self.swapchain_image_count) |index| {
                self.mapped_memory_ubo[index] = @ptrFromInt(@intFromPtr(self.mapped_memory_ubo[0].?) + index * mapping.size);
            }
        }

        // allocate swapchain command buffers
        {
            try errCheck(c.vkAllocateCommandBuffers(
                self.device,
                &c.VkCommandBufferAllocateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                    .pNext = null,
                    .commandPool = self.command_pool[command_pool_index_swapchain],
                    .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                    .commandBufferCount = self.swapchain_image_count,
                },
                &self.command_buffer,
            ));
            for (0..self.swapchain_image_count) |index| {
                std.debug.assert(self.command_buffer[index] != null);
            }
        }

        // create descriptor pool
        {
            const descriptor_pool_size = [2]c.VkDescriptorPoolSize{
                c.VkDescriptorPoolSize{
                    .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount = self.swapchain_image_count,
                },
                c.VkDescriptorPoolSize{
                    .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .descriptorCount = self.swapchain_image_count,
                },
            };
            try errCheck(c.vkCreateDescriptorPool(
                self.device,
                &c.VkDescriptorPoolCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
                    .poolSizeCount = descriptor_pool_size.len,
                    .pPoolSizes = &descriptor_pool_size,
                    .maxSets = self.swapchain_image_count,
                },
                null,
                &self.descriptor_pool,
            ));
            std.debug.assert(self.descriptor_pool != null);
        }

        // allocate descriptor sets
        {
            var layouts: [swapchain_image_count_max]c.VkDescriptorSetLayout = undefined;
            for (0..self.swapchain_image_count) |index| {
                layouts[index] = self.descriptor_set_layout;
            }
            try errCheck(c.vkAllocateDescriptorSets(
                self.device,
                &c.VkDescriptorSetAllocateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                    .pNext = null,
                    .descriptorPool = self.descriptor_pool,
                    .descriptorSetCount = self.swapchain_image_count,
                    .pSetLayouts = &layouts,
                },
                &self.descriptor_set,
            ));
            for (0..self.swapchain_image_count) |index| {
                std.debug.assert(self.descriptor_set[index] != null);
            }
        }

        // populate descriptor sets
        {
            for (0..self.swapchain_image_count) |index| {
                const descriptor_write = [2]c.VkWriteDescriptorSet{
                    c.VkWriteDescriptorSet{
                        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .pNext = null,
                        .dstSet = self.descriptor_set[index],
                        .dstBinding = 0,
                        .dstArrayElement = 0,
                        .descriptorCount = 1,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .pImageInfo = null,
                        .pBufferInfo = &c.VkDescriptorBufferInfo{
                            .buffer = self.buffer[self.buffer_index_uniform.offset + index],
                            .offset = 0,
                            .range = self.buffer_mapping[self.buffer_index_uniform.offset + index].size,
                        },
                        .pTexelBufferView = null,
                    },
                    c.VkWriteDescriptorSet{
                        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .pNext = null,
                        .dstSet = self.descriptor_set[index],
                        .dstBinding = 1,
                        .dstArrayElement = 0,
                        .descriptorCount = 1,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                        .pImageInfo = &c.VkDescriptorImageInfo{
                            .sampler = self.sampler,
                            .imageView = self.image_view[self.image_index_checkerboard],
                            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                        },
                        .pBufferInfo = null,
                        .pTexelBufferView = null,
                    },
                };
                c.vkUpdateDescriptorSets(
                    self.device,
                    descriptor_write.len,
                    &descriptor_write,
                    0,
                    null,
                );
            }
        }

        // create semaphores
        {
            const semaphore_create_info = c.VkSemaphoreCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
            };

            for (0..self.swapchain_image_count) |swapchain_image_index| {
                inline for (0..semaphore_count) |index| {
                    try errCheck(c.vkCreateSemaphore(
                        self.device,
                        &semaphore_create_info,
                        null,
                        &self.semaphore[swapchain_image_index][index],
                    ));
                    std.debug.assert(self.semaphore[swapchain_image_index][index] != null);
                }
            }
        }

        // create fences
        {
            const fence_create_info = c.VkFenceCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                .pNext = null,
                .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
            };

            for (0..self.swapchain_image_count) |swapchain_image_index| {
                inline for (0..fence_count) |index| {
                    try errCheck(c.vkCreateFence(
                        self.device,
                        &fence_create_info,
                        null,
                        &self.fence[swapchain_image_index][index],
                    ));
                    std.debug.assert(self.fence[swapchain_image_index][index] != null);
                }
            }
        }
    }
};

fn errCheck(result: c.VkResult) !void {
    return switch (result) {
        c.VK_SUCCESS => {},
        c.VK_NOT_READY => error.VkNotReady,
        c.VK_TIMEOUT => error.VkTimeout,
        c.VK_EVENT_SET => error.VkEventSet,
        c.VK_EVENT_RESET => error.VkEventReset,
        c.VK_INCOMPLETE => error.VkIncomplete,
        c.VK_ERROR_OUT_OF_HOST_MEMORY => error.VkErrorOutOfHostMemory,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => error.VkErrorOutOfDeviceMemory,
        c.VK_ERROR_INITIALIZATION_FAILED => error.VkErrorInitializationFailed,
        c.VK_ERROR_DEVICE_LOST => error.VkErrorDeviceLost,
        c.VK_ERROR_MEMORY_MAP_FAILED => error.VkErrorMemoryMapFailed,
        c.VK_ERROR_LAYER_NOT_PRESENT => error.VkErrorLayerNotPresent,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => error.VkErrorExtensionNotPresent,
        c.VK_ERROR_FEATURE_NOT_PRESENT => error.VkErrorFeatureNotPresent,
        c.VK_ERROR_INCOMPATIBLE_DRIVER => error.VkErrorIncompatibleDriver,
        c.VK_ERROR_TOO_MANY_OBJECTS => error.VkErrorTooManyObjects,
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => error.VkErrorFormatNotSupported,
        c.VK_ERROR_FRAGMENTED_POOL => error.VkErrorFragmentedPool,
        c.VK_ERROR_UNKNOWN => error.VkErrorUnknown,
        c.VK_ERROR_OUT_OF_POOL_MEMORY => error.VkErrorOutOfPoolMemory,
        c.VK_ERROR_INVALID_EXTERNAL_HANDLE => error.VkErrorInvalidExternalHandle,
        c.VK_ERROR_FRAGMENTATION => error.VkErrorFragmentation,
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => error.VkErrorInvalidOpaqueCaptureAddress,
        c.VK_PIPELINE_COMPILE_REQUIRED => error.VkPipelineCompileRequired,
        c.VK_ERROR_SURFACE_LOST_KHR => error.VkSurfaceLostKhr,
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => error.VkErrorNativeWindowInUseKhr,
        c.VK_SUBOPTIMAL_KHR => error.VkSuboptimalKhr,
        c.VK_ERROR_OUT_OF_DATE_KHR => error.VkErrorOutOfDateKhr,
        c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => error.VkErrorIncompatibleDisplayKhr,
        c.VK_ERROR_VALIDATION_FAILED_EXT => error.VkErrorValidationFailedExt,
        c.VK_ERROR_INVALID_SHADER_NV => error.VkErrorInvalidShaderNv,
        c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => error.VkErrorImageUsageNotSupportedKhr,
        c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => error.VkErrorVideoPictureLayoutNotSupportedKhr,
        c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => error.VkErrorVideoProfileOperationNotSupportedKhr,
        c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => error.VkErrorVideoProfileFormatNotSupportedKhr,
        c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => error.VkErrorVideoProfileCodecNotSupportedKhr,
        c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => error.VkErrorVideoStdVersionNotSupportedKhr,
        c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => error.VkErrorInvalidDrmFormatModifierPlaneLayoutExt,
        c.VK_ERROR_NOT_PERMITTED_KHR => error.VkErrorNotPermittedKhr,
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => error.VkErrorFullScreenExclusiveModeLostExt,
        c.VK_THREAD_IDLE_KHR => error.VkThreadIdleKhr,
        c.VK_THREAD_DONE_KHR => error.VkThreadDoneKhr,
        c.VK_OPERATION_DEFERRED_KHR => error.VkOperationDeferredKhr,
        c.VK_OPERATION_NOT_DEFERRED_KHR => error.VkOperationNotDeferredKhr,
        c.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => error.VkErrorInvalidVideoStdParametersKhr,
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => error.VkErrorCompressionExhaustedExt,
        c.VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => error.VkErrorIncompatibleShaderBinaryExt,
        else => error.VkErrorGeneric,
    };
}

fn errCheckAllowIncomplete(result: c.VkResult) !void {
    if (result == c.VK_INCOMPLETE) {
        return;
    }
    return errCheck(result);
}

// DOCS: https://registry.khronos.org/vulkan/specs/1.3-extensions/html/chap15.html#interfaces-resources-layout
fn vkBaseAlign(comptime T: type) comptime_int {
    return switch (@typeInfo(T)) {
        // NOTE: A scalar of size N has a scalar alignment of N.
        .Float => @sizeOf(T),
        .Int => @sizeOf(T),
        .ComptimeFloat => @sizeOf(T),
        .ComptimeInt => @sizeOf(T),

        .Vector => |vector| switch (vector.len) {
            // NOTE: A two-component vector has a base alignment equal to twice its scalar alignment.
            2 => 2 * @sizeOf(vector.child),
            // NOTE: A three- or four-component vector has a base alignment equal to four times its scalar alignment.
            3 => 4 * @sizeOf(vector.child),
            4 => 4 * @sizeOf(vector.child),
            else => unreachable,
        },

        // NOTE: An array has a base alignment equal to the base alignment of its element type.
        // NOTE: A matrix type inherits base alignment from the equivalent array declaration.
        .Array => |array| vkBaseAlign(array.child),

        // NOTE: A structure has a base alignment equal to the largest base alignment of any of its members.
        .Struct => |s| blk: {
            var max = 0;
            for (s.fields) |field| {
                // NOTE: fields are assumed to explicitly aligned, so we don't need recursion.
                max = @max(field.alignment, max);
            }
            break :blk max;
        },

        else => unreachable,
    };
}

// NOTE: run using `zig test src/vulkan.zig` until integrated with `build.zig`
// TODO: integrate with `build.zig`
test "vulkan alignment" {
    try std.testing.expectEqual(@sizeOf(m.Real), vkBaseAlign(m.Real));
    try std.testing.expectEqual(@sizeOf(m.Real), vkBaseAlign([4]m.Real));
    try std.testing.expectEqual(2 * @sizeOf(m.Real), vkBaseAlign(m.Vec2));
    try std.testing.expectEqual(4 * @sizeOf(m.Real), vkBaseAlign(m.Vec3));
    try std.testing.expectEqual(@max(vkBaseAlign(m.Vec2), vkBaseAlign(m.Vec3)), vkBaseAlign(Vertex));
    // TODO: standard buffer alignment

    // TODO: move this out of base alignment requirements
    // .Array => |array| switch (@typeInfo(array.child)) {
    //     // NOTE: All vectors must be aligned according to their scalar alignment.
    //     .Vector => |vector| vector.len * vkBaseAlign(vector.child),
    //     // TODO: how to enforce the following?
    //     // If the uniformBufferStandardLayout feature is not enabled on the device, then any member of an OpTypeStruct with a storage class of Uniform and a decoration of Block must be aligned according to its extended alignment.

    //     // NOTE: Every other member must be aligned according to its base alignment.
    //     else => vkBaseAlign(array.child),
    // },

    // try std.testing.expectEqual(3 * @sizeOf(Real), vkBaseAlign([1]Vec3));
}

fn vkMemcpy(destination: ?*anyopaque, source: anytype) void {
    std.debug.assert(@typeInfo(@TypeOf(source)) == .Pointer);
    // NOTE: memcpy, rather than a write to the pointer, does not require zig's stricter alignment, which may be violated by vulkan
    @memcpy(
        @as([*]u8, @ptrCast(destination)),
        std.mem.asBytes(source),
    );
}
