const std = @import("std");
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

// DOCS: https://docs.vulkan.org/spec/latest/index.html

const VulkanGfx = struct {
    const State = struct {
        const instance_extension_count_max = 64;
        const instance_layer_count_max = 64;
        const physical_device_count_max = 8;
        const queue_family_count_max = 16;
        const physical_device_group_count_max = 16;
        const device_extension_count_max = 512;
        const device_layer_count_max = 16;

        instance_version: u32 = 0,
        instance_extension_count: u32 = instance_extension_count_max,
        instance_extension: [instance_extension_count_max]c.VkExtensionProperties = undefined,
        instance_layer_count: u32 = instance_layer_count_max,
        instance_layer: [instance_layer_count_max]c.VkLayerProperties = undefined,
        instance: c.VkInstance = null,
        physical_device_count: u32 = physical_device_count_max,
        physical_device: [physical_device_count_max]c.VkPhysicalDevice = undefined,
        physical_device_properties: [physical_device_count_max]c.VkPhysicalDeviceProperties = undefined,
        physical_device_features: [physical_device_count_max]c.VkPhysicalDeviceFeatures = undefined,
        physical_device_gpu_main_index: usize = 0,
        // TODO: this is per physical device, so should be stored differently
        queue_family_count: u32 = queue_family_count_max,
        queue_family: [queue_family_count_max]c.VkQueueFamilyProperties = undefined,
        physical_device_group_count: u32 = physical_device_group_count_max,
        physical_device_group: [physical_device_group_count_max]c.VkPhysicalDeviceGroupProperties = undefined,
        device_extension_count: u32 = device_extension_count_max,
        device_extension: [device_extension_count_max]c.VkExtensionProperties = undefined,
        device: c.VkDevice = null,
    };

    state: State,

    // TODO: make better
    queue_family_main_gpu_index: u32,

    pub fn kill(self: VulkanGfx) void {
        c.vkDestroyDevice(self.state.device, null);
        c.vkDestroyInstance(self.state.instance, null);
    }

    pub fn update(_: VulkanGfx) void {}
};

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

