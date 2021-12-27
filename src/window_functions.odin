package playing_with_vulkan

import "core:c"
import "core:fmt"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"
import "vendor:stb/image"

CreateWindowWithCallbacksAndIcon::proc() -> (window_handle: glfw.WindowHandle){
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.WindowHint(glfw.MAXIMIZED,0)
    window_handle = glfw.CreateWindow(512, 512, "Vulkan Fun", nil, nil);

    glfw.SetKeyCallback(window_handle, glfw.KeyProc(proc(window_handle: glfw.WindowHandle, key, scancode, action, mods: c.int){
        if action == glfw.PRESS {
            switch key {
                case glfw.KEY_F1:
                    //glfw.SetWindowMonitor()
                case glfw.KEY_ESCAPE:
                    glfw.SetWindowShouldClose(window_handle, true)
            }
        }
    }))

    glfw.SetFramebufferSizeCallback(window_handle, glfw.FramebufferSizeProc(proc(window_handle: glfw.WindowHandle, width, height: c.int){
        window_state := (^WindowState)(glfw.GetWindowUserPointer(window_handle))^
        fmt.println("Frame buffer size changed")
        vk.DeviceWaitIdle(window_state.logical_device)
    }))
    
    w, h, channels: c.int
    icon_bytes := image.load("resources/DaxodeProfile.png",&w,&h, &channels, 0)
    icon := glfw.Image{w,h,icon_bytes}
    glfw.SetWindowIcon(window_handle, []glfw.Image{icon})
    image.image_free(icon_bytes)

    return
}

CheckVulkanInstanceExistence :: proc() -> (exists: VulkanInstanceExists) {
    layer_count : u32 = 0;
    vk.EnumerateInstanceLayerProperties(&layer_count,nil)
    supported_layers := make([]vk.LayerProperties, layer_count, context.temp_allocator)
    defer delete(supported_layers, context.temp_allocator)
    vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(supported_layers))
    for layer in &supported_layers {
        exists.exists_vk_layer_khr_validation |= cstring(&layer.layerName[0]) == cstring("VK_LAYER_KHRONOS_validation")
    }

    extension_count : u32 = 0;
    vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
    supported_extensions := make([]vk.ExtensionProperties, extension_count, context.temp_allocator)
    defer delete(supported_extensions, context.temp_allocator)
    vk.EnumerateInstanceExtensionProperties(nil, &extension_count, raw_data(supported_extensions))
    for extension in &supported_extensions {
        exists.exists_vk_ext_debug_utils |= cstring(&extension.extensionName[0]) == cstring("VK_EXT_debug_utils")
    }

    fmt.println("VK_LAYER_KHRONOS_validation exists:", exists.exists_vk_layer_khr_validation,
                "|",
                "VK_EXT_debug_utils exists:", exists.exists_vk_ext_debug_utils)
    
    return
}

