package playing_with_vulkan

import vk "vendor:vulkan"
import "vendor:glfw"
import "core:fmt"
import "core:dynlib"
import "core:runtime"
import "core:strings"

load_vulkan_function_pointers::proc()
{
    lib, ok := dynlib.load_library("vulkan-1.dll", true);
    assert(ok);

    context.user_ptr = &lib;

    vk.load_proc_addresses(proc(p: rawptr, name: cstring) {
        lib := (cast(^dynlib.Library)context.user_ptr)^;

        ptr, found := dynlib.symbol_address(lib, runtime.cstring_to_string(name));
        if !found {
            return;
        }

        casted := cast(^rawptr)p;
        casted^ = ptr;
    });
}

main::proc()
{
    load_vulkan_function_pointers()

    count : u32 = 0;
    vk.EnumerateInstanceExtensionProperties(nil,&count,nil)

    when ODIN_DEBUG {
        fmt.println("debug enabled")
    } else {
        count = 666
    }
    
    // Create GLFW Window
    glfw.Init();
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.WindowHint(glfw.RESIZABLE, 0);
    window := glfw.CreateWindow(1600, 900, strings.clone_to_cstring(fmt.aprintf("Instance Extension Properties: {}", count)), nil, nil);

    // Create App Info
    appInfo : vk.ApplicationInfo;
    appInfo.sType = vk.StructureType.APPLICATION_INFO;
    appInfo.pApplicationName = "Hello Triangle"
    appInfo.applicationVersion = vk.MAKE_VERSION(1,0,0)
    appInfo.pEngineName = "No Engine"
    appInfo.engineVersion = vk.MAKE_VERSION(1,0,0)
    appInfo.apiVersion = vk.API_VERSION_1_0;
    

    // Create Create Info
    createInfo : vk.InstanceCreateInfo;
    createInfo.sType = vk.StructureType.INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    idk := glfw.GetRequiredInstanceExtensions();
    createInfo.ppEnabledExtensionNames = &idk[0];
    createInfo.enabledExtensionCount = u32(len(idk));
    
    // Create instance
    instance: vk.Instance
    if (vk.CreateInstance(&createInfo, nil, &instance) != vk.Result.SUCCESS) {
        fmt.println("Creating instance failed");
    }

    deviceCount : u32 = 0;
    vk.EnumeratePhysicalDevices(instance, &deviceCount, nil);
    fmt.println(deviceCount)

    devices := make([^]vk.PhysicalDevice, deviceCount)
    vk.EnumeratePhysicalDevices(instance, &deviceCount, devices);

    for i in 0..<deviceCount {
        deviceProp : vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(devices[i], &deviceProp)
        fmt.println(strings.string_from_nul_terminated_ptr(cast(^u8)&deviceProp.deviceName,256))
    }

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents();
    }

    glfw.DestroyWindow(window);

    glfw.Terminate();
}