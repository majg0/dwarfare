const std = @import("std");
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

// DOCS: https://docs.vulkan.org/spec/latest/index.html

const instance_extension_count_max = 64;
const instance_layer_count_max = 64;
const physical_device_count_max = 8;
const queue_family_count_max = 16;
const physical_device_group_count_max = 16;
const device_extension_count_max = 512;
const device_layer_count_max = 16;

const VulkanGfx = struct {
    instance: c.VkInstance,
    device: c.VkDevice,

    pub fn kill(self: VulkanGfx) void {
        c.vkDestroyDevice(self.device, null);
        c.vkDestroyInstance(self.instance, null);
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

    // instance
    // DOCS: https://docs.vulkan.org/spec/latest/chapters/initialization.html#initialization-instances

    var instance: c.VkInstance = null;
    {
        // instance version
        {
            var instance_version: u32 = 0;
            try err_check(c.vkEnumerateInstanceVersion(&instance_version));
            std.debug.print("Supported API Version: {}.{}.{}", .{
                c.VK_VERSION_MAJOR(instance_version),
                c.VK_VERSION_MINOR(instance_version),
                c.VK_VERSION_PATCH(instance_version),
            });
        }

        // instance extensions
        {
            var instance_extension_count: u32 = instance_extension_count_max;
            var instance_extension_buf: [instance_extension_count_max]c.VkExtensionProperties = undefined;
            try err_check_allow_incomplete(c.vkEnumerateInstanceExtensionProperties(
                null,
                &instance_extension_count,
                &instance_extension_buf[0],
            ));
            const instance_extensions = instance_extension_buf[0..instance_extension_count];

            std.debug.print("\nAvailable Instance Extensions ({}):\n", .{instance_extension_count});
            for (instance_extensions) |extension| {
                std.debug.print("- {s} (v{})\n", .{
                    extension.extensionName,
                    extension.specVersion,
                });
            }
        }

        // instance layers
        {
            var instance_layer_count: u32 = instance_layer_count_max;
            var instance_layer_buf: [instance_layer_count_max]c.VkLayerProperties = undefined;
            try err_check_allow_incomplete(c.vkEnumerateInstanceLayerProperties(
                &instance_layer_count,
                &instance_layer_buf[0],
            ));
            const instance_layers = instance_layer_buf[0..instance_layer_count];

            std.debug.print("\nAvailable Instance Layers ({}):\n", .{instance_layer_count});
            for (instance_layers) |instance_layer| {
                std.debug.print("- {s} ({s})\n", .{ instance_layer.layerName, instance_layer.description });
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

            const instanceCreateInfo = c.VkInstanceCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                .pApplicationInfo = &application_info,
            };

            try err_check(c.vkCreateInstance(&instanceCreateInfo, null, &instance));
        }
    }

    // physical device
    // DOCS: https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html#devsandqueues-physical-device-enumeration

    var physical_device_main_gpu: c.VkPhysicalDevice = null;
    {
        var physical_device_count: u32 = physical_device_count_max;
        var physical_device_buf: [physical_device_count_max]c.VkPhysicalDevice = undefined;
        try err_check_allow_incomplete(c.vkEnumeratePhysicalDevices(
            instance,
            &physical_device_count,
            &physical_device_buf[0],
        ));
        const physical_devices = physical_device_buf[0..physical_device_count];

        std.debug.print("\nAvailable Physical Devices ({})\n", .{physical_device_count});
        for (physical_devices) |physical_device| {
            var physical_device_properties: c.VkPhysicalDeviceProperties = undefined;
            c.vkGetPhysicalDeviceProperties(physical_device, &physical_device_properties);

            var physical_device_features: c.VkPhysicalDeviceFeatures = undefined;
            c.vkGetPhysicalDeviceFeatures(physical_device, &physical_device_features);

            const select_gpu =
                physical_device_main_gpu == null and
                physical_device_properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU;

            if (select_gpu) {
                physical_device_main_gpu = physical_device;
            }

            std.debug.print("- {s} ({s}){s}\n", .{
                physical_device_properties.deviceName,
                switch (physical_device_properties.deviceType) {
                    c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "Integrated GPU",
                    c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "Discrete GPU",
                    c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "Virtual GPU",
                    c.VK_PHYSICAL_DEVICE_TYPE_CPU => "CPU",
                    else => "Unknown",
                },
                if (select_gpu) " [Selected GPU]" else "",
            });
        }
    }
    std.debug.assert(physical_device_main_gpu != null);

    // queue families
    var queue_family_main_gpu: ?c.VkQueueFamilyProperties = null;
    {
        var queue_family_count: u32 = queue_family_count_max;
        var queue_family_buf: [queue_family_count_max]c.VkQueueFamilyProperties = undefined;
        c.vkGetPhysicalDeviceQueueFamilyProperties(
            physical_device_main_gpu,
            &queue_family_count,
            &queue_family_buf[0],
        );
        const queue_families = queue_family_buf[0..queue_family_count];

        std.debug.print("\nAvailable Queue Families ({})\n", .{queue_family_count});
        for (queue_families) |queue_family| {
            const mask = c.VK_QUEUE_GRAPHICS_BIT | c.VK_QUEUE_COMPUTE_BIT | c.VK_QUEUE_TRANSFER_BIT;
            const select = queue_family_main_gpu == null and (queue_family.queueFlags & mask) != 0;
            if (select) {
                queue_family_main_gpu = queue_family;
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
        var physical_device_group_count: u32 = physical_device_group_count_max;
        var physical_device_group_buf: [physical_device_group_count_max]c.VkPhysicalDeviceGroupProperties = undefined;
        try err_check_allow_incomplete(c.vkEnumeratePhysicalDeviceGroups(
            instance,
            &physical_device_group_count,
            &physical_device_group_buf[0],
        ));
        const physical_device_groups = physical_device_group_buf[0..physical_device_group_count];

        std.debug.print("\nAvailable Physical Device Groups ({})\n", .{physical_device_group_count});
        for (physical_device_groups) |physical_device_group| {
            std.debug.print("  - size:{}\n", .{physical_device_group.physicalDeviceCount});
        }
    }

    // device
    // DOCS: https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html#devsandqueues-devices

    var device: c.VkDevice = null;
    {
        // device extensions
        {
            var device_extension_count: u32 = device_extension_count_max;
            var device_extension_buf: [device_extension_count_max]c.VkExtensionProperties = undefined;
            try err_check_allow_incomplete(c.vkEnumerateDeviceExtensionProperties(
                physical_device_main_gpu,
                null,
                &device_extension_count,
                &device_extension_buf[0],
            ));
            const device_extensions = device_extension_buf[0..device_extension_count];

            std.debug.print("\nAvailable Device Extensions ({}):\n", .{device_extension_count});
            for (device_extensions) |extension| {
                // TODO: not sure why names end with �
                std.debug.print("- {s} (v{})\n", .{
                    extension.extensionName,
                    extension.specVersion,
                });
            }
        }

        // device
        {
            const device_create_info = c.VkDeviceCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueCreateInfoCount = 0,
                .pQueueCreateInfos = null,
                .enabledLayerCount = 0,
                .ppEnabledLayerNames = null,
                .enabledExtensionCount = 0,
                .ppEnabledExtensionNames = null,
                .pEnabledFeatures = null,
            };
            try err_check(c.vkCreateDevice(
                physical_device_main_gpu,
                &device_create_info,
                null,
                &device,
            ));
        }
    }
    std.debug.assert(device != null);

    return VulkanGfx{
        .instance = instance,
        .device = device,
    };
}
