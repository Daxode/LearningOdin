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
    app_instance: vk.Instance,
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

    // Init glfw
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
    appplication_info := vk.ApplicationInfo {
        sType = vk.StructureType.APPLICATION_INFO,
        pApplicationName = "Hello Triangle",
        applicationVersion = vk.MAKE_VERSION(1,0,0),
        pEngineName = "Dax Engine",
        engineVersion = vk.MAKE_VERSION(1,0,0),
        apiVersion = vk.API_VERSION_1_0,
    }

    // Create Instance and External Debug Messenger
    debugMessengerEXT: vk.DebugUtilsMessengerEXT
    window_state.app_instance, debugMessengerEXT = CreateVulkanInstanceWithDebugMSG(&appplication_info, &window_state.exists_in_instance)
    defer vk.DestroyInstance(window_state.app_instance, nil)
    defer when ODIN_DEBUG {
        DestroyDebugUtilsMessengerEXT := vk.ProcDestroyDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(window_state.app_instance, "vkDestroyDebugUtilsMessengerEXT"));
        if (DestroyDebugUtilsMessengerEXT != nil) {
            DestroyDebugUtilsMessengerEXT(window_state.app_instance, debugMessengerEXT, nil);
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
    

    // Get images from swapchain
    swapchain_images, swapchain_image_views := CreateViewsForSwapChain(window_state.logical_device, swapchain_khr, surface_device.surface_format.format)
    defer delete(swapchain_images)
    defer for image_view in swapchain_image_views {
        vk.DestroyImageView(window_state.logical_device, image_view, nil)
    }

    // Setup RenderPass
    renderpass := CreateRenderPass(window_state.logical_device, surface_device.surface_format.format)
    defer vk.DestroyRenderPass(logical_device, renderpass, nil)

    // Set up Graphics Pipeline
    pipeline, pipeline_layout := CreatePipeline(window_state.logical_device, surface_extent, renderpass)
    defer vk.DestroyPipelineLayout(window_state.logical_device, pipeline_layout, nil)
    defer vk.DestroyPipeline(window_state.logical_device, pipeline, nil)

    // Create framebuffers
    framebuffers := CreateFrameBuffers(window_state.logical_device, renderpass, &swapchain_image_views, surface_extent)
    defer delete(framebuffers)
    defer for framebuffer in framebuffers {
        vk.DestroyFramebuffer(window_state.logical_device, framebuffer, nil)
    }

    // Create command buffer
    command_buffers, command_pool := CreateCommandBufferWithPool(logical_device, framebuffers, surface_device.family_index_graphics, surface_extent, renderpass, pipeline)
    defer vk.DestroyCommandPool(window_state.logical_device, command_pool, nil)
    defer delete(command_buffers)

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