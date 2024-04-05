const std = @import("std");
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

const VulkanGfx = struct {
    instance: c.VkInstance,

    pub fn kill(self: VulkanGfx) void {
        c.vkDestroyInstance(self.instance, null);
    }
};

fn errCheck(result: c.VkResult) !void {
    if (result != c.VK_SUCCESS) {
        return error.VkError;
    }
}

pub fn init() !VulkanGfx {
    std.debug.print("=== Vulkan ===\n", .{});

    // TODO: move this out to a global pre-alloc
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const appInfo = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Dwarfare",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    // instance extensions
    {
        var extensionCount: u32 = 0;
        try errCheck(c.vkEnumerateInstanceExtensionProperties(null, &extensionCount, null));
        std.debug.print("Available Instance Extensions ({}):\n", .{extensionCount});

        const extensions = try allocator.alloc(c.VkExtensionProperties, extensionCount);
        try errCheck(c.vkEnumerateInstanceExtensionProperties(null, &extensionCount, extensions.ptr));

        for (extensions) |extension| {
            std.debug.print("- {s}\n", .{extension.extensionName});
        }
    }

    // instance layers
    {
        var layerCount: u32 = 0;
        try errCheck(c.vkEnumerateInstanceLayerProperties(&layerCount, null));
        std.debug.print("Available Instance Layers ({}):\n", .{layerCount});

        const layers = try allocator.alloc(c.VkLayerProperties, layerCount);
        try errCheck(c.vkEnumerateInstanceLayerProperties(&layerCount, layers.ptr));

        for (layers) |layer| {
            std.debug.print("- {s} ({s})\n", .{ layer.layerName, layer.description });
        }
    }

    // instance
    const instance = instance: {
        const instanceCreateInfo = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &appInfo,
        };

        var instance: c.VkInstance = null;
        try errCheck(c.vkCreateInstance(&instanceCreateInfo, null, &instance));

        break :instance instance;
    };

    // physical device
    var physicalDeviceCount: u32 = 0;
    try errCheck(c.vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, null));

    const physicalDevices = try allocator.alloc(c.VkPhysicalDevice, physicalDeviceCount);
    try errCheck(c.vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, physicalDevices.ptr));

    std.debug.print("Available Physical Devices ({})\n", .{physicalDeviceCount});
    for (physicalDevices) |physicalDevice| {
        var physicalDeviceProperties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(physicalDevice, &physicalDeviceProperties);

        std.debug.print("- {s} ({s})\n", .{ physicalDeviceProperties.deviceName, vkPhysicalDeviceTypeName(physicalDeviceProperties.deviceType) });

        var physicalDeviceFeatures: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceFeatures(physicalDevice, &physicalDeviceFeatures);
    }

    return VulkanGfx{ .instance = instance };
}

fn vkPhysicalDeviceTypeName(physicalDeviceType: c.VkPhysicalDeviceType) []const u8 {
    return switch (physicalDeviceType) {
        c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "Integrated GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "Discrete GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "Virtual GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_CPU => "CPU",
        else => "Unknown",
    };
}
