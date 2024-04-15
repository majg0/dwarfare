const std = @import("std");
const builtin = @import("builtin");
const xcb = @import("./xcb.zig");
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("xcb/xcb.h");
    @cInclude("vulkan/vulkan_xcb.h");
});

// DOCS: https://docs.vulkan.org/spec/latest/index.html

const int_invalid = 0xDEAD;

const instance_layer_enable = if (builtin.mode == std.builtin.Mode.Debug)
    [_][*c]const u8{
        "VK_LAYER_KHRONOS_validation",
    }
else
    [_][*c]const u8{};
const instance_extension_enable = [_][*c]const u8{
    "VK_KHR_surface",
    if (builtin.os.tag == std.Target.Os.Tag.linux)
        "VK_KHR_xcb_surface"
    else
        unreachable,
};
const device_extension_enable = [_][*c]const u8{
    "VK_KHR_swapchain",
};
const dynamic_state: [2]c.VkDynamicState align(4) = .{
    c.VK_DYNAMIC_STATE_VIEWPORT,
    c.VK_DYNAMIC_STATE_SCISSOR,
};

const instance_extension_count_max = 64;
const instance_layer_count_max = 64;
const physical_device_count_max = 8;
const queue_family_count_max = 16;
const physical_device_group_count_max = 16;
const device_extension_count_max = 512;
const surface_format_count_max = 8;
const surface_present_mode_count_max = 8;
const swapchain_image_count_max = 8;
const shader_size_max = 2048;
const shader_count = 2;

fn initArray(comptime T: type, comptime size: usize, comptime value: T) [size]T {
    var array: [size]T = undefined;
    inline for (&array) |*elem| {
        elem.* = value;
    }
    return array;
}

fn err_check(result: c.VkResult) !void {
    if (result != c.VK_SUCCESS and result != c.VK_INCOMPLETE) {
        std.debug.print("vk error code {}\n", .{result});
        return error.VkError;
    }
}

fn err_check_allow_incomplete(result: c.VkResult) !void {
    if (result == c.VK_INCOMPLETE) {
        return;
    }
    return err_check(result);
}

pub const VulkanGfx = struct {
    instance_version: u32 = int_invalid,
    instance_extension_count: u32 = instance_extension_count_max,
    instance_extension: [instance_extension_count_max]c.VkExtensionProperties = undefined,
    instance_layer_count: u32 = instance_layer_count_max,
    instance_layer: [instance_layer_count_max]c.VkLayerProperties = undefined,
    instance: c.VkInstance = null,
    physical_device_count: u32 = physical_device_count_max,
    physical_device: [physical_device_count_max]c.VkPhysicalDevice = undefined,
    physical_device_properties: [physical_device_count_max]c.VkPhysicalDeviceProperties = undefined,
    physical_device_features: [physical_device_count_max]c.VkPhysicalDeviceFeatures = undefined,
    physical_device_index_gpu: usize = int_invalid,
    queue_family_count: u32 = queue_family_count_max,
    queue_family: [queue_family_count_max]c.VkQueueFamilyProperties = undefined,
    queue_family_index_all: u32 = int_invalid,
    physical_device_group_count: u32 = physical_device_group_count_max,
    physical_device_group: [physical_device_group_count_max]c.VkPhysicalDeviceGroupProperties = undefined,
    device_extension_count: u32 = device_extension_count_max,
    device_extension: [device_extension_count_max]c.VkExtensionProperties = undefined,
    device: c.VkDevice = null,
    surface: c.VkSurfaceKHR = null,
    surface_capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    surface_format_count: u32 = surface_format_count_max,
    surface_format: [surface_format_count_max]c.VkSurfaceFormatKHR = undefined,
    surface_format_index_bgra_srgb: usize = int_invalid,
    surface_present_mode_count: u32 = surface_format_count_max,
    surface_present_mode: [surface_present_mode_count_max]c.VkPresentModeKHR = undefined,
    surface_present_mode_index_fifo: usize = int_invalid,
    swapchain: c.VkSwapchainKHR = null,
    swapchain_image_count: u32 = swapchain_image_count_max,
    swapchain_image: [swapchain_image_count_max]c.VkImage = undefined,
    swapchain_image_view: [swapchain_image_count_max]c.VkImageView = undefined,
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
    pipeline_layout: c.VkPipelineLayout = null,
    render_pass: c.VkRenderPass = null,
    pipeline_graphics: c.VkPipeline = null,

    pub fn kill(self: VulkanGfx) void {
        c.vkDestroyPipeline(self.device, self.pipeline_graphics, null);
        c.vkDestroyRenderPass(self.device, self.render_pass, null);
        c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
        for (self.shader_module) |shader_module| {
            c.vkDestroyShaderModule(self.device, shader_module, null);
        }
        for (0..self.swapchain_image_count) |index| {
            c.vkDestroyImageView(self.device, self.swapchain_image_view[index], null);
        }
        c.vkDestroySwapchainKHR(self.device, self.swapchain, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroyInstance(self.instance, null);
    }

    pub fn update(_: VulkanGfx) void {}

    pub fn init(self: *VulkanGfx, ui: xcb.XcbUi) !void {
        std.debug.print("\n=== Vulkan ===\n", .{});

        // instance
        // DOCS: https://docs.vulkan.org/spec/latest/chapters/initialization.html#initialization-instances

        {
            // instance version
            {
                try err_check(c.vkEnumerateInstanceVersion(&self.instance_version));
                std.debug.assert(self.instance_version != int_invalid);

                std.debug.print("\nSupported API Version: {}.{}.{}\n", .{
                    c.VK_VERSION_MAJOR(self.instance_version),
                    c.VK_VERSION_MINOR(self.instance_version),
                    c.VK_VERSION_PATCH(self.instance_version),
                });
            }

            // instance extensions
            {
                try err_check_allow_incomplete(c.vkEnumerateInstanceExtensionProperties(
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

            // instance layers
            {
                try err_check_allow_incomplete(c.vkEnumerateInstanceLayerProperties(
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

            // instance
            {
                const application_info = c.VkApplicationInfo{
                    .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                    .pApplicationName = "Dwarfare",
                    .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
                    .pEngineName = "No Engine",
                    .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
                    .apiVersion = c.VK_MAKE_VERSION(1, 1, 0),
                };

                const instance_create_info = c.VkInstanceCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                    .pNext = null,
                    .pApplicationInfo = &application_info,
                    .enabledLayerCount = instance_layer_enable.len,
                    .ppEnabledLayerNames = &instance_layer_enable,
                    .enabledExtensionCount = instance_extension_enable.len,
                    .ppEnabledExtensionNames = &instance_extension_enable,
                };

                try err_check(c.vkCreateInstance(&instance_create_info, null, &self.instance));
                std.debug.assert(self.instance != null);
            }
        }

        // physical device
        // DOCS: https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html#devsandqueues-physical-device-enumeration

        {
            try err_check_allow_incomplete(c.vkEnumeratePhysicalDevices(
                self.instance,
                &self.physical_device_count,
                &self.physical_device,
            ));
            std.debug.assert(self.physical_device_count != 0);

            // fill
            for (0..self.physical_device_count) |index| {
                const physical_device = self.physical_device[index];
                c.vkGetPhysicalDeviceProperties(physical_device, &self.physical_device_properties[index]);
                c.vkGetPhysicalDeviceFeatures(physical_device, &self.physical_device_features[index]);
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

        // queue families
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
                    self.queue_family_index_all = @intCast(index);
                    break;
                }
            }
            std.debug.assert(self.queue_family_index_all != int_invalid);

            // print
            std.debug.print("\nAvailable Queue Families ({})\n", .{self.queue_family_count});
            for (0..self.queue_family_count) |index| {
                const queue_family = self.queue_family[index];
                std.debug.print("  - {b:9}{s}\n", .{
                    queue_family.queueFlags,
                    if (index == self.queue_family_index_all) " [Selected]" else "",
                });
            }
        }

        // NOTE: They're all size:1 on my computer, so I can't really test this out
        {
            try err_check_allow_incomplete(c.vkEnumeratePhysicalDeviceGroups(
                self.instance,
                &self.physical_device_group_count,
                &self.physical_device_group,
            ));
            std.debug.assert(self.physical_device_group_count != 0);

            std.debug.print("\nAvailable Physical Device Groups ({})\n", .{self.physical_device_group_count});
            for (0..self.physical_device_count) |index| {
                const physical_device_group = self.physical_device_group[index];
                std.debug.print("  - size:{}\n", .{physical_device_group.physicalDeviceCount});
            }
        }

        // device
        // DOCS: https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html#devsandqueues-devices

        var queue: c.VkQueue = null;
        const device_queue_index = 0;
        {
            // device extensions
            {
                try err_check_allow_incomplete(c.vkEnumerateDeviceExtensionProperties(
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

            // device
            {
                const device_queue_create_info = c.VkDeviceQueueCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .queueFamilyIndex = self.queue_family_index_all,
                    .queueCount = 1,
                    .pQueuePriorities = &@as(f32, 1.0),
                };

                const device_create_info = c.VkDeviceCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .queueCreateInfoCount = 1,
                    .pQueueCreateInfos = &device_queue_create_info,
                    .enabledLayerCount = 0,
                    .ppEnabledLayerNames = null,
                    .enabledExtensionCount = device_extension_enable.len,
                    .ppEnabledExtensionNames = &device_extension_enable,
                    .pEnabledFeatures = null,
                };

                try err_check(c.vkCreateDevice(
                    self.physical_device[self.physical_device_index_gpu],
                    &device_create_info,
                    null,
                    &self.device,
                ));
                std.debug.assert(self.device != null);
            }
        }

        // queue
        {
            c.vkGetDeviceQueue(
                self.device,
                self.queue_family_index_all,
                device_queue_index,
                &queue,
            );
            std.debug.assert(queue != null);
        }

        // surface
        {
            {
                var surface_create_info = c.VkXcbSurfaceCreateInfoKHR{
                    .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
                    .pNext = null,
                    .flags = 0,
                    .connection = @ptrCast(ui.connection),
                    .window = ui.window,
                };

                try err_check(c.vkCreateXcbSurfaceKHR(
                    self.instance,
                    &surface_create_info,
                    null,
                    &self.surface,
                ));
                std.debug.assert(self.surface != null);
            }

            {
                var support_present = c.VK_FALSE;
                try err_check(c.vkGetPhysicalDeviceSurfaceSupportKHR(
                    self.physical_device[self.physical_device_index_gpu],
                    self.queue_family_index_all,
                    self.surface,
                    &support_present,
                ));
                std.debug.assert(support_present != c.VK_FALSE);
            }

            {
                try err_check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
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

            {
                try err_check_allow_incomplete(c.vkGetPhysicalDeviceSurfaceFormatsKHR(
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

            {
                try err_check_allow_incomplete(c.vkGetPhysicalDeviceSurfacePresentModesKHR(
                    self.physical_device[self.physical_device_index_gpu],
                    self.surface,
                    &self.surface_present_mode_count,
                    &self.surface_present_mode,
                ));
                std.debug.assert(self.surface_present_mode_count != 0);

                for (0..self.surface_present_mode_count) |index| {
                    const present_mode = self.surface_present_mode[index];
                    if (present_mode == c.VK_PRESENT_MODE_FIFO_KHR) {
                        self.surface_present_mode_index_fifo = index;
                        break;
                    }
                }
                std.debug.assert(self.surface_present_mode_index_fifo != int_invalid);

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
                        if (index == self.surface_present_mode_index_fifo) " [Selected]" else "",
                    });
                }
            }
        }

        // swapchain
        // TODO: consider hi-DPI support
        {
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
                    .presentMode = self.surface_present_mode[self.surface_present_mode_index_fifo],
                    .clipped = c.VK_TRUE,
                    // TODO: recreate swapchain on resize
                    .oldSwapchain = null,
                };

                try err_check(c.vkCreateSwapchainKHR(
                    self.device,
                    &swapchain_create_info,
                    null,
                    &self.swapchain,
                ));
                std.debug.assert(self.swapchain != null);
            }

            {
                try err_check(c.vkGetSwapchainImagesKHR(
                    self.device,
                    self.swapchain,
                    &self.swapchain_image_count,
                    &self.swapchain_image,
                ));
                std.debug.assert(self.swapchain_image_count == image_count);
            }

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

                    try err_check(c.vkCreateImageView(
                        self.device,
                        &image_view_create_info,
                        null,
                        &self.swapchain_image_view[index],
                    ));
                    std.debug.assert(self.swapchain_image_view[index] != null);
                }
            }
        }

        // shaders
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
                    try err_check(c.vkCreateShaderModule(
                        self.device,
                        &shader_module_create_info,
                        null,
                        module,
                    ));
                    std.debug.assert(module.* != null);
                }
            }
        }

        // pipeline graphics
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

            const pipeline_vertex_input_state_create_info = c.VkPipelineVertexInputStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .vertexBindingDescriptionCount = 0,
                .pVertexBindingDescriptions = null,
                .vertexAttributeDescriptionCount = 0,
                .pVertexAttributeDescriptions = null,
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

            {
                const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .setLayoutCount = 0,
                    .pSetLayouts = null,
                    .pushConstantRangeCount = 0,
                    .pPushConstantRanges = null,
                };
                try err_check(c.vkCreatePipelineLayout(
                    self.device,
                    &pipeline_layout_create_info,
                    null,
                    &self.pipeline_layout,
                ));
                std.debug.assert(self.pipeline_layout != null);
            }

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

                const render_pass_create_info = c.VkRenderPassCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .attachmentCount = 1,
                    .pAttachments = &attachment_description_color,
                    .subpassCount = 1,
                    .pSubpasses = &subpass_description,
                    .dependencyCount = 0,
                    .pDependencies = null,
                };

                try err_check(c.vkCreateRenderPass(
                    self.device,
                    &render_pass_create_info,
                    null,
                    &self.render_pass,
                ));
                std.debug.assert(self.render_pass != null);
            }

            {
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

                try err_check(c.vkCreateGraphicsPipelines(
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

        // const viewport = c.VkViewport{
        //     .x = 0,
        //     .y = 0,
        //     .width = state.surface_capabilities.currentExtent.width,
        //     .height = state.surface_capabilities.currentExtent.height,
        //     .minDepth = 0,
        //     .maxDepth = 1,
        // };

        // const scissor = c.VkRect2D{
        //     .offset = c.VkOffset2D{ .x = 0, .y = 0 },
        //     .extent = state.surface_capabilities.currentExtent,
        // };
    }
};