// Vulkan instance exits can be nil in release, Remember to destroy instance, and debugmessenger in debugmode
CreateVulkanInstanceWithDebugMSG :: proc(application_info: ^vk.ApplicationInfo, exists: ^VulkanInstanceExists) -> (instance: vk.Instance, debugMessengerEXT: vk.DebugUtilsMessengerEXT) {
    instance_createinfo := vk.InstanceCreateInfo{
        sType = vk.StructureType.INSTANCE_CREATE_INFO,
        pApplicationInfo = application_info,
    }
    
    when ODIN_DEBUG {
        if exists.exists_vk_layer_khr_validation {
            instance_createinfo.enabledLayerCount = 1
            layerKHRVal : cstring = "VK_LAYER_KHRONOS_validation"
            instance_createinfo.ppEnabledLayerNames = &layerKHRVal
        }
    }

    required_instance_extensions := glfw.GetRequiredInstanceExtensions();
    when ODIN_DEBUG {
        enabled_extensions: []cstring
        defer if exists.exists_vk_ext_debug_utils{delete(enabled_extensions, context.temp_allocator)} 
        // Append VK_EXT_debug_utils to list of required_instance_extensions
        if exists.exists_vk_ext_debug_utils {
            enabled_extensions := make([]cstring, len(required_instance_extensions)+1, context.temp_allocator)
            copy(enabled_extensions[:], required_instance_extensions[:])
            enabled_extensions[len(enabled_extensions)-1] = "VK_EXT_debug_utils"
            instance_createinfo.ppEnabledExtensionNames = raw_data(enabled_extensions);
            instance_createinfo.enabledExtensionCount = u32(len(enabled_extensions));
        } else {
            instance_createinfo.ppEnabledExtensionNames = raw_data(required_instance_extensions);
            instance_createinfo.enabledExtensionCount = u32(len(required_instance_extensions));
        }
    } else {
        instance_createinfo.ppEnabledExtensionNames = raw_data(required_instance_extensions);
        instance_createinfo.enabledExtensionCount = u32(len(required_instance_extensions));
    }

    // Create Debugger
    when ODIN_DEBUG {
        debug_createinfo: vk.DebugUtilsMessengerCreateInfoEXT
        if exists.exists_vk_ext_debug_utils {
            debug_createinfo = {
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
            instance_createinfo.pNext = &debug_createinfo
        }
    }

    // Create instance
    result_create_instance := vk.CreateInstance(&instance_createinfo, nil, &instance)
    when ODIN_DEBUG { 
        if (result_create_instance != vk.Result.SUCCESS) {
            panic("Creating Vulkan instance failed");
        }
    }

    when ODIN_DEBUG {
        if exists.exists_vk_ext_debug_utils {
            CreateDebugUtilsMessengerEXT := vk.ProcCreateDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
            if (CreateDebugUtilsMessengerEXT != nil) {
                CreateDebugUtilsMessengerEXT(instance, &debug_createinfo, nil, &debugMessengerEXT)
            } else {
                fmt.println("vkCreateDebugUtilsMessengerEXT not found");
            }
        }
    }

    return
}

GetOptimalSurfaceDevice::proc(app_instance: vk.Instance, surface_khr: vk.SurfaceKHR) -> (surface_device: SurfaceDevice) {
    // Retrieve Physical Devices
    deviceCount : u32 = 0;
    vk.EnumeratePhysicalDevices(app_instance, &deviceCount, nil)
    devices := make([]vk.PhysicalDevice, deviceCount, context.temp_allocator)
    defer delete(devices, context.temp_allocator)
    vk.EnumeratePhysicalDevices(app_instance, &deviceCount, &devices[0])
    
    // Get most suited device
    deviceBestScore : u32 = 0
    for device in devices {
        deviceCurrentScore : u32 = 0
        
        // Retrieve Device Data
        physical_device_properties : vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(device, &physical_device_properties)
        deviceFeature : vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceFeatures(device, &deviceFeature)
        
        // Get Queue Family indicies
        qFamilyCount : u32 = 0
        vk.GetPhysicalDeviceQueueFamilyProperties(device, &qFamilyCount, nil)
        queue_families := make([]vk.QueueFamilyProperties, qFamilyCount, context.temp_allocator)
        vk.GetPhysicalDeviceQueueFamilyProperties(device, &qFamilyCount, raw_data(queue_families))

        QueueFamilySupports :: distinct bit_set[QueueFamilySupport; u8]
        QueueFamilySupport :: enum u8 {GRAPHICS, PRESENTATION}
        qFamiliesSupported : QueueFamilySupports
        for queue_family, i in queue_families {
            index := u32(i)
            if vk.QueueFlag.GRAPHICS in queue_family.queueFlags {
                surface_device.family_index_graphics = index
                qFamiliesSupported |= {.GRAPHICS}
            }

            presentSupport: b32 = false
            vk.GetPhysicalDeviceSurfaceSupportKHR(device, index, surface_khr, &presentSupport)
            if presentSupport {
                surface_device.family_index_presentation = index
                qFamiliesSupported |= {.PRESENTATION}
            }

            when ODIN_DEBUG {fmt.println("QueueCount:",queue_family.queueCount, queue_family.queueFlags, "HasPresentation:",presentSupport)}
        }

        // Calculate Score
        if physical_device_properties.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU {
            deviceCurrentScore += 1000
        }

        deviceCurrentScore += physical_device_properties.limits.maxImageDimension2D;

        // Disable score
        deviceCurrentScore *= u32(deviceFeature.geometryShader)
        deviceCurrentScore *= u32(qFamiliesSupported == {.GRAPHICS, .PRESENTATION})

        /// Check for device extension support
        device_extension_count: u32
        vk.EnumerateDeviceExtensionProperties(device, nil, &device_extension_count, nil)
        device_extensions := make([]vk.ExtensionProperties, device_extension_count, context.temp_allocator)
        vk.EnumerateDeviceExtensionProperties(device, nil, &device_extension_count, raw_data(device_extensions))
        
        swapchain_present := false
        for device_extension in &device_extensions {
            swapchain_present |= cstring(&device_extension.extensionName[0]) == cstring("VK_KHR_swapchain")
        }
        deviceCurrentScore *= u32(swapchain_present)

        /// Check Device Surface
        //// Allocate surface formats and present modes buffer
        format_count: u32
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device,surface_khr,&format_count,nil)
        present_mode_count: u32
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device,surface_khr,&present_mode_count,nil)

        present_mode_size := size_of(vk.PresentModeKHR)   * present_mode_count
        format_size  := size_of(vk.SurfaceFormatKHR) * format_count
        surface_present_and_format_buffer, _ := mem.alloc_bytes(size=int(present_mode_size + format_size), allocator=context.temp_allocator)
        
        //// Fill buffers
        surface_present_modes := mem.slice_data_cast([]vk.PresentModeKHR,   surface_present_and_format_buffer[:present_mode_size])
        surface_formats := mem.slice_data_cast([]vk.SurfaceFormatKHR, surface_present_and_format_buffer[present_mode_size:])
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device,surface_khr,&format_count,raw_data(surface_formats))
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device,surface_khr,&present_mode_count,raw_data(surface_present_modes))
        
        surface_device.surface_format = surface_formats[0]
        for format in surface_formats {
            if format.format == vk.Format.B8G8R8A8_SRGB {
                surface_device.surface_format = format
            }
        }

        surface_device.surface_present_mode = vk.PresentModeKHR.FIFO
        for present_mode in surface_present_modes {
            if present_mode == vk.PresentModeKHR.FIFO_RELAXED {
                surface_device.surface_present_mode = present_mode
            }
        }
        
        deviceCurrentScore *= u32(len(surface_present_modes)>0 && len(surface_formats)>0)

        // Resolve Score
        if deviceCurrentScore > deviceBestScore {
            surface_device.device_picked = device
            deviceBestScore = deviceCurrentScore
        }

        when ODIN_DEBUG {
            fmt.println("Checked device:", cstring(&physical_device_properties.deviceName[0]))
        }
    }

    when ODIN_DEBUG {
        physical_device_properties : vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(surface_device.device_picked, &physical_device_properties)
        fmt.println("GPU found: ", cstring(&physical_device_properties.deviceName[0]))
    }

    return
}

