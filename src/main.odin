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
import "core:os"

// Loads all function pointers, 
// except those that should be manually updated based on having the vulkan instance
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
    defer glfw.Terminate();
    window_handle: glfw.WindowHandle
    defer glfw.DestroyWindow(window_handle);
    {
        glfw.Init();
        glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
        glfw.WindowHint(glfw.RESIZABLE, 0);
        window_handle = glfw.CreateWindow(1600, 900, "Vulkan Fun", nil, nil);
        
        w, h, channels: c.int
        icon_bytes := image.load("resources/DaxodeProfile.png",&w,&h, &channels, 0)
        icon := glfw.Image{w,h,icon_bytes}
        glfw.SetWindowIcon(window_handle, []glfw.Image{icon})
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
    app_instance: vk.Instance
    defer vk.DestroyInstance(app_instance, nil)
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
    defer vk.DestroySurfaceKHR(app_instance, surface_khr, nil)
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
    defer vk.DestroyDevice(logical_device, nil)
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
    defer vk.DestroySwapchainKHR(logical_device, swapchain_khr, nil)
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

    // Get images from swapchain
    swapchain_images: []vk.Image
    swapchain_image_views : []vk.ImageView
    defer delete(swapchain_images)
    defer for image_view in swapchain_image_views {
        vk.DestroyImageView(logical_device, image_view, nil)
    }

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

            // Create swapchain_image_views
            result_swapchain_image_view := vk.CreateImageView(logical_device, &view_create_info, nil, &swapchain_image_views[i])
            when ODIN_DEBUG { 
                if (result_swapchain_image_view != vk.Result.SUCCESS) {
                    panic("Creating image view failed")
                }
            }
        }
    }

    // Setup RenderPass
    renderpass: vk.RenderPass
    defer vk.DestroyRenderPass(logical_device, renderpass, nil)
    {
        attachment_description := vk.AttachmentDescription {
            format = surface_format.format,
            samples = {._1},
            loadOp = .CLEAR,
            storeOp = .STORE,
            stencilLoadOp = .DONT_CARE,
            stencilStoreOp = .DONT_CARE,
            finalLayout = .PRESENT_SRC_KHR,
        }

        attachment_reference := vk.AttachmentReference {layout = .COLOR_ATTACHMENT_OPTIMAL}
        subpass_description := vk.SubpassDescription {
            pipelineBindPoint = .GRAPHICS,
            colorAttachmentCount = 1,
            pColorAttachments = &attachment_reference,
        }

        subpass_dependency := vk.SubpassDependency{
            srcSubpass = vk.SUBPASS_EXTERNAL,
            srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
            dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
            dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
        }

        renderpass_createinfo := vk.RenderPassCreateInfo {
            sType = vk.StructureType.RENDER_PASS_CREATE_INFO,
            attachmentCount = 1,
            pAttachments = &attachment_description,
            subpassCount = 1,
            pSubpasses = &subpass_description,
            dependencyCount = 1,
            pDependencies = &subpass_dependency,
        }

        // Create swapchain_image_views
        result_renderpass := vk.CreateRenderPass(logical_device, &renderpass_createinfo, nil, &renderpass)
        when ODIN_DEBUG { 
            if (result_renderpass != vk.Result.SUCCESS) {
                panic("Creating renderpass failed")
            }
        }
    }

    // Set up Graphics Pipeline
    pipeline_layout: vk.PipelineLayout
    defer vk.DestroyPipelineLayout(logical_device, pipeline_layout, nil)
    pipeline: vk.Pipeline
    defer vk.DestroyPipeline(logical_device, pipeline, nil)
    {
        triangle_vert_shader_module, _ := CreateShaderModuleFromDevice("shaders_compiled/triangle_vert.spv", logical_device)
        defer vk.DestroyShaderModule(logical_device, triangle_vert_shader_module, nil)
        triangle_vert_shader_stage := vk.PipelineShaderStageCreateInfo {
            sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
            stage = {.VERTEX},
            module = triangle_vert_shader_module,
            pName = "main",
        }

        triangle_frag_shader_module, _ := CreateShaderModuleFromDevice("shaders_compiled/triangle_frag.spv", logical_device)
        defer vk.DestroyShaderModule(logical_device, triangle_frag_shader_module, nil)
        triangle_frag_shader_stage := vk.PipelineShaderStageCreateInfo {
            sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
            stage = {.FRAGMENT},
            module = triangle_frag_shader_module,
            pName = "main",
        }

        triangle_shader_stages := [?]vk.PipelineShaderStageCreateInfo {triangle_vert_shader_stage, triangle_frag_shader_stage}

        // How vertex data should be handled
        vertex_input_createinfo := vk.PipelineVertexInputStateCreateInfo {sType = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO}
        assembly_input_createinfo := vk.PipelineInputAssemblyStateCreateInfo {
            sType = vk.StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            topology = .TRIANGLE_LIST,
        }

        // Where to draw
        app_viewport := vk.Viewport{
            width = f32(surface_extent.width),
            height = f32(surface_extent.height),
            maxDepth = 1,
        }
        app_scissor := vk.Rect2D{extent = surface_extent}

        viewport_state_createinfo := vk.PipelineViewportStateCreateInfo{
            sType = vk.StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            pScissors = &app_scissor,
            scissorCount = 1,
            pViewports = &app_viewport,
            viewportCount = 1,
        }

        // Create rasterizer
        rasterizer_createinfo := vk.PipelineRasterizationStateCreateInfo {
            sType = vk.StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            cullMode = {.BACK},
            frontFace = vk.FrontFace.CLOCKWISE,
        }

        multisampling_createinfo := vk.PipelineMultisampleStateCreateInfo {
            sType = vk.StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            minSampleShading = 1,
            rasterizationSamples = {._1},
        }

        blend_alpha := vk.PipelineColorBlendAttachmentState {
            colorWriteMask = {.R, .G, .B, .A},
            blendEnable = true,
            srcColorBlendFactor = .SRC_ALPHA,
            dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        }
        blend_createinfo := vk.PipelineColorBlendStateCreateInfo {
            sType = vk.StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            attachmentCount = 1,
            pAttachments = &blend_alpha,
        }

        // Set up dynamic states, that should be updated before drawing
        dynamic_states := [?]vk.DynamicState{.VIEWPORT, .LINE_WIDTH}
        dynamic_state_createinfo := vk.PipelineDynamicStateCreateInfo {
            sType = vk.StructureType.PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            dynamicStateCount = 2,
            pDynamicStates = &dynamic_states[0],
        }

        // Pipeline layout
        pipeline_layout_createinfo := vk.PipelineLayoutCreateInfo {sType = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO}
        result_pipeline_layout := vk.CreatePipelineLayout(logical_device, &pipeline_layout_createinfo, nil, &pipeline_layout)
        when ODIN_DEBUG { 
            if (result_pipeline_layout != vk.Result.SUCCESS) {
                panic("Creating pipeline layout failed")
            }
        }

        pipeline_createinfo := vk.GraphicsPipelineCreateInfo{
            sType = vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO,
            stageCount = 2,
            pStages = &triangle_shader_stages[0],
            pVertexInputState = &vertex_input_createinfo,
            pInputAssemblyState = &assembly_input_createinfo,
            pViewportState = &viewport_state_createinfo,
            pRasterizationState = &rasterizer_createinfo,
            pMultisampleState = &multisampling_createinfo,
            pColorBlendState = &blend_createinfo,
            //pDynamicState = &dynamic_state_createinfo,
            layout = pipeline_layout,
            renderPass = renderpass,
        }

        result_pipeline := vk.CreateGraphicsPipelines(logical_device, 0, 1, &pipeline_createinfo, nil, &pipeline)
        when ODIN_DEBUG { 
            if (result_pipeline != vk.Result.SUCCESS) {
                panic("Creating graphics pipeline failed")
            }
        }
    }

    // Create framebuffers
    framebuffers := make([]vk.Framebuffer, len(swapchain_image_views))
    defer delete(framebuffers)
    defer for framebuffer in framebuffers {
        vk.DestroyFramebuffer(logical_device, framebuffer, nil)
    }

    {
        for image_view, i in &swapchain_image_views {
            framebuffer_createinfo := vk.FramebufferCreateInfo {
                sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
                renderPass = renderpass,
                attachmentCount = 1,
                pAttachments = &image_view,
                width = surface_extent.width,
                height = surface_extent.height,
                layers = 1,
            }

            // Create framebuffer
            result_framebuffers := vk.CreateFramebuffer(logical_device, &framebuffer_createinfo, nil, &framebuffers[i])
            when ODIN_DEBUG { 
                if (result_framebuffers != vk.Result.SUCCESS) {
                    panic("Creating framebuffer failed")
                }
            }
        }
    }

    // Create command buffer
    command_pool: vk.CommandPool
    defer vk.DestroyCommandPool(logical_device, command_pool, nil)
    command_buffers := make([]vk.CommandBuffer, len(framebuffers))
    defer delete(command_buffers)
    {
        command_pool_createinfo := vk.CommandPoolCreateInfo {
            sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = famIndexGraphics,
        }

        result_command_pool := vk.CreateCommandPool(logical_device, &command_pool_createinfo, nil, &command_pool)
        when ODIN_DEBUG {
            if (result_command_pool != vk.Result.SUCCESS) {
                panic("Creating command pool failed")
            }
        }

        command_buffers_info := vk.CommandBufferAllocateInfo {
            sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
            commandPool = command_pool,
            level = .PRIMARY,
            commandBufferCount = u32(len(command_buffers)),
        }

        result_command_buffer := vk.AllocateCommandBuffers(logical_device, &command_buffers_info, raw_data(command_buffers))
        when ODIN_DEBUG {
            if result_command_buffer != vk.Result.SUCCESS {
                panic("Creating command buffers failed")
            }
        }

        for command_buffer, i in command_buffers {
            command_buffer_begininfo := vk.CommandBufferBeginInfo {
                sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
            }
            result_command_buffer_begin := vk.BeginCommandBuffer(command_buffer, &command_buffer_begininfo)
            when ODIN_DEBUG {
                if result_command_buffer_begin != vk.Result.SUCCESS {
                    panic("Beginning command buffer failed")
                }
            }

            clear_color := vk.ClearValue {color={float32={0., 0., 0., 1.}}}
            renderpass_begin_info := vk.RenderPassBeginInfo {
                sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
                renderPass = renderpass,
                framebuffer = framebuffers[i],
                renderArea = {{0,0}, surface_extent},
                clearValueCount = 1,
                pClearValues = &clear_color,
            }

            vk.CmdBeginRenderPass(command_buffer, &renderpass_begin_info, .INLINE)
            vk.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline)
            vk.CmdDraw(command_buffer,3,1,0,0)
            vk.CmdEndRenderPass(command_buffer)

            result_command_buffer_end := vk.EndCommandBuffer(command_buffer)
            when ODIN_DEBUG {
                if result_command_buffer_end != vk.Result.SUCCESS {
                    panic("Ending recording of command buffer failed")
                }
            }
        }
    }

    // Create semaphores
    semaphore_image_available: vk.Semaphore
    defer vk.DestroySemaphore(logical_device,semaphore_image_available,nil)
    semaphore_render_finished: vk.Semaphore
    defer vk.DestroySemaphore(logical_device,semaphore_render_finished,nil)
    {
        semaphore_createinfo := vk.SemaphoreCreateInfo{sType= vk.StructureType.SEMAPHORE_CREATE_INFO}
        result_semaphore_image_available := vk.CreateSemaphore(logical_device, &semaphore_createinfo, nil, &semaphore_image_available)
        result_semaphore_render_finished := vk.CreateSemaphore(logical_device, &semaphore_createinfo, nil, &semaphore_render_finished)
        when ODIN_DEBUG {
            if (result_semaphore_image_available != vk.Result.SUCCESS || result_semaphore_render_finished != vk.Result.SUCCESS) {
                panic("Creating semaphores failed")
            }
        }
    }

    queue_graphics: vk.Queue
    queue_presentation: vk.Queue
    // Get Queues
    {
        vk.GetDeviceQueue(logical_device, famIndexGraphics, 0, &queue_graphics)
        vk.GetDeviceQueue(logical_device, famIndexPresentation, 0, &queue_presentation)
    }

    // Main loop
    for !glfw.WindowShouldClose(window_handle) {
        glfw.PollEvents();

        // Draw frame
        image_index: u32
        vk.AcquireNextImageKHR(logical_device, swapchain_khr, c.UINT64_MAX, semaphore_image_available, 0, &image_index)
        wait_mask := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
        submit_info := vk.SubmitInfo {
            sType = vk.StructureType.SUBMIT_INFO,
            waitSemaphoreCount = 1,
            pWaitSemaphores = &semaphore_image_available,
            pWaitDstStageMask = &wait_mask,
            commandBufferCount = 1,
            pCommandBuffers = &command_buffers[image_index],
            signalSemaphoreCount = 1,
            pSignalSemaphores = &semaphore_render_finished,
        }

        result_queue_submit := vk.QueueSubmit(queue_graphics, 1, &submit_info, 0)
        when ODIN_DEBUG {
            if result_queue_submit != vk.Result.SUCCESS {
                panic("Submitting queue failed")
            }
        }

        present_info := vk.PresentInfoKHR {
            sType = vk.StructureType.PRESENT_INFO_KHR,
            waitSemaphoreCount = 1,
            pWaitSemaphores = &semaphore_render_finished,
            swapchainCount = 1,
            pSwapchains = &swapchain_khr,
            pImageIndices = &image_index,
        }

        vk.QueuePresentKHR(queue_presentation, &present_info)
        vk.QueueWaitIdle(queue_presentation)
        vk.QueueWaitIdle(queue_graphics)
    }

    when ODIN_DEBUG {
        DestroyDebugUtilsMessengerEXT := vk.ProcDestroyDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(app_instance, "vkDestroyDebugUtilsMessengerEXT"));
        if (DestroyDebugUtilsMessengerEXT != nil) {
            DestroyDebugUtilsMessengerEXT(app_instance, debugMessengerEXT, nil);
        }
    }
}

// Based on the given logical device, 
// it loads the given path to a SPIR-V, 
// and creates a shader module on the device
CreateShaderModuleFromDevice :: proc(path: string, device: vk.Device) -> (shader_module: vk.ShaderModule, success: bool) {
    shader_bytes, read_ok := os.read_entire_file(path)
    success = read_ok

    createinfo := vk.ShaderModuleCreateInfo {
        sType = vk.StructureType.SHADER_MODULE_CREATE_INFO,
        codeSize = len(shader_bytes),
        pCode = (^u32)(raw_data(shader_bytes)),
    }

    result_shader_module := vk.CreateShaderModule(device, &createinfo, nil, &shader_module)
    when ODIN_DEBUG { 
        if (result_shader_module != vk.Result.SUCCESS) {
            panic("Creating shader module failed")
        }
    }

    delete(shader_bytes)
    return
}