pub fn init() !VulkanGfx {
    std.debug.print("\n=== Vulkan ===\n", .{});

    var state = VulkanGfx.State{};

    // instance
    // DOCS: https://docs.vulkan.org/spec/latest/chapters/initialization.html#initialization-instances

    {
        // instance version
        {
            try err_check(c.vkEnumerateInstanceVersion(&state.instance_version));
            std.debug.print("\nSupported API Version: {}.{}.{}\n", .{
                c.VK_VERSION_MAJOR(state.instance_version),
                c.VK_VERSION_MINOR(state.instance_version),
                c.VK_VERSION_PATCH(state.instance_version),
            });
        }

        // instance extensions
        {
            try err_check_allow_incomplete(c.vkEnumerateInstanceExtensionProperties(
                null,
                &state.instance_extension_count,
                &state.instance_extension[0],
            ));

            std.debug.print("\nAvailable Instance Extensions ({}):\n", .{state.instance_extension_count});
            for (0..state.instance_extension_count) |index| {
                const extension = state.instance_extension[index];
                std.debug.print("- {s} (v{})\n", .{
                    extension.extensionName,
                    extension.specVersion,
                });
            }
        }

        // instance layers
        {
            try err_check_allow_incomplete(c.vkEnumerateInstanceLayerProperties(
                &state.instance_layer_count,
                &state.instance_layer[0],
            ));

            std.debug.print("\nAvailable Instance Layers ({}):\n", .{state.instance_layer_count});
            for (0..state.instance_layer_count) |index| {
                const layer = state.instance_layer[index];
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
                .pApplicationInfo = &application_info,
            };

            try err_check(c.vkCreateInstance(&instance_create_info, null, &state.instance));
        }
    }

    // physical device
    // DOCS: https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html#devsandqueues-physical-device-enumeration

    {
        try err_check_allow_incomplete(c.vkEnumeratePhysicalDevices(
            state.instance,
            &state.physical_device_count,
            &state.physical_device[0],
        ));

        // fill structures
        for (0..state.physical_device_count) |index| {
            const physical_device = state.physical_device[index];
            c.vkGetPhysicalDeviceProperties(physical_device, &state.physical_device_properties[index]);
            c.vkGetPhysicalDeviceFeatures(physical_device, &state.physical_device_features[index]);
        }

        // find main gpu
        for (0..state.physical_device_count) |index| {
            const properties = state.physical_device_properties[index];
            if (properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                state.physical_device_gpu_main_index = index;
                break;
            }
        }

        std.debug.print("\nAvailable Physical Devices ({})\n", .{state.physical_device_count});
        for (0..state.physical_device_count) |index| {
            const properties = state.physical_device_properties[index];
            std.debug.print("- {s} ({s}){s}\n", .{
                properties.deviceName,
                switch (properties.deviceType) {
                    c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "Integrated GPU",
                    c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "Discrete GPU",
                    c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "Virtual GPU",
                    c.VK_PHYSICAL_DEVICE_TYPE_CPU => "CPU",
                    else => "Unknown",
                },
                if (index == state.physical_device_gpu_main_index) " [Selected GPU]" else "",
            });
        }
    }

    // queue families
    var queue_family_main_gpu: ?c.VkQueueFamilyProperties = null;
    var queue_family_main_gpu_index: u32 = 0;
    {
        c.vkGetPhysicalDeviceQueueFamilyProperties(
            state.physical_device[state.physical_device_gpu_main_index],
            &state.queue_family_count,
            &state.queue_family[0],
        );

        std.debug.print("\nAvailable Queue Families ({})\n", .{state.queue_family_count});
        for (0..state.queue_family_count) |index| {
            const queue_family = state.queue_family[index];
            const mask = c.VK_QUEUE_GRAPHICS_BIT | c.VK_QUEUE_COMPUTE_BIT | c.VK_QUEUE_TRANSFER_BIT;
            const select = queue_family_main_gpu == null and (queue_family.queueFlags & mask) != 0;
            if (select) {
                queue_family_main_gpu = queue_family;
                queue_family_main_gpu_index = @intCast(index);
            }
            std.debug.print("  - {b:9}{s}\n", .{
                queue_family.queueFlags,
                if (select) " [Selected]" else "",
            });
        }
    }
    std.debug.assert(queue_family_main_gpu != null);

    // NOTE: I don't have a computer supporting groups, they're all size:1, so can't really test this out
    {
        try err_check_allow_incomplete(c.vkEnumeratePhysicalDeviceGroups(
            state.instance,
            &state.physical_device_group_count,
            &state.physical_device_group[0],
        ));

        std.debug.print("\nAvailable Physical Device Groups ({})\n", .{state.physical_device_group_count});
        for (0..state.physical_device_count) |index| {
            const physical_device_group = state.physical_device_group[index];
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
                state.physical_device[state.physical_device_gpu_main_index],
                null,
                &state.device_extension_count,
                &state.device_extension[0],
            ));

            std.debug.print("\nAvailable Device Extensions ({}):\n", .{state.device_extension_count});
            for (0..state.device_extension_count) |index| {
                const extension = state.device_extension[index];
                // TODO: not sure why names end with �
                std.debug.print("- {s} (v{})\n", .{
                    extension.extensionName,
                    extension.specVersion,
                });
            }
        }

        // device & queue
        {
            const device_queue_create_info = c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueFamilyIndex = queue_family_main_gpu_index,
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
                .enabledExtensionCount = 0,
                .ppEnabledExtensionNames = null,
                .pEnabledFeatures = null,
            };
            try err_check(c.vkCreateDevice(
                state.physical_device[state.physical_device_gpu_main_index],
                &device_create_info,
                null,
                &state.device,
            ));
            c.vkGetDeviceQueue(
                state.device,
                queue_family_main_gpu_index,
                device_queue_index,
                &queue,
            );
        }
    }
    std.debug.assert(state.device != null);
    std.debug.assert(queue != null);

    return VulkanGfx{
        .state = state,
        .queue_family_main_gpu_index = queue_family_main_gpu_index,
    };
}