// Rememeber to destroy device
CreateDevice::proc(surface_device: SurfaceDevice, exists_vk_layer_khr_validation: b8) -> (logical_device: vk.Device) {
    family_index_set := u32set{surface_device.family_index_graphics, surface_device.family_index_presentation}

    // Setup Queue Device CreateInfo
    queuePriority : f32 = 1
    device_queue_createinfos := make([dynamic]vk.DeviceQueueCreateInfo,0,4)
    defer delete(device_queue_createinfos)
    for family_index in u32(0)..<u32(32) {
        if !(family_index in family_index_set) {continue}
        append(&device_queue_createinfos, vk.DeviceQueueCreateInfo {
            sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = family_index,
            queueCount = 1,
            pQueuePriorities = &queuePriority,
        })
    }

    // Create Logical Device
    deviceFeature : vk.PhysicalDeviceFeatures
    vk.GetPhysicalDeviceFeatures(surface_device.device_picked, &deviceFeature)
    swapchain_extension_name: cstring = "VK_KHR_swapchain"
    deviceCreateInfo := vk.DeviceCreateInfo {
        sType = vk.StructureType.DEVICE_CREATE_INFO,
        queueCreateInfoCount = u32(len(device_queue_createinfos)),
        pQueueCreateInfos = raw_data(device_queue_createinfos),
        pEnabledFeatures = &deviceFeature,
        enabledExtensionCount = 1,
        ppEnabledExtensionNames = &swapchain_extension_name,
    }

    when ODIN_DEBUG {
        if exists_vk_layer_khr_validation {
            deviceCreateInfo.enabledLayerCount = 1
            layerKHRVal: cstring = "VK_LAYER_KHRONOS_validation"
            deviceCreateInfo.ppEnabledLayerNames = &layerKHRVal
        }
    }

    // Create device
    resultCreateDevice := vk.CreateDevice(surface_device.device_picked, &deviceCreateInfo, nil, &logical_device)
    when ODIN_DEBUG { 
        if (resultCreateDevice != vk.Result.SUCCESS) {
            panic("Creating device failed")
        }
    }
    return
}