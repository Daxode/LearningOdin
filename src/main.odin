package playing_with_vulkan

import vk "vendor:vulkan"
import "vendor:glfw"
import "core:fmt"
import "core:dynlib"
import "core:runtime"
import "core:strings"
import "vendor:stb/image"
import "core:c"
import "core:mem"

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
        
        w, h, channels: c.int
        icon_bytes := image.load("resources/DaxodeProfile.png",&w,&h, &channels, 0)
        icon := glfw.Image{w,h,icon_bytes}
        glfw.SetWindowIcon(windowHandle, []glfw.Image{icon})
        image.image_free(icon_bytes)
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
    surface_khr : vk.SurfaceKHR
    {
        resultCreateWindowSurface := glfw.CreateWindowSurface(vkInstance, windowHandle, nil, &surface_khr)
        when ODIN_DEBUG { 
            if (resultCreateWindowSurface != vk.Result.SUCCESS) {
                panic("Creating instance failed")
            }
        }
    }

    // Pick the physical device
    devicePicked: vk.PhysicalDevice
    famIndexGraphics : u32
    famIndexPresentation : u32
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

            QueueFamilySupports :: distinct bit_set[QueueFamilySupport; u8]
            QueueFamilySupport :: enum u8 {GRAPHICS, PRESENTATION}
            qFamiliesSupported : QueueFamilySupports
            for qFamily, i in qFamilies {
                index := u32(i)
                if vk.QueueFlag.GRAPHICS in qFamily.queueFlags {
                    famIndexGraphics = index
                    qFamiliesSupported |= {.GRAPHICS}
                }

                presentSupport : b32 = false
                vk.GetPhysicalDeviceSurfaceSupportKHR(device, index, surface_khr, &presentSupport)
                if (presentSupport) {
                    famIndexPresentation = index
                    qFamiliesSupported |= {.PRESENTATION}
                }
            }

            // Calculate Score
            if deviceProp.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU {
                deviceCurrentScore += 1000
            }

            deviceCurrentScore += deviceProp.limits.maxImageDimension2D;

            // Disable score
            deviceCurrentScore *= u32(deviceFeature.geometryShader)
            deviceCurrentScore *= u32(qFamiliesSupported == {.GRAPHICS, .PRESENTATION})

            when ODIN_DEBUG {    
                // Check for device extension support
                device_extension_count: u32
                vk.EnumerateDeviceExtensionProperties(device, nil, &device_extension_count, nil)
                device_extensions := make([]vk.ExtensionProperties, device_extension_count)
                vk.EnumerateDeviceExtensionProperties(device, nil, &device_extension_count, raw_data(device_extensions))
                
                swapchain_present := false
                for device_extension in &device_extensions {
                    swapchain_present |= cstring(&device_extension.extensionName[0]) == cstring("VK_KHR_swapchain")
                }
                deviceCurrentScore *= u32(swapchain_present)

                // Check Device Surface
                surface_capabilities: vk.SurfaceCapabilitiesKHR
                vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface_khr, &surface_capabilities)

                format_count: u32
                vk.GetPhysicalDeviceSurfaceFormatsKHR(device,surface_khr,&format_count,nil)
                present_mode_count: u32
                vk.GetPhysicalDeviceSurfacePresentModesKHR(device,surface_khr,&present_mode_count,nil)

                present_mode_size := size_of(vk.PresentModeKHR)   * present_mode_count
                format_size  := size_of(vk.SurfaceFormatKHR) * format_count
                surface_present_and_format_buffer, _ := mem.alloc_bytes(int(present_mode_size + format_size))
                present_mode_buffer := mem.slice_data_cast([]vk.PresentModeKHR,   surface_present_and_format_buffer[:present_mode_size])
                format_buffer  := mem.slice_data_cast([]vk.SurfaceFormatKHR, surface_present_and_format_buffer[present_mode_size:])

                vk.GetPhysicalDeviceSurfaceFormatsKHR(device,surface_khr,&format_count,raw_data(format_buffer))
                vk.GetPhysicalDeviceSurfacePresentModesKHR(device,surface_khr,&present_mode_count,raw_data(present_mode_buffer))

                for format in format_buffer {
                    fmt.println(format)
                }

                for present_mode in present_mode_buffer {
                    fmt.println(present_mode)
                }
            }

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
        u32set :: bit_set[u32(0)..<u32(32);u32]
        famIndexSet := u32set{famIndexGraphics, famIndexPresentation}

        // Setup Queue Device CreateInfo
        queuePriority : f32 = 1
        deviceQCreateInfos := make([dynamic]vk.DeviceQueueCreateInfo,0,4)
        defer delete(deviceQCreateInfos)
        for famIndex in u32(0)..<u32(32) {
            if !(famIndex in famIndexSet) {continue}
            append(&deviceQCreateInfos, vk.DeviceQueueCreateInfo {
                sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
                queueFamilyIndex = famIndex,
                queueCount = 1,
                pQueuePriorities = &queuePriority,
            })
        }

        // Create Logical Device
        deviceFeature : vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceFeatures(devicePicked, &deviceFeature)
        swapchain_extension_name: cstring = "VK_KHR_swapchain"
        deviceCreateInfo := vk.DeviceCreateInfo {
            sType = vk.StructureType.DEVICE_CREATE_INFO,
            queueCreateInfoCount = u32(len(deviceQCreateInfos)),
            pQueueCreateInfos = raw_data(deviceQCreateInfos),
            pEnabledFeatures = &deviceFeature,
            enabledExtensionCount = 1,
            ppEnabledExtensionNames = &swapchain_extension_name,
        }

        when ODIN_DEBUG {
            deviceCreateInfo.enabledLayerCount = 1
            layerKHRVal: cstring = "VK_LAYER_KHRONOS_validation"
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
        vk.GetDeviceQueue(logicalDevice, famIndexGraphics, 0, &graphicsQ)
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
    vk.DestroySurfaceKHR(vkInstance, surface_khr, nil)
    vk.DestroyInstance(vkInstance, nil)
    glfw.DestroyWindow(windowHandle);
    glfw.Terminate();
}