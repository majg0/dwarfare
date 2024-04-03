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

pub fn init() !VulkanGfx {
    var extensionCount: u32 = 0;
    _ = c.vkEnumerateInstanceExtensionProperties(null, &extensionCount, null);
    std.debug.print("Vulkan extension count: {}\n", .{extensionCount});

    const appInfo = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Dwarfare",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    const createInfo = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &appInfo,
    };

    var instance: c.VkInstance = undefined;
    if (c.vkCreateInstance(&createInfo, null, &instance) != c.VK_SUCCESS) {
        return error.VkCreateInstanceError;
    }

    return VulkanGfx{ .instance = instance };
}
