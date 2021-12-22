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
    window_handle: glfw.WindowHandle
    {
        glfw.Init();
        glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
        glfw.WindowHint(glfw.RESIZABLE, 0);
        window_handle = glfw.CreateWindow(1600, 900, "Vulkan Fun", nil, nil);
        
        // w, h, channels: c.int
        // icon_bytes := image.load("resources/DaxodeProfile.png",&w,&h, &channels, 0)
        // icon := glfw.Image{w,h,icon_bytes}
        // glfw.SetWindowIcon(window_handle, []glfw.Image{icon})
        // image.image_free(icon_bytes)
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
    app_instance: vk.Instance
    when ODIN_DEBUG {debugMessengerEXT: vk.DebugUtilsMessengerEXT}
    {
        instance_createinfo : vk.InstanceCreateInfo;
        instance_createinfo.sType = vk.StructureType.INSTANCE_CREATE_INFO;
        instance_createinfo.pApplicationInfo = &appInfo;
        when ODIN_DEBUG {
            instance_createinfo.enabledLayerCount = 1
            layerKHRVal : cstring = "VK_LAYER_KHRONOS_validation"
            instance_createinfo.ppEnabledLayerNames = &layerKHRVal
        }

        requiredInstanceExtensions := glfw.GetRequiredInstanceExtensions();
        when ODIN_DEBUG {
            enabledExtensions := make([]cstring, len(requiredInstanceExtensions)+1)
            defer delete(enabledExtensions)
            copy(enabledExtensions[:], requiredInstanceExtensions[:])
            enabledExtensions[len(enabledExtensions)-1] = "VK_EXT_debug_utils"
            instance_createinfo.ppEnabledExtensionNames = raw_data(enabledExtensions);
            instance_createinfo.enabledExtensionCount = u32(len(enabledExtensions));
        } else {
            instance_createinfo.ppEnabledExtensionNames = raw_data(requiredInstanceExtensions);
            instance_createinfo.enabledExtensionCount = u32(len(requiredInstanceExtensions));
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

            instance_createinfo.pNext = cast(rawptr) &debugCreateInfo
        }

        // Create instance
        resultCreateInstance := vk.CreateInstance(&instance_createinfo, nil, &app_instance)
        when ODIN_DEBUG { 
            if (resultCreateInstance != vk.Result.SUCCESS) {
                panic("Creating Vulkan instance failed");
            }
        }

        when ODIN_DEBUG {
            CreateDebugUtilsMessengerEXT := vk.ProcCreateDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(app_instance, "vkCreateDebugUtilsMessengerEXT"));
            if (CreateDebugUtilsMessengerEXT != nil) {
                CreateDebugUtilsMessengerEXT(app_instance, &debugCreateInfo, nil, &debugMessengerEXT)
            } else {
                panic("vk.Result.ERROR_EXTENSION_NOT_PRESENT");
            }
        }
    }

    // Get window surface
    surface_khr : vk.SurfaceKHR
    {
        resultCreateWindowSurface := glfw.CreateWindowSurface(app_instance, window_handle, nil, &surface_khr)
        when ODIN_DEBUG { 
            if (resultCreateWindowSurface != vk.Result.SUCCESS) {
                panic("Creating instance failed")
            }
        }
    }

    // Pick the physical device
    device_picked: vk.PhysicalDevice
    famIndexGraphics: u32
    famIndexPresentation: u32
    surface_present_mode: vk.PresentModeKHR
    surface_format: vk.SurfaceFormatKHR
    {
        // Retrieve Physical Devices
        deviceCount : u32 = 0;
        vk.EnumeratePhysicalDevices(app_instance, &deviceCount, nil)
        devices := make([]vk.PhysicalDevice, deviceCount)
        defer delete(devices)
        vk.EnumeratePhysicalDevices(app_instance, &deviceCount, &devices[0])
        
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

            /// Check for device extension support
            device_extension_count: u32
            vk.EnumerateDeviceExtensionProperties(device, nil, &device_extension_count, nil)
            device_extensions := make([]vk.ExtensionProperties, device_extension_count)
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
            
            surface_format = surface_formats[0]
            for format in surface_formats {
                if format.format == vk.Format.B8G8R8A8_SRGB {
                    surface_format = format
                }
            }

            surface_present_mode = vk.PresentModeKHR.FIFO
            for present_mode in surface_present_modes {
                if present_mode == vk.PresentModeKHR.FIFO_RELAXED {
                    surface_present_mode = present_mode
                }
            }
            
            deviceCurrentScore *= u32(len(surface_present_modes)>0 && len(surface_formats)>0)

            // Resolve Score
            if deviceCurrentScore > deviceBestScore {
                device_picked = device
                deviceBestScore = deviceCurrentScore
            }

            when ODIN_DEBUG {
                fmt.println(strings.string_from_nul_terminated_ptr(&deviceProp.deviceName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE))
            }
        }

        when ODIN_DEBUG {
            deviceProp : vk.PhysicalDeviceProperties
            vk.GetPhysicalDeviceProperties(device_picked, &deviceProp)
            fmt.println("GPU found: ", strings.string_from_nul_terminated_ptr(&deviceProp.deviceName[0], vk.MAX_PHYSICAL_DEVICE_NAME_SIZE))
        }
    }
    
    // Create Logical Device
    logical_device : vk.Device
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
        vk.GetPhysicalDeviceFeatures(device_picked, &deviceFeature)
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

        // Create device
        resultCreateDevice := vk.CreateDevice(device_picked, &deviceCreateInfo, nil, &logical_device)
        when ODIN_DEBUG { 
            if (resultCreateDevice != vk.Result.SUCCESS) {
                panic("Creating device failed")
            }
        }
    }

    // Create swapchain
    swapchain_khr: vk.SwapchainKHR
    surface_extent: vk.Extent2D
    {
        surface_capabilities: vk.SurfaceCapabilitiesKHR
        vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device_picked, surface_khr, &surface_capabilities)
        
        surface_extent = surface_capabilities.currentExtent
        if (surface_extent.width == c.UINT32_MAX) {
            window_frame_width, window_frame_height := glfw.GetFramebufferSize(window_handle)
            surface_extent = {
                clamp(u32(window_frame_width), surface_capabilities.minImageExtent.width,  surface_capabilities.maxImageExtent.width),
                clamp(u32(window_frame_height), surface_capabilities.minImageExtent.height,  surface_capabilities.maxImageExtent.height),
            }
        }

        swapchain_khr_createinfo := vk.SwapchainCreateInfoKHR {
            sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
            surface = surface_khr,
            minImageCount = min(surface_capabilities.minImageCount+1, surface_capabilities.maxImageCount),
            imageFormat = surface_format.format,
            imageColorSpace = surface_format.colorSpace,
            imageExtent = surface_extent,
            imageArrayLayers = 1,
            imageUsage = {.COLOR_ATTACHMENT},
            preTransform = surface_capabilities.currentTransform,
            compositeAlpha = {.OPAQUE},
            presentMode = surface_present_mode,
            clipped = true, // clips from windows in front
        }

        if famIndexGraphics != famIndexPresentation {
            swapchain_khr_createinfo.imageSharingMode = vk.SharingMode.CONCURRENT
            q_family_indicies := [?]u32{famIndexGraphics, famIndexPresentation}
            swapchain_khr_createinfo.queueFamilyIndexCount = len(q_family_indicies)
            swapchain_khr_createinfo.pQueueFamilyIndices = &(q_family_indicies)[0]
        }

        // Create swapchain_khr
        result_swapchain_khr := vk.CreateSwapchainKHR(logical_device, &swapchain_khr_createinfo, nil, &swapchain_khr)
        when ODIN_DEBUG { 
            if (result_swapchain_khr != vk.Result.SUCCESS) {
                panic("Creating swapchain failed")
            }
        }
    }

    swapchain_images: []vk.Image
    swapchain_image_views : []vk.ImageView
    defer delete(swapchain_images)
    defer delete(swapchain_image_views)
    {
        // Get image count
        image_count: u32
        vk.GetSwapchainImagesKHR(logical_device, swapchain_khr, &image_count,nil)

        // Allocate memmory to save images and views
        swapchain_images_size := size_of(vk.Image)*image_count
        swapchain_images_and_views_buffer, _ := mem.alloc_bytes(int(swapchain_images_size + size_of(vk.ImageView)*image_count))
        swapchain_images        = mem.slice_data_cast([]vk.Image,       swapchain_images_and_views_buffer[:swapchain_images_size])
        swapchain_image_views   = mem.slice_data_cast([]vk.ImageView,   swapchain_images_and_views_buffer[swapchain_images_size:])
        
        // Get images
        vk.GetSwapchainImagesKHR(logical_device, swapchain_khr, &image_count, raw_data(swapchain_images))

        // Create views and fill swapchain_image_views
        for swapchain_image, i in swapchain_images {
            view_create_info := vk.ImageViewCreateInfo {
                sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
                image = swapchain_image,
                viewType = vk.ImageViewType.D2,
                format = surface_format.format,
                components = {.IDENTITY,.IDENTITY,.IDENTITY,.IDENTITY},
                subresourceRange = {{.COLOR}, 0,1,0,1},
            }

            // Create swapchain_khr
            result_swapchain_image_view := vk.CreateImageView(logical_device, &view_create_info, nil, &swapchain_image_views[i])
            when ODIN_DEBUG { 
                if (result_swapchain_image_view != vk.Result.SUCCESS) {
                    panic("Creating image view failed")
                }
            }
        }
    }

    // Main loop
    for !glfw.WindowShouldClose(window_handle) {
        glfw.PollEvents();
    }

    when ODIN_DEBUG {
        DestroyDebugUtilsMessengerEXT := vk.ProcDestroyDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(app_instance, "vkDestroyDebugUtilsMessengerEXT"));
        if (DestroyDebugUtilsMessengerEXT != nil) {
            DestroyDebugUtilsMessengerEXT(app_instance, debugMessengerEXT, nil);
        }
    }

    for image_view in swapchain_image_views {
        vk.DestroyImageView(logical_device, image_view, nil)
    }
    vk.DestroySwapchainKHR(logical_device, swapchain_khr, nil)
    vk.DestroyDevice(logical_device, nil)
    vk.DestroySurfaceKHR(app_instance, surface_khr, nil)
    vk.DestroyInstance(app_instance, nil)
    glfw.DestroyWindow(window_handle);
    glfw.Terminate();
}