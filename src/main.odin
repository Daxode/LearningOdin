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
    windowHandle: glfw.WindowHandle
    {
        glfw.Init();
        glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
        glfw.WindowHint(glfw.RESIZABLE, 0);
        windowHandle = glfw.CreateWindow(1600, 900, "Vulkan Fun", nil, nil);
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
    vkInstance: vk.Instance
    when ODIN_DEBUG {debugMessengerEXT: vk.DebugUtilsMessengerEXT}
    {
        createInfo : vk.InstanceCreateInfo;
        createInfo.sType = vk.StructureType.INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo = &appInfo;
        when ODIN_DEBUG {
            createInfo.enabledLayerCount = 1
            layerKHRVal : cstring = "VK_LAYER_KHRONOS_validation"
            createInfo.ppEnabledLayerNames = &layerKHRVal
        }

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
            debugCreateInfo := vk.DebugUtilsMessengerCreateInfoEXT {
                sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
                messageType = {.GENERAL, .VALIDATION, .PERFORMANCE},
                pfnUserCallback = vk.ProcDebugUtilsMessengerCallbackEXT(proc(
                    msgSeverity: vk.DebugUtilsMessageSeverityFlagsEXT, msgTypes: vk.DebugUtilsMessageTypeFlagsEXT, 
                    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT, pUserData: rawptr) {
                        severityString := ""
                        if .VERBOSE in msgSeverity {
                            severityString = "VK[V]:"
                        } else if .INFO in msgSeverity {
                            severityString = "VK[I]:"
                        } else if .WARNING in msgSeverity {
                            severityString = "VK[W]:"
                        } else if .ERROR in msgSeverity {
                            severityString = "VK[E]:"
                        }

                        fmt.println(severityString, pCallbackData^.pMessage)
                    }),
            }

            createInfo.pNext = cast(rawptr) &debugCreateInfo
        }

        // Create instance
        resultCreateInstance := vk.CreateInstance(&createInfo, nil, &vkInstance)
        when ODIN_DEBUG { 
            if (resultCreateInstance != vk.Result.SUCCESS) {
                panic("Creating Vulkan instance failed");
            }
        }

        when ODIN_DEBUG {
            CreateDebugUtilsMessengerEXT := vk.ProcCreateDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(vkInstance, "vkCreateDebugUtilsMessengerEXT"));
            if (CreateDebugUtilsMessengerEXT != nil) {
                CreateDebugUtilsMessengerEXT(vkInstance, &debugCreateInfo, nil, &debugMessengerEXT)
            } else {
                panic("vk.Result.ERROR_EXTENSION_NOT_PRESENT");
            }
        }
    }

    // Get window surface
    surfaceKHR : vk.SurfaceKHR
    {
        resultCreateWindowSurface := glfw.CreateWindowSurface(vkInstance, windowHandle, nil, &surfaceKHR)
        when ODIN_DEBUG { 
            if (resultCreateWindowSurface != vk.Result.SUCCESS) {
                panic("Creating instance failed")
            }
        }
    }

    // Pick the physical device
    devicePicked: vk.PhysicalDevice
    graphicsFamIndex : u32
    presentFamIndex : u32

    QueueFamilySupports :: distinct bit_set[QueueFamilySupport; u8]
    QueueFamilySupport :: enum u8 {GRAPHICS,PRESENTATION}
    qFamiliesSupports : []QueueFamilySupports
    defer delete(qFamilies)
    
    {
        // Retrieve Physical Devices
        deviceCount : u32 = 0;
        vk.EnumeratePhysicalDevices(vkInstance, &deviceCount, nil)
        devices := make([]vk.PhysicalDevice, deviceCount)
        defer delete(devices)
        vk.EnumeratePhysicalDevices(vkInstance, &deviceCount, &devices[0])
        
        // Get most suited device
        deviceBestScore : u32 = 0
        for device in devices {
            deviceCurrentScore : u32 = 0
            
            // Retrieve Device Data
            deviceProp : vk.PhysicalDeviceProperties
            vk.GetPhysicalDeviceProperties(device, &deviceProp)
            deviceFeature : vk.PhysicalDeviceFeatures
            vk.GetPhysicalDeviceFeatures(device, &deviceFeature)
            
            // Get Queue Family indicies
            qFamilyCount : u32 = 0
            vk.GetPhysicalDeviceQueueFamilyProperties(device, &qFamilyCount, nil)
            qFamilies := make([]vk.QueueFamilyProperties, qFamilyCount)
            vk.GetPhysicalDeviceQueueFamilyProperties(device, &qFamilyCount, raw_data(qFamilies))

            qFamiliesSupported : QueueFamilySupports
            qFamiliesSupports = make([]QueueFamilySupports, qFamilyCount)
            defer delete(supportsFounds)
            for qFamily, i in qFamilies {
                index := u32(i)
                if vk.QueueFlag.GRAPHICS in qFamily.queueFlags {
                    graphicsFamIndex = index
                    supportsFounds[i] |= {.GRAPHICS}
                }

                presentSupport : b32 = false
                vk.GetPhysicalDeviceSurfaceSupportKHR(device, index, surfaceKHR, &presentSupport)
                if (presentSupport) {
                    presentFamIndex = index
                    supportsFounds[i] |= {.PRESENTATION}
                }
                qFamiliesSupported |= supportsFounds[i]
            }

            // Calculate Score
            if deviceProp.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU {
                deviceCurrentScore += 1000
            }

            deviceCurrentScore += deviceProp.limits.maxImageDimension2D;

            deviceCurrentScore *= u32(deviceFeature.geometryShader)
            deviceCurrentScore *= u32(qFamiliesSupported == {.GRAPHICS, .PRESENTATION})

            // Resolve Score
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
    logicalDevice : vk.Device
    {
        // Setup Queue Device CreateInfo
        queuePriority : f32 = 1
        deviceQCreateInfo := vk.DeviceQueueCreateInfo {
            sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = graphicsFamIndex,
            queueCount = 1,
            pQueuePriorities = &queuePriority,
        }

        // Create Logical Device
        deviceFeature : vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceFeatures(devicePicked, &deviceFeature)
        deviceCreateInfo := vk.DeviceCreateInfo {
            sType = vk.StructureType.DEVICE_CREATE_INFO,
            queueCreateInfoCount = 1,
            pQueueCreateInfos = &deviceQCreateInfo,
            pEnabledFeatures = &deviceFeature,
        }

        when ODIN_DEBUG {
            deviceCreateInfo.enabledLayerCount = 1
            layerKHRVal : cstring = "VK_LAYER_KHRONOS_validation"
            deviceCreateInfo.ppEnabledLayerNames = &layerKHRVal
        }

        // Create instance
        resultCreateDevice := vk.CreateDevice(devicePicked, &deviceCreateInfo, nil, &logicalDevice)
        when ODIN_DEBUG { 
            if (resultCreateDevice != vk.Result.SUCCESS) {
                panic("Creating instance failed")
            }
        }
    }

    // Get Graphics Queue
    {
        graphicsQ : vk.Queue
        vk.GetDeviceQueue(logicalDevice, graphicsFamIndex, 0, &graphicsQ)
    }

    // Main loop
    for !glfw.WindowShouldClose(windowHandle) {
        glfw.PollEvents();
    }

    when ODIN_DEBUG {
        DestroyDebugUtilsMessengerEXT := vk.ProcDestroyDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(vkInstance, "vkDestroyDebugUtilsMessengerEXT"));
        if (DestroyDebugUtilsMessengerEXT != nil) {
            DestroyDebugUtilsMessengerEXT(vkInstance, debugMessengerEXT, nil);
        }
    }

    vk.DestroyDevice(logicalDevice, nil)
    vk.DestroySurfaceKHR(vkInstance, surfaceKHR, nil)
    vk.DestroyInstance(vkInstance, nil)
    glfw.DestroyWindow(windowHandle);
    glfw.Terminate();
}