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

    // Get layers
    layerCount : u32 = 0;
    vk.EnumerateInstanceLayerProperties(&layerCount,nil)
    layers := make([]vk.LayerProperties,layerCount)
    defer delete(layers)
    vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(layers))

    when ODIN_DEBUG {
        doesKHRValLayerExist := false
        for layer in &layers {
            layerName := strings.string_from_nul_terminated_ptr(&layer.layerName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE)
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

    // Create Debugger
    when ODIN_DEBUG {
        debugCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT
        debugCreateInfo.sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
        debugCreateInfo.messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR}
        debugCreateInfo.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
        debugCreateInfo.pfnUserCallback = vk.ProcDebugUtilsMessengerCallbackEXT(proc(
            messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT, messageTypes: vk.DebugUtilsMessageTypeFlagsEXT, 
            pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT, pUserData: rawptr) {
                fmt.println(pCallbackData^.pMessage)
        })

        createInfo.pNext = cast(rawptr) &debugCreateInfo
    }

    // Create instance
    instance: vk.Instance
    resultCreateInstance := vk.CreateInstance(&createInfo, nil, &instance)
    when ODIN_DEBUG { 
        if (resultCreateInstance != vk.Result.SUCCESS) {
            panic("Creating instance failed");
        }
    }
    
    when ODIN_DEBUG {
        debugMessengerEXT:vk.DebugUtilsMessengerEXT
        CreateDebugUtilsMessengerEXT := vk.ProcCreateDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
        if (CreateDebugUtilsMessengerEXT != nil) {
            CreateDebugUtilsMessengerEXT(instance, &debugCreateInfo, nil, &debugMessengerEXT)
        } else {
            panic("vk.Result.ERROR_EXTENSION_NOT_PRESENT");
        }
    }

    // Get the physical device
    deviceCount : u32 = 0;
    vk.EnumeratePhysicalDevices(instance, &deviceCount, nil);
    devices := make([]vk.PhysicalDevice, deviceCount)
    defer delete(devices)
    vk.EnumeratePhysicalDevices(instance, &deviceCount, &devices[0]);
    
    deviceProp : vk.PhysicalDeviceProperties
    deviceFeature : vk.PhysicalDeviceFeatures
    deviceBest : vk.PhysicalDevice
    deviceBestScore : u32 = 0
    for device in devices {
        deviceCurrentScore : u32 = 0
        vk.GetPhysicalDeviceProperties(device, &deviceProp)
        vk.GetPhysicalDeviceFeatures(device, &deviceFeature)
        if deviceProp.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU {
            deviceCurrentScore += 1000
        }

        deviceCurrentScore += deviceProp.limits.maxImageDimension2D;

        deviceCurrentScore *= u32(deviceFeature.geometryShader)

        if deviceCurrentScore > deviceBestScore {
            deviceBest = device
            deviceBestScore = deviceCurrentScore
        }

        when ODIN_DEBUG {
            fmt.println(strings.string_from_nul_terminated_ptr(&deviceProp.deviceName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE))
        }
    }

    when ODIN_DEBUG {
        vk.GetPhysicalDeviceProperties(deviceBest, &deviceProp)
        fmt.println("GPU found: ", strings.string_from_nul_terminated_ptr(&deviceProp.deviceName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE))
    }

    // Get Queue
    qFamilyCount : u32 = 0
    vk.GetPhysicalDeviceQueueFamilyProperties(deviceBest, &qFamilyCount, nil)
    qFamilies := make([]vk.QueueFamilyProperties, qFamilyCount)
    vk.GetPhysicalDeviceQueueFamilyProperties(deviceBest, &qFamilyCount, raw_data(qFamilies))
    graphicsFamIndex : Maybe(u32)
    for qFamily, i in qFamilies {
        if vk.QueueFlag.GRAPHICS in qFamily.queueFlags {
            graphicsFamIndex = u32(i)
        }
    }

    deviceQCreateInfo : vk.DeviceQueueCreateInfo
    deviceQCreateInfo.sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO
    deviceQCreateInfo.queueFamilyIndex = graphicsFamIndex.?
    deviceQCreateInfo.queueCount = 1
    queuePriority : f32 = 1
    deviceQCreateInfo.pQueuePriorities = &queuePriority

    // Main loop
    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents();
    }

    when ODIN_DEBUG {
        DestroyDebugUtilsMessengerEXT := vk.ProcDestroyDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
        if (DestroyDebugUtilsMessengerEXT != nil) {
            DestroyDebugUtilsMessengerEXT(instance, debugMessengerEXT, nil);
        }
    }

    vk.DestroyInstance(instance, nil)
    glfw.DestroyWindow(window);
    glfw.Terminate();
}