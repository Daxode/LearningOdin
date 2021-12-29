package playing_with_vulkan

import "core:c"
import "core:fmt"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"
import "vendor:stb/image"

import "core:c/libc"
import "core:runtime"


CreateWindowWithCallbacksAndIcon::proc() -> (window_handle: glfw.WindowHandle){
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.WindowHint(glfw.MAXIMIZED, 1)
    window_handle = glfw.CreateWindow(512, 512, "Vulkan Fun", nil, nil);

    glfw.SetKeyCallback(window_handle, proc "c" (window_handle: glfw.WindowHandle, key, scancode, action, mods: c.int){
        app := (^ApplicationState)(glfw.GetWindowUserPointer(window_handle))
        context = runtime.default_context()
        if action == glfw.PRESS {
            switch key {
                case glfw.KEY_F1, glfw.KEY_ENTER:
                    // Toggle fullscreen
                    if key == glfw.KEY_ENTER {if !(mods & glfw.MOD_ALT == glfw.MOD_ALT) {return;}}
                    monitors := glfw.GetMonitors()
                    window_x, window_y := glfw.GetWindowPos(app.window_handle)
                    for monitor in monitors {
                        videomode := glfw.GetVideoMode(monitor)
                        monitor_x, monitor_y := glfw.GetMonitorPos(monitor)
                        if window_x >= monitor_x && window_y >= monitor_y && window_x < monitor_x+videomode.width && window_y < monitor_y+videomode.height {
                            is_fullscreen := 1-glfw.GetWindowAttrib(app.window_handle, glfw.DECORATED)
                            glfw.SetWindowAttrib(app.window_handle, glfw.DECORATED, is_fullscreen)
                            if is_fullscreen > 0 {
                                glfw.SetWindowPos(app.window_handle,monitor_x+200,monitor_y+200)
                                glfw.SetWindowSize(app.window_handle, 512, 512)
                            } else {
                                videomode := glfw.GetVideoMode(monitor)
                                glfw.SetWindowPos(app.window_handle,monitor_x,monitor_y)
                                glfw.SetWindowSize(app.window_handle, videomode.width, videomode.height)
                            }
                        }
                    }
                case glfw.KEY_F5:
                    // Reload Shaders and Swapchain
                    when DAX_DEBUG {
                        libc.system("glslc.exe ../shaders/triangle.vert -o shaders_compiled/triangle_vert.spv")
                        libc.system("glslc.exe ../shaders/triangle.frag -o shaders_compiled/triangle_frag.spv")
                    }

                    vk.DestroyShaderModule(app.logical_device, app.triangle_material.vertex,nil)
                    vk.DestroyShaderModule(app.logical_device, app.triangle_material.fragment,nil)
                    app.triangle_material.vertex, _ = CreateShaderModuleFromDevice("shaders_compiled/triangle_vert.spv", app.logical_device)
                    app.triangle_material.fragment, _ = CreateShaderModuleFromDevice("shaders_compiled/triangle_frag.spv", app.logical_device)
                    app.triangle_pipeline_info.stage_vertex_createinfo.module = app.triangle_material.vertex
                    app.triangle_pipeline_info.stage_fragment_createinfo.module = app.triangle_material.fragment

                    app.should_swap = true
                    //SwapSwapchain(&app)
                case glfw.KEY_ESCAPE:
                    glfw.SetWindowShouldClose(window_handle, true)
            }
        }
    })

    glfw.SetFramebufferSizeCallback(window_handle, glfw.FramebufferSizeProc(proc(window_handle: glfw.WindowHandle, width, height: c.int){
        app := (^ApplicationState)(glfw.GetWindowUserPointer(window_handle))
        app.should_swap = true
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
    
    when DAX_DEBUG {
        if exists.exists_vk_layer_khr_validation {
            instance_createinfo.enabledLayerCount = 1
            layerKHRVal : cstring = "VK_LAYER_KHRONOS_validation"
            instance_createinfo.ppEnabledLayerNames = &layerKHRVal
        }
    }

    required_instance_extensions := glfw.GetRequiredInstanceExtensions();
    when DAX_DEBUG {
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
    when DAX_DEBUG {
        debug_createinfo: vk.DebugUtilsMessengerCreateInfoEXT
        if exists.exists_vk_ext_debug_utils {
            debug_createinfo = {
                sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                messageSeverity = {.INFO, .WARNING, .ERROR},
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
    when DAX_DEBUG { 
        if (result_create_instance != vk.Result.SUCCESS) {
            panic("Creating Vulkan instance failed");
        }
    }

    when DAX_DEBUG {
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

GetOptimalSurfaceDevice::proc(app_instance: vk.Instance, surface_khr: vk.SurfaceKHR) -> SurfaceDevice {
    // Retrieve Physical Devices
    deviceCount : u32 = 0;
    vk.EnumeratePhysicalDevices(app_instance, &deviceCount, nil)
    devices := make([]vk.PhysicalDevice, deviceCount, context.temp_allocator)
    defer delete(devices, context.temp_allocator)
    vk.EnumeratePhysicalDevices(app_instance, &deviceCount, &devices[0])
    
    surface_devices := make([]SurfaceDevice, deviceCount, context.temp_allocator)
    defer delete(surface_devices, context.temp_allocator)

    // Get most suited device
    deviceBestScore : u32 = 0
    bestDeviceIndex: runtime.Maybe(int)
    for device, device_index in devices {
        deviceCurrentScore : u32 = 0
        surface_devices[device_index].device_picked = device
        
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
                surface_devices[device_index].family_index_graphics = index
                qFamiliesSupported |= {.GRAPHICS}
            }

            presentSupport: b32 = false
            vk.GetPhysicalDeviceSurfaceSupportKHR(device, index, surface_khr, &presentSupport)
            if presentSupport {
                surface_devices[device_index].family_index_presentation = index
                qFamiliesSupported |= {.PRESENTATION}
            }

            when DAX_DEBUG {fmt.println("QueueCount:",queue_family.queueCount, queue_family.queueFlags, "HasPresentation:",presentSupport)}
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
        
        surface_devices[device_index].surface_format = surface_formats[0]
        for format in surface_formats {
            if format.format == vk.Format.B8G8R8A8_SRGB {
                surface_devices[device_index].surface_format = format
            }
        }

        surface_devices[device_index].surface_present_mode = vk.PresentModeKHR.FIFO
        for present_mode in surface_present_modes {
            if present_mode == vk.PresentModeKHR.FIFO_RELAXED {
                surface_devices[device_index].surface_present_mode = present_mode
            }
        }
        
        deviceCurrentScore *= u32(len(surface_present_modes)>0 && len(surface_formats)>0)

        // Resolve Score
        if deviceCurrentScore > deviceBestScore {
            bestDeviceIndex = device_index
            deviceBestScore = deviceCurrentScore
        }

        when DAX_DEBUG {
            fmt.println("Checked device:", cstring(&physical_device_properties.deviceName[0]))
        }
    }

    when DAX_DEBUG {
        fmt.println("Surface devices:", surface_devices)
        if bestDeviceIndex == nil {
            panic("No suitable device found!")
        }
        physical_device_properties : vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(surface_devices[bestDeviceIndex.?].device_picked, &physical_device_properties)
        fmt.println("GPU found: ", cstring(&physical_device_properties.deviceName[0]))
    }

    return surface_devices[bestDeviceIndex.?]
}

// Rememeber to destroy device
CreateDevice::proc(surface_device: SurfaceDevice, exists_vk_layer_khr_validation: b8) -> (logical_device: vk.Device) {
    family_index_set := u32set{surface_device.family_index_graphics, surface_device.family_index_presentation}

    // Setup Queue Device CreateInfo
    queuePriority : f32 = 1
    device_queue_createinfos := make([dynamic]vk.DeviceQueueCreateInfo,0,4, context.temp_allocator)
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

    when DAX_DEBUG {
        if exists_vk_layer_khr_validation {
            deviceCreateInfo.enabledLayerCount = 1
            layerKHRVal: cstring = "VK_LAYER_KHRONOS_validation"
            deviceCreateInfo.ppEnabledLayerNames = &layerKHRVal
        }
    }

    // Create device
    resultCreateDevice := vk.CreateDevice(surface_device.device_picked, &deviceCreateInfo, nil, &logical_device)
    when DAX_DEBUG { 
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
    when DAX_DEBUG { 
        if (result_swapchain_khr != vk.Result.SUCCESS) {
            panic("Creating swapchain failed")
        }
    }

    return
}

// Get images from swapchain
// Remember to delete swapchain_images to delete allocations
CreateViewsForSwapChain::proc(logical_device: vk.Device, swapchain_khr: vk.SwapchainKHR, format: vk.Format, swapchain_images: []vk.Image, swapchain_image_views : []vk.ImageView){
    // Get images
    image_count := u32(len(swapchain_images))
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
        when DAX_DEBUG { 
            if (result_swapchain_image_view != vk.Result.SUCCESS) {
                panic("Creating image view failed")
            }
        }
    }

    return
}

// Setup RenderPass
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
    when DAX_DEBUG { 
        if (result_renderpass != vk.Result.SUCCESS) {
            panic("Creating renderpass failed")
        }
    }

    return
}

// Set up Graphics Pipeline
SetPipelineInfoFromMaterial :: proc(logical_device: vk.Device, renderpass: vk.RenderPass, pipeline_layout: vk.PipelineLayout, material: Material, graphics_pipeline_info: ^GraphicsPipelineInfo){
    using graphics_pipeline_info

    stage_vertex_createinfo = {
        sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.VERTEX},
        module = material.vertex,
        pName = "main",
    }
    stage_fragment_createinfo = {
        sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.FRAGMENT},
        module = material.fragment,
        pName = "main",
    }

    // How vertex data should be handled
    vertex_input_createinfo = vk.PipelineVertexInputStateCreateInfo {sType = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO}
    assembly_input_createinfo = vk.PipelineInputAssemblyStateCreateInfo {
        sType = vk.StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }

    // Where to draw
    viewport.maxDepth = 1

    viewport_state_createinfo = vk.PipelineViewportStateCreateInfo {
        sType = vk.StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        pScissors = &scissor,
        scissorCount = 1,
        pViewports = &viewport,
        viewportCount = 1,
    }

    // Create rasterizer
    rasterizer_createinfo = vk.PipelineRasterizationStateCreateInfo {
        sType = vk.StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        cullMode = {.BACK},
        frontFace = vk.FrontFace.CLOCKWISE,
    }

    multisampling_createinfo = vk.PipelineMultisampleStateCreateInfo {
        sType = vk.StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        minSampleShading = 1,
        rasterizationSamples = {._1},
    }

    blend_alpha = vk.PipelineColorBlendAttachmentState {
        colorWriteMask = {.R, .G, .B, .A},
        blendEnable = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
    }
    blend_createinfo = vk.PipelineColorBlendStateCreateInfo {
        sType = vk.StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount = 1,
        pAttachments = &blend_alpha,
    }

    // Set up dynamic states, that should be updated before drawing
    // dynamic_states = [?]vk.DynamicState{.VIEWPORT, .LINE_WIDTH}
    // dynamic_state_createinfo = vk.PipelineDynamicStateCreateInfo {
    //     sType = vk.StructureType.PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    //     dynamicStateCount = 2,
    //     pDynamicStates = &dynamic_states[0],
    // }

    createinfo = vk.GraphicsPipelineCreateInfo{
        sType = vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount = 2,
        pStages = &stage_vertex_createinfo,
        pVertexInputState = &vertex_input_createinfo,
        pInputAssemblyState = &assembly_input_createinfo,
        pViewportState = &viewport_state_createinfo,
        pRasterizationState = &rasterizer_createinfo,
        pMultisampleState = &multisampling_createinfo,
        pColorBlendState = &blend_createinfo,
        //pDynamicState = &dynamic_state_createinfo,
        renderPass = renderpass,
    }

    return
}

// Create framebuffers
CreateFrameBuffers::proc(logical_device: vk.Device, renderpass: vk.RenderPass, image_views: ^[]vk.ImageView, surface_extent: vk.Extent2D, framebuffers: []vk.Framebuffer){
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
        when DAX_DEBUG { 
            if (result_framebuffers != vk.Result.SUCCESS) {
                panic("Creating framebuffer failed")
            }
        }
    }

    return
}

 // Create command buffer
 CreateCommandBufferWithPool::proc(logical_device: vk.Device, framebuffers: []vk.Framebuffer, 
                                      family_index_graphics: u32, 
                                      surface_extent: vk.Extent2D, renderpass: vk.RenderPass, 
                                      pipeline: vk.Pipeline, 
                                      command_buffers: []vk.CommandBuffer)->(command_pool: vk.CommandPool){
    command_pool_createinfo := vk.CommandPoolCreateInfo {
        sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = family_index_graphics,
    }

    result_command_pool := vk.CreateCommandPool(logical_device, &command_pool_createinfo, nil, &command_pool)
    when DAX_DEBUG {
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
    when DAX_DEBUG {
        if result_command_buffer != vk.Result.SUCCESS {
            panic("Creating command buffers failed")
        }
    }

    for command_buffer, i in command_buffers {
        command_buffer_begininfo := vk.CommandBufferBeginInfo {
            sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
        }
        result_command_buffer_begin := vk.BeginCommandBuffer(command_buffer, &command_buffer_begininfo)
        when DAX_DEBUG {
            if result_command_buffer_begin != vk.Result.SUCCESS {
                panic("Beginning command buffer failed")
            }
        }

        clear_color := vk.ClearValue {color={float32={0.02, 0.015, 0.015, 0.5}}}
        
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
        vk.CmdDraw(command_buffer,6,1,0,0)
        vk.CmdEndRenderPass(command_buffer)

        result_command_buffer_end := vk.EndCommandBuffer(command_buffer)
        when DAX_DEBUG {
            if result_command_buffer_end != vk.Result.SUCCESS {
                panic("Ending recording of command buffer failed")
            }
        }
    }

    return
}

CreateSwapchainBuffers::proc(logical_device: vk.Device, swapchain_khr: vk.SwapchainKHR) -> (swapchain_buffers: SwapchainBuffers) {
    using swapchain_buffers

    // Get image count
    image_count: u32
    vk.GetSwapchainImagesKHR(logical_device, swapchain_khr, &image_count,nil)
    
    // Allocate memmory to save images and views
    images_size := size_of(vk.Image)*image_count
    image_views_size := size_of(vk.ImageView)*image_count
    framebuffers_size := size_of(vk.Framebuffer)*image_count
    command_buffers_size := size_of(vk.CommandBuffer)*image_count
    
    buffer, _ := mem.alloc_bytes(int(images_size + image_views_size + framebuffers_size + command_buffers_size))
    images          = mem.slice_data_cast([]vk.Image,         buffer[:images_size])
    image_views     = mem.slice_data_cast([]vk.ImageView,     buffer[ images_size:images_size+image_views_size])
    framebuffers    = mem.slice_data_cast([]vk.Framebuffer,   buffer[             images_size+image_views_size:images_size+image_views_size+framebuffers_size])
    command_buffers = mem.slice_data_cast([]vk.CommandBuffer, buffer[                                          images_size+image_views_size+framebuffers_size:])
    return
}

// pipeline_createinfo can only point to zero init place if first_time is true
UpdateSwapchainData :: proc(logical_device: vk.Device, window_handle: glfw.WindowHandle, 
                        surface_khr: vk.SurfaceKHR, surface_device: ^SurfaceDevice, 
                        renderpass: vk.RenderPass, material: Material, pipeline_info: ^GraphicsPipelineInfo, $first_time : b8, using swapchain_data: ^SwapchainData) {

    surface_capabilities: vk.SurfaceCapabilitiesKHR
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(surface_device.device_picked, surface_khr, &surface_capabilities)
    swapchain_khr, surface_extent = InitSwapchain(logical_device, window_handle, surface_khr, surface_capabilities, surface_device)
    
    when first_time {
        swapchain_buffers = CreateSwapchainBuffers(logical_device, swapchain_khr)
        SetPipelineInfoFromMaterial(logical_device, renderpass, pipeline_layout, material, pipeline_info)

        pipeline_layout_createinfo := vk.PipelineLayoutCreateInfo {sType = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO}
        result_pipeline_layout := vk.CreatePipelineLayout(logical_device, &pipeline_layout_createinfo, nil, &pipeline_layout)
        when DAX_DEBUG { 
            if (result_pipeline_layout != vk.Result.SUCCESS) {
                panic("Creating pipeline layout failed")
            }
        }
        pipeline_info.createinfo.layout = pipeline_layout
    }

    pipeline_info.viewport.width = f32(surface_extent.width)
    pipeline_info.viewport.height = f32(surface_extent.height)
    pipeline_info.scissor.extent = surface_extent
    result_pipeline := vk.CreateGraphicsPipelines(logical_device, 0, 1, &pipeline_info.createinfo, nil, &pipeline)
    when DAX_DEBUG { 
        if (result_pipeline != vk.Result.SUCCESS) {
            panic("Creating graphics pipeline failed")
        }
    }
    CreateViewsForSwapChain(logical_device, swapchain_khr, surface_device.surface_format.format, swapchain_buffers.images, swapchain_buffers.image_views)
    CreateFrameBuffers(logical_device, renderpass, &swapchain_buffers.image_views, surface_extent, swapchain_buffers.framebuffers)
    command_pool = CreateCommandBufferWithPool(logical_device, swapchain_buffers.framebuffers, surface_device.family_index_graphics, surface_extent, renderpass, pipeline, swapchain_buffers.command_buffers)
    return
}
    
DestroySwapchainData::proc(logical_device: vk.Device, using swapchain_data: SwapchainData) {
    vk.DestroyPipeline(logical_device, pipeline, nil)
    vk.DestroyCommandPool(logical_device, command_pool, nil)
    for framebuffer in swapchain_buffers.framebuffers {
        vk.DestroyFramebuffer(logical_device, framebuffer, nil)
    }
    for image_view in swapchain_buffers.image_views {
        vk.DestroyImageView(logical_device, image_view, nil)
    }
    vk.DestroySwapchainKHR(logical_device, swapchain_khr, nil)
}

SwapSwapchain::proc(using application_state: ^ApplicationState) {
    w, h := glfw.GetFramebufferSize(window_handle)
    for (w == 0 || h == 0) && !glfw.WindowShouldClose(window_handle) {
        UpdateFrame(application_state, false)
    }

    vk.DeviceWaitIdle(logical_device)
    DestroySwapchainData(logical_device, swapchain_data)
    UpdateSwapchainData(logical_device, window_handle, surface_khr, &surface_device, renderpass_default, triangle_material, &triangle_pipeline_info, false, &swapchain_data)  
    application_state.should_swap = false
}