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

    when ODIN_DEBUG {
        fmt.println("debug enabled")
    }
    
    // Create GLFW Window
    glfw.Init();
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.WindowHint(glfw.RESIZABLE, 0);
    window := glfw.CreateWindow(1600, 900, "Vulkan Fun", nil, nil);

    // Get instance properties
    instanceLayerPropCount : u32 = 0;
    vk.EnumerateInstanceLayerProperties(&instanceLayerPropCount,nil)
    instanceLayerProps := make([]vk.LayerProperties,instanceLayerPropCount)
    defer delete(instanceLayerProps)
    vk.EnumerateInstanceLayerProperties(&instanceLayerPropCount, raw_data(instanceLayerProps))

    when ODIN_DEBUG {
        doesKHRValLayerExist := false
        for prop in &instanceLayerProps {
            layerName := strings.string_from_nul_terminated_ptr(&prop.layerName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE)
            fmt.println(layerName)
            doesKHRValLayerExist |= layerName == "VK_LAYER_KHRONOS_validation"
        }

        if(!doesKHRValLayerExist) {
            panic("VK_LAYER_KHRONOS_validation not found")
        }
    }

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
    createInfo.enabledLayerCount = 1
    layerKHRVal : cstring = "VK_LAYER_KHRONOS_validation"
    createInfo.ppEnabledLayerNames = &layerKHRVal

    requiredInstanceExtensions := glfw.GetRequiredInstanceExtensions();
    when ODIN_DEBUG {
        enabledExtensions := make([]cstring, len(requiredInstanceExtensions)+1)
        copy(enabledExtensions[:], requiredInstanceExtensions[:])
        enabledExtensions[len(enabledExtensions)-1] = "VK_EXT_debug_utils"
        createInfo.ppEnabledExtensionNames = raw_data(enabledExtensions);
        createInfo.enabledExtensionCount = u32(len(enabledExtensions));
    } else {
        createInfo.ppEnabledExtensionNames = raw_data(requiredInstanceExtensions);
        createInfo.enabledExtensionCount = u32(len(requiredInstanceExtensions));
    }
    
    // Create instance
    instance: vk.Instance
    if (vk.CreateInstance(&createInfo, nil, &instance) != vk.Result.SUCCESS) {
        fmt.println("Creating instance failed");
    }

    // Get the physical device
    deviceCount : u32 = 0;
    vk.EnumeratePhysicalDevices(instance, &deviceCount, nil);
    devices := make([]vk.PhysicalDevice, deviceCount)
    defer delete(devices)
    vk.EnumeratePhysicalDevices(instance, &deviceCount, &devices[0]);
    
    deviceProp : vk.PhysicalDeviceProperties
    deviceCurrent := devices[0]
    for device in devices {
        vk.GetPhysicalDeviceProperties(device, &deviceProp)
        if(deviceProp.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU) {
            deviceCurrent = device
        }
        when ODIN_DEBUG {
            fmt.println(strings.string_from_nul_terminated_ptr(&deviceProp.deviceName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE))
        }
    }

    // Main loop
    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents();
    }

    glfw.DestroyWindow(window);
    glfw.Terminate();
}