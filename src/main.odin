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
import "core:time"

// Loads all function pointers, 
// except those that should be manually updated based on having the vulkan instance
load_vulkan_function_pointers::proc()
{
    lib, ok := dynlib.load_library("vulkan-1.dll", true)
    assert(ok)

    context.user_ptr = &lib

    vk.load_proc_addresses(proc(p: rawptr, name: cstring) {
        lib := (cast(^dynlib.Library)context.user_ptr)^

        found_ptr, found := dynlib.symbol_address(lib, runtime.cstring_to_string(name))
        if !found {return;}

        casted := cast(^rawptr)p // Pointer to function pointer
        casted^ = found_ptr
    });
}

FRAME_IN_Q_MAX : u8 : 6
WindowState :: struct { // Use for state not for argument passing with callback
    window_handle: glfw.WindowHandle,
    logical_device: vk.Device,
    vk_instance: vk.Instance,
    using exists_in_instance: VulkanInstanceExists, // Only filled in debug
}

main::proc()
{
    load_vulkan_function_pointers()
    
    when ODIN_DEBUG {
        fmt.println("debug enabled")
    }

    window_state: WindowState
    using window_state

    glfw.Init();
    defer glfw.Terminate();
    
    // Create GLFW Window
    window_state.window_handle = CreateWindowWithCallbacksAndIcon()
    defer glfw.DestroyWindow(window_state.window_handle)
    glfw.SetWindowUserPointer(window_state.window_handle, &window_state)

    // Check validation layers and for VK_EXT_debug_utils
    when ODIN_DEBUG {
        window_state.exists_in_instance = CheckVulkanInstanceExistence()
    }

    // Create App Info
    appInfo := vk.ApplicationInfo {
        sType = vk.StructureType.APPLICATION_INFO,
        pApplicationName = "Hello Triangle",
        applicationVersion = vk.MAKE_VERSION(1,0,0),
        pEngineName = "Dax Engine",
        engineVersion = vk.MAKE_VERSION(1,0,0),
        apiVersion = vk.API_VERSION_1_0,
    }

    // Create Instance and External Debug Messenger
    app_instance: vk.Instance
    defer vk.DestroyInstance(app_instance, nil)
    when ODIN_DEBUG {debugMessengerEXT: vk.DebugUtilsMessengerEXT}
    {
        instance_createinfo := vk.InstanceCreateInfo{
            sType = vk.StructureType.INSTANCE_CREATE_INFO,
            pApplicationInfo = &appInfo,
        }
        
        when ODIN_DEBUG {
            if window_state.exists_vk_layer_khr_validation {
                instance_createinfo.enabledLayerCount = 1
                layerKHRVal : cstring = "VK_LAYER_KHRONOS_validation"
                instance_createinfo.ppEnabledLayerNames = &layerKHRVal
            }
        }

        required_instance_extensions := glfw.GetRequiredInstanceExtensions();
        when ODIN_DEBUG {
            enabled_extensions: []cstring
            defer if window_state.exists_vk_ext_debug_utils{delete(enabled_extensions, context.temp_allocator)} 
            // Append VK_EXT_debug_utils to list of required_instance_extensions
            if window_state.exists_vk_ext_debug_utils {
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
            if window_state.exists_vk_ext_debug_utils {
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
        result_create_instance := vk.CreateInstance(&instance_createinfo, nil, &app_instance)
        when ODIN_DEBUG { 
            if (result_create_instance != vk.Result.SUCCESS) {
                panic("Creating Vulkan instance failed");
            }
        }

        when ODIN_DEBUG {
            if window_state.exists_vk_ext_debug_utils {
                CreateDebugUtilsMessengerEXT := vk.ProcCreateDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(app_instance, "vkCreateDebugUtilsMessengerEXT"));
                if (CreateDebugUtilsMessengerEXT != nil) {
                    CreateDebugUtilsMessengerEXT(app_instance, &debug_createinfo, nil, &debugMessengerEXT)
                } else {
                    fmt.println("vkCreateDebugUtilsMessengerEXT not found");
                }
            }
        }
    }

    // Get window surface
    surface_khr : vk.SurfaceKHR
    defer vk.DestroySurfaceKHR(app_instance, surface_khr, nil)
    {
        resultCreateWindowSurface := glfw.CreateWindowSurface(app_instance, window_state.window_handle, nil, &surface_khr)
        when ODIN_DEBUG { 
            if (resultCreateWindowSurface != vk.Result.SUCCESS) {
                panic("Creating window surface failed")
            }
        }
    }

    // Pick the physical device
    surface_device := GetOptimalSurfaceDevice(app_instance, surface_khr)
    
    
    // Create Logical Device
    window_state.logical_device = CreateDevice(surface_device, window_state.exists_vk_layer_khr_validation)
    defer vk.DestroyDevice(window_state.logical_device, nil)
    
    // Get Queues
    queue_graphics: vk.Queue
    queue_presentation: vk.Queue
    {
        vk.GetDeviceQueue(window_state.logical_device, surface_device.family_index_graphics, 0, &queue_graphics)
        vk.GetDeviceQueue(window_state.logical_device, surface_device.family_index_presentation, 0, &queue_presentation)
    }

    // Create swapchain
    surface_capabilities: vk.SurfaceCapabilitiesKHR
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(surface_device.device_picked, surface_khr, &surface_capabilities)
    
    swapchain_khr, surface_extent := InitSwapchain(window_state.logical_device, window_state.window_handle, surface_khr, surface_capabilities, &surface_device)
    defer vk.DestroySwapchainKHR(window_state.logical_device, swapchain_khr, nil)
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

    // Get images from swapchain
    swapchain_images: []vk.Image
    swapchain_image_views : []vk.ImageView
    defer delete(swapchain_images)
    defer for image_view in swapchain_image_views {
        vk.DestroyImageView(window_state.logical_device, image_view, nil)
    }

    {
        // Get image count
        image_count: u32
        vk.GetSwapchainImagesKHR(window_state.logical_device, swapchain_khr, &image_count,nil)

        // Allocate memmory to save images and views
        swapchain_images_size := size_of(vk.Image)*image_count
        swapchain_images_and_views_buffer, _ := mem.alloc_bytes(int(swapchain_images_size + size_of(vk.ImageView)*image_count))
        swapchain_images        = mem.slice_data_cast([]vk.Image,       swapchain_images_and_views_buffer[:swapchain_images_size])
        swapchain_image_views   = mem.slice_data_cast([]vk.ImageView,   swapchain_images_and_views_buffer[swapchain_images_size:])
        
        // Get images
        vk.GetSwapchainImagesKHR(window_state.logical_device, swapchain_khr, &image_count, raw_data(swapchain_images))

        // Create views and fill swapchain_image_views
        for swapchain_image, i in swapchain_images {
            view_create_info := vk.ImageViewCreateInfo {
                sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
                image = swapchain_image,
                viewType = vk.ImageViewType.D2,
                format = surface_device.surface_format.format,
                components = {.IDENTITY,.IDENTITY,.IDENTITY,.IDENTITY},
                subresourceRange = {{.COLOR}, 0,1,0,1},
            }

            // Create swapchain_image_views
            result_swapchain_image_view := vk.CreateImageView(window_state.logical_device, &view_create_info, nil, &swapchain_image_views[i])
            when ODIN_DEBUG { 
                if (result_swapchain_image_view != vk.Result.SUCCESS) {
                    panic("Creating image view failed")
                }
            }
        }
    }

    // Setup RenderPass
    renderpass: vk.RenderPass
    defer vk.DestroyRenderPass(window_state.logical_device, renderpass, nil)
    {
        attachment_description := vk.AttachmentDescription {
            format = surface_device.surface_format.format,
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
        result_renderpass := vk.CreateRenderPass(window_state.logical_device, &renderpass_createinfo, nil, &renderpass)
        when ODIN_DEBUG { 
            if (result_renderpass != vk.Result.SUCCESS) {
                panic("Creating renderpass failed")
            }
        }
    }

    // Set up Graphics Pipeline
    pipeline_layout: vk.PipelineLayout
    defer vk.DestroyPipelineLayout(window_state.logical_device, pipeline_layout, nil)
    pipeline: vk.Pipeline
    defer vk.DestroyPipeline(window_state.logical_device, pipeline, nil)
    {
        triangle_vert_shader_module, _ := CreateShaderModuleFromDevice("shaders_compiled/triangle_vert.spv", window_state.logical_device)
        defer vk.DestroyShaderModule(window_state.logical_device, triangle_vert_shader_module, nil)
        triangle_vert_shader_stage := vk.PipelineShaderStageCreateInfo {
            sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
            stage = {.VERTEX},
            module = triangle_vert_shader_module,
            pName = "main",
        }

        triangle_frag_shader_module, _ := CreateShaderModuleFromDevice("shaders_compiled/triangle_frag.spv", window_state.logical_device)
        defer vk.DestroyShaderModule(window_state.logical_device, triangle_frag_shader_module, nil)
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
        result_pipeline_layout := vk.CreatePipelineLayout(window_state.logical_device, &pipeline_layout_createinfo, nil, &pipeline_layout)
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

        result_pipeline := vk.CreateGraphicsPipelines(window_state.logical_device, 0, 1, &pipeline_createinfo, nil, &pipeline)
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
        vk.DestroyFramebuffer(window_state.logical_device, framebuffer, nil)
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
            result_framebuffers := vk.CreateFramebuffer(window_state.logical_device, &framebuffer_createinfo, nil, &framebuffers[i])
            when ODIN_DEBUG { 
                if (result_framebuffers != vk.Result.SUCCESS) {
                    panic("Creating framebuffer failed")
                }
            }
        }
    }

    // Create command buffer
    command_pool: vk.CommandPool
    defer vk.DestroyCommandPool(window_state.logical_device, command_pool, nil)
    command_buffers := make([]vk.CommandBuffer, len(framebuffers))
    defer delete(command_buffers)
    {
        command_pool_createinfo := vk.CommandPoolCreateInfo {
            sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = surface_device.family_index_graphics,
        }

        result_command_pool := vk.CreateCommandPool(window_state.logical_device, &command_pool_createinfo, nil, &command_pool)
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

        result_command_buffer := vk.AllocateCommandBuffers(window_state.logical_device, &command_buffers_info, raw_data(command_buffers))
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
    }

    // Create semaphores and fences
    semaphores_image_available: [FRAME_IN_Q_MAX]vk.Semaphore
    semaphores_render_finished: [FRAME_IN_Q_MAX]vk.Semaphore
    fences_from_bucket_index: [FRAME_IN_Q_MAX]vk.Fence
    fences_from_image_index:  [FRAME_IN_Q_MAX]vk.Fence // Borrow of fences_from_bucket_index
    defer for i in 0..<FRAME_IN_Q_MAX {
        vk.WaitForFences(window_state.logical_device, 1, &fences_from_bucket_index[i],false, c.UINT64_MAX)
        vk.DestroySemaphore(window_state.logical_device,semaphores_image_available[i],nil)
        vk.DestroySemaphore(window_state.logical_device,semaphores_render_finished[i],nil)
        vk.DestroyFence(window_state.logical_device,fences_from_bucket_index[i],nil)
    }
    {
        semaphore_createinfo := vk.SemaphoreCreateInfo{sType= vk.StructureType.SEMAPHORE_CREATE_INFO}
        fence_createinfo := vk.FenceCreateInfo{sType= vk.StructureType.FENCE_CREATE_INFO,flags={.SIGNALED}}

        for i in 0..<FRAME_IN_Q_MAX {
            result_semaphore_image_available := vk.CreateSemaphore(window_state.logical_device, &semaphore_createinfo, nil, &semaphores_image_available[i])
            result_semaphore_render_finished := vk.CreateSemaphore(window_state.logical_device, &semaphore_createinfo, nil, &semaphores_render_finished[i])
            when ODIN_DEBUG {
                if (result_semaphore_image_available != vk.Result.SUCCESS || result_semaphore_render_finished != vk.Result.SUCCESS) {
                    panic("Creating semaphores failed")
                }
            }

            result_fence_from_bucket_index := vk.CreateFence(window_state.logical_device, &fence_createinfo, nil, &fences_from_bucket_index[i])
            when ODIN_DEBUG {
                if (result_fence_from_bucket_index != vk.Result.SUCCESS) {
                    panic("Creating fence failed")
                }
            }
        }
    }

    time_start := time.tick_now()
    time_frame_last := time_start
    time_frame_current: time.Tick
    time_delta: f64 = 0

    current_bucket_index:u8 = 0
    // Main loop
    for !glfw.WindowShouldClose(window_state.window_handle) {
        time_frame_current = time.tick_now()
        time_delta = time.duration_seconds(time.tick_diff(time_frame_last, time_frame_current))
        glfw.PollEvents();

        // Draw frame
        {
            // Wait till bucket is ready
            vk.WaitForFences(window_state.logical_device, 1, &fences_from_bucket_index[current_bucket_index], false, c.UINT64_MAX)
            vk.ResetFences(window_state.logical_device, 1, &fences_from_bucket_index[current_bucket_index])

            // Acquire image to draw
            image_index: u32
            result_acquire_next_image := vk.AcquireNextImageKHR(window_state.logical_device, swapchain_khr, c.UINT64_MAX, semaphores_image_available[current_bucket_index], 0, &image_index)
            when ODIN_DEBUG {if result_acquire_next_image!= vk.Result.SUCCESS{fmt.println("Couldn't acquire next image: ", result_acquire_next_image)}}
            // Submit the command to draw
            wait_mask := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
            submit_info := vk.SubmitInfo {
                sType = vk.StructureType.SUBMIT_INFO,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &semaphores_image_available[current_bucket_index],
                pWaitDstStageMask = &wait_mask,
                commandBufferCount = 1,
                pCommandBuffers = &command_buffers[image_index],
                signalSemaphoreCount = 1,
                pSignalSemaphores = &semaphores_render_finished[current_bucket_index],
            }

            // Make sure to wait with submitting a queue for an image who's already in flight
            if fences_from_image_index[image_index] != 0 {
                vk.WaitForFences(window_state.logical_device, 1, &fences_from_image_index[image_index], false, c.UINT64_MAX)
            }
            
            result_queue_submit := vk.QueueSubmit(queue_graphics, 1, &submit_info, fences_from_bucket_index[current_bucket_index])
            when ODIN_DEBUG {
                if result_queue_submit != vk.Result.SUCCESS {
                    panic("Submitting queue failed")
                }
            }
            fences_from_image_index[image_index] = fences_from_bucket_index[current_bucket_index]
    
            // Present Result
            present_info := vk.PresentInfoKHR {
                sType = vk.StructureType.PRESENT_INFO_KHR,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &semaphores_render_finished[current_bucket_index],
                swapchainCount = 1,
                pSwapchains = &swapchain_khr,
                pImageIndices = &image_index,
            }
            result_queue_present_khr := vk.QueuePresentKHR(queue_presentation, &present_info)
            when ODIN_DEBUG {if result_queue_present_khr!= vk.Result.SUCCESS{fmt.println("Couldn't queue for presentation: ", result_queue_present_khr)}}

            current_bucket_index = (current_bucket_index+1)%FRAME_IN_Q_MAX
        }

        // After frame update
        fmt.println("Delta Seconds:", time_delta)
        time_frame_last = time_frame_current
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
    shader_bytes: []u8
    shader_bytes, success = os.read_entire_file(path)

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