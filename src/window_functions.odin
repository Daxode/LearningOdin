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
        application_state := (^ApplicationState)(glfw.GetWindowUserPointer(window_handle))^
        fmt.println("Frame buffer size changed")
        vk.DeviceWaitIdle(application_state.logical_device)
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

////////////////////////////////////////// Everything Below is To help recreate the swapchain //////////////////////////////////////////

InitSwapchain :: proc(logical_device: vk.Device, window_handle: glfw.WindowHandle, 
                          surface_khr: vk.SurfaceKHR, surface_capabilities: vk.SurfaceCapabilitiesKHR, surface_device: ^SurfaceDevice,
                          ) -> (swapchain_khr: vk.SwapchainKHR, surface_extent: vk.Extent2D) {
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
        imageFormat = surface_device.surface_format.format,
        imageColorSpace = surface_device.surface_format.colorSpace,
        imageExtent = surface_extent,
        imageArrayLayers = 1,
        imageUsage = {.COLOR_ATTACHMENT},
        preTransform = surface_capabilities.currentTransform,
        compositeAlpha = {.OPAQUE},
        presentMode = surface_device.surface_present_mode,
        clipped = true, // clips from windows in front
    }

    if surface_device.family_index_graphics != surface_device.family_index_presentation {
        swapchain_khr_createinfo.imageSharingMode = vk.SharingMode.CONCURRENT
        swapchain_khr_createinfo.queueFamilyIndexCount = 2
        swapchain_khr_createinfo.pQueueFamilyIndices = &surface_device.family_index_graphics // Points to both graphics and presentation index
    }

    // Create swapchain_khr
    result_swapchain_khr := vk.CreateSwapchainKHR(logical_device, &swapchain_khr_createinfo, nil, &swapchain_khr)
    when ODIN_DEBUG { 
        if (result_swapchain_khr != vk.Result.SUCCESS) {
            panic("Creating swapchain failed")
        }
    }

    return
}

// Remember to delete swapchain_images to delete allocations
CreateViewsForSwapChain::proc(logical_device: vk.Device, swapchain_khr: vk.SwapchainKHR, format: vk.Format) -> (swapchain_images: []vk.Image, swapchain_image_views : []vk.ImageView){
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
            format = format,
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

    return
}

CreateRenderPass :: proc(logical_device: vk.Device, format: vk.Format) -> (renderpass: vk.RenderPass) {
    attachment_description := vk.AttachmentDescription {
        format = format,
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

    return
}

CreatePipeline :: proc(logical_device: vk.Device, surface_extent: vk.Extent2D, renderpass: vk.RenderPass) -> (pipeline: vk.Pipeline, pipeline_layout: vk.PipelineLayout){
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
    return
}

CreateFrameBuffers::proc(logical_device: vk.Device, renderpass: vk.RenderPass, image_views: ^[]vk.ImageView, surface_extent: vk.Extent2D) -> (framebuffers: []vk.Framebuffer){
    framebuffers = make([]vk.Framebuffer, len(image_views))
    for image_view, i in image_views {
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

    return
}

 CreateCommandBufferWithPool::proc(logical_device: vk.Device, framebuffers: []vk.Framebuffer, 
                                      family_index_graphics: u32, 
                                      surface_extent: vk.Extent2D, renderpass: vk.RenderPass, 
                                      pipeline: vk.Pipeline,
                                     )->(command_buffers: []vk.CommandBuffer, command_pool: vk.CommandPool){
    command_buffers = make([]vk.CommandBuffer, len(framebuffers))
    command_pool_createinfo := vk.CommandPoolCreateInfo {
        sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = family_index_graphics,
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

        clear_color := vk.ClearValue {color={float32={0.01, 0.01, 0.01, 0.5}}}
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

    return
}