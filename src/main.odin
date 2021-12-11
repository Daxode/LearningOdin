package playing_with_vulkan

import vk "vendor:vulkan"
import "vendor:glfw"
import "core:fmt"

main::proc()
{
    glfw.Init();

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.WindowHint(glfw.RESIZABLE, 0);

    fmt.println("Vulkan Supported: ", glfw.VulkanSupported())

    window := glfw.CreateWindow(1600, 900, "Vulkan window", nil, nil);

    appInfo : vk.ApplicationInfo;
    appInfo.sType = vk.StructureType.APPLICATION_INFO;
    appInfo.pApplicationName = "Hello Triangle"
    appInfo.applicationVersion = vk.MAKE_VERSION(1,0,0)
    appInfo.pEngineName = "No Engine"
    appInfo.engineVersion = vk.MAKE_VERSION(1,0,0)
    appInfo.apiVersion = vk.API_VERSION_1_0;

    extensionCount : u32 = 0;
    //vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, nil);

    createInfo : vk.InstanceCreateInfo;
    createInfo.sType = vk.StructureType.INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    idk := glfw.GetRequiredInstanceExtensions();
    createInfo.ppEnabledExtensionNames = &idk[0];
    createInfo.enabledExtensionCount = u32(len(idk));

    instance := vk.Instance{}
    result  := vk.CreateInstance(&createInfo, nil, &instance)
    assert(result == vk.Result.SUCCESS)

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents();
    }

    glfw.DestroyWindow(window);

    glfw.Terminate();
}