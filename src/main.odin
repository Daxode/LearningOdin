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

    // Check validation layers
    {        
        when ODIN_DEBUG {
            layerCount : u32 = 0;
            vk.EnumerateInstanceLayerProperties(&layerCount,nil)
            supportedLayers := make([]vk.LayerProperties, layerCount)
            defer delete(supportedLayers)
            vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(supportedLayers))
            
            doesKHRValLayerExist := false
            for layer in &supportedLayers {
                layerName := strings.string_from_nul_terminated_ptr(&layer.layerName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE)
                fmt.println(layerName)
                doesKHRValLayerExist |= layerName == "VK_LAYER_KHRONOS_validation"
            }

            if(!doesKHRValLayerExist) {
                panic("VK_LAYER_KHRONOS_validation not found")
            }
        }
    }

    // Create App Info
    appInfo := vk.ApplicationInfo {
        sType = vk.StructureType.APPLICATION_INFO,
        pApplicationName = "Hello Triangle",
        applicationVersion = vk.MAKE_VERSION(1,0,0),
        pEngineName = "No Engine",
        engineVersion = vk.MAKE_VERSION(1,0,0),
        apiVersion = vk.API_VERSION_1_0,
    }

    // Create Instance and External Debug Messenger
    instance: vk.Instance
    debugMessengerEXT: vk.DebugUtilsMessengerEXT
    {
        createInfo : vk.InstanceCreateInfo;
        createInfo.sType = vk.StructureType.INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo = &appInfo;
        createInfo.enabledLayerCount = 1
        layerKHRVal : cstring = "VK_LAYER_KHRONOS_validation"
        createInfo.ppEnabledLayerNames = &layerKHRVal

        requiredInstanceExtensions := glfw.GetRequiredInstanceExtensions();
        when ODIN_DEBUG {
            enabledExtensions := make([]cstring, len(requiredInstanceExtensions)+1)
            defer delete(enabledExtensions)
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
        resultCreateInstance := vk.CreateInstance(&createInfo, nil, &instance)
        when ODIN_DEBUG { 
            if (resultCreateInstance != vk.Result.SUCCESS) {
                panic("Creating instance failed");
            }
        }

        when ODIN_DEBUG {
            CreateDebugUtilsMessengerEXT := vk.ProcCreateDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
            if (CreateDebugUtilsMessengerEXT != nil) {
                CreateDebugUtilsMessengerEXT(instance, &debugCreateInfo, nil, &debugMessengerEXT)
            } else {
                panic("vk.Result.ERROR_EXTENSION_NOT_PRESENT");
            }
        }
    }

    // Pick the physical device
    devicePicked: vk.PhysicalDevice
    {
        deviceCount : u32 = 0;
        vk.EnumeratePhysicalDevices(instance, &deviceCount, nil)
        devices := make([]vk.PhysicalDevice, deviceCount)
        defer delete(devices)
        vk.EnumeratePhysicalDevices(instance, &deviceCount, &devices[0])
        
        deviceBestScore : u32 = 0
        for device in devices {
            deviceCurrentScore : u32 = 0
            
            deviceProp : vk.PhysicalDeviceProperties
            vk.GetPhysicalDeviceProperties(device, &deviceProp)
            deviceFeature : vk.PhysicalDeviceFeatures
            vk.GetPhysicalDeviceFeatures(device, &deviceFeature)
            
            if deviceProp.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU {
                deviceCurrentScore += 1000
            }

            deviceCurrentScore += deviceProp.limits.maxImageDimension2D;

            deviceCurrentScore *= u32(deviceFeature.geometryShader)

            if deviceCurrentScore > deviceBestScore {
                devicePicked = device
                deviceBestScore = deviceCurrentScore
            }

            when ODIN_DEBUG {
                fmt.println(strings.string_from_nul_terminated_ptr(&deviceProp.deviceName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE))
            }
        }

        when ODIN_DEBUG {
            deviceProp : vk.PhysicalDeviceProperties
            vk.GetPhysicalDeviceProperties(devicePicked, &deviceProp)
            fmt.println("GPU found: ", strings.string_from_nul_terminated_ptr(&deviceProp.deviceName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE))
        }
    }
    
    // Create Logical Device
    graphicsFamIndex : Maybe(u32)
    {
        // Get Queue Family indicies
        qFamilyCount : u32 = 0
        vk.GetPhysicalDeviceQueueFamilyProperties(devicePicked, &qFamilyCount, nil)
        qFamilies := make([]vk.QueueFamilyProperties, qFamilyCount)
        defer delete(qFamilies)
        vk.GetPhysicalDeviceQueueFamilyProperties(devicePicked, &qFamilyCount, raw_data(qFamilies))
        for qFamily, i in qFamilies {
            if vk.QueueFlag.GRAPHICS in qFamily.queueFlags {
                graphicsFamIndex = u32(i)
            }
        }

        // Create Queue Device CreateInfo
        queuePriority : f32 = 1
        deviceQCreateInfo := vk.DeviceQueueCreateInfo {
            sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = graphicsFamIndex.?,
            queueCount = 1,
            pQueuePriorities = &queuePriority,
        }

        // Create Logical Device
        deviceFeature : vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceFeatures(devicePicked, &deviceFeature)
        deviceCreateInfo : vk.DeviceCreateInfo
        deviceCreateInfo.sType = vk.StructureType.DEVICE_CREATE_INFO
    }

    // Create GLFW Window
    window: glfw.WindowHandle
    {
        glfw.Init();
        glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
        glfw.WindowHint(glfw.RESIZABLE, 0);
        window = glfw.CreateWindow(1600, 900, "Vulkan Fun", nil, nil);
    }

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