package playing_with_vulkan

import vk "vendor:vulkan"
import "vendor:glfw"
import "core:fmt"
import "core:dynlib"
import "core:runtime"

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
    // Create GLFW Window
    glfw.Init();
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.WindowHint(glfw.RESIZABLE, 0);
    window := glfw.CreateWindow(1600, 900, "Vulkan window", nil, nil);

    count : u32 = 0;
    vk.EnumerateInstanceExtensionProperties(nil,&count,nil)
    fmt.println("Instance Extension Properties: ", count)

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
    result  := vk.CreateInstance(&createInfo, nil, &instance)
    assert(result == vk.Result.SUCCESS)

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents();
    }

    glfw.DestroyWindow(window);

    glfw.Terminate();
}