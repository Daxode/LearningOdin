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

main::proc()
{
    load_vulkan_function_pointers()
    
    when ODIN_DEBUG {
        fmt.println("debug enabled")
    }

    application_state: ApplicationState
    using application_state

    // Init glfw
    glfw.Init();
    defer glfw.Terminate();
    
    // Create GLFW Window
    application_state.window_handle = CreateWindowWithCallbacksAndIcon()
    defer glfw.DestroyWindow(application_state.window_handle)
    glfw.SetWindowUserPointer(application_state.window_handle, &application_state)

    // Check validation layers and for VK_EXT_debug_utils
    when ODIN_DEBUG {
        application_state.exists_in_instance = CheckVulkanInstanceExistence()
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
    application_state.app_instance, debugMessengerEXT = CreateVulkanInstanceWithDebugMSG(&appplication_info, &application_state.exists_in_instance)
    defer vk.DestroyInstance(application_state.app_instance, nil)
    defer when ODIN_DEBUG {
        DestroyDebugUtilsMessengerEXT := vk.ProcDestroyDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(application_state.app_instance, "vkDestroyDebugUtilsMessengerEXT"));
        if (DestroyDebugUtilsMessengerEXT != nil) {
            DestroyDebugUtilsMessengerEXT(application_state.app_instance, debugMessengerEXT, nil);
        }
    }

    // Get window surface
    defer vk.DestroySurfaceKHR(app_instance, surface_khr, nil)
    {
        resultCreateWindowSurface := glfw.CreateWindowSurface(app_instance, application_state.window_handle, nil, &surface_khr)
        when ODIN_DEBUG { 
            if (resultCreateWindowSurface != vk.Result.SUCCESS) {
                panic("Creating window surface failed")
            }
        }
    }

    // Pick the physical device
    surface_device = GetOptimalSurfaceDevice(app_instance, surface_khr)
    logical_device = CreateDevice(surface_device, application_state.exists_vk_layer_khr_validation)
    renderpass_default = CreateRenderPass(logical_device, surface_device.surface_format.format)
    defer vk.DestroyDevice(logical_device, nil)
    defer vk.DestroyRenderPass(logical_device, renderpass_default, nil)
    
    // Get Queues
    vk.GetDeviceQueue(application_state.logical_device, surface_device.family_index_graphics, 0, &device_queues.graphics)
    vk.GetDeviceQueue(application_state.logical_device, surface_device.family_index_presentation, 0, &device_queues.presentation)
    
    // Create swapchain
    triangle_material.vertex, _ = CreateShaderModuleFromDevice("shaders_compiled/triangle_vert.spv", logical_device)
    triangle_material.fragment, _ = CreateShaderModuleFromDevice("shaders_compiled/triangle_frag.spv", logical_device)
    defer vk.DestroyShaderModule(logical_device, triangle_material.vertex,nil)
    defer vk.DestroyShaderModule(logical_device, triangle_material.fragment,nil)

    UpdateSwapchainData(logical_device, window_handle, surface_khr, &surface_device, renderpass_default, triangle_material, &triangle_pipeline_info, true, &application_state.swapchain_data)
    defer delete(swapchain_buffers.images)
    defer vk.DestroyPipelineLayout(logical_device, pipeline_layout, nil)
    defer DestroySwapchainData(application_state.logical_device, application_state.swapchain_data)
    
    // Create semaphores and fences
    frame_sync_handles = CreateFrameSyncHandles(application_state.logical_device) 
    defer for i in 0..<FRAME_IN_Q_MAX {
        vk.WaitForFences(application_state.logical_device, 1, &frame_sync_handles.fences_from_bucket_index[i],false, c.UINT64_MAX)
        vk.DestroySemaphore(application_state.logical_device,frame_sync_handles.semaphores_image_available[i],nil)
        vk.DestroySemaphore(application_state.logical_device,frame_sync_handles.semaphores_render_finished[i],nil)
        vk.DestroyFence(application_state.logical_device,frame_sync_handles.fences_from_bucket_index[i],nil)
    }

    CreateFrameSyncHandles::proc(logical_device: vk.Device)->(frame_sync_handles: FrameSyncHandles){
        semaphore_createinfo := vk.SemaphoreCreateInfo{sType= vk.StructureType.SEMAPHORE_CREATE_INFO}
        fence_createinfo := vk.FenceCreateInfo{sType= vk.StructureType.FENCE_CREATE_INFO,flags={.SIGNALED}}

        for i in 0..<FRAME_IN_Q_MAX {
            result_semaphore_image_available := vk.CreateSemaphore(logical_device, &semaphore_createinfo, nil, &frame_sync_handles.semaphores_image_available[i])
            result_semaphore_render_finished := vk.CreateSemaphore(logical_device, &semaphore_createinfo, nil, &frame_sync_handles.semaphores_render_finished[i])
            when ODIN_DEBUG {
                if (result_semaphore_image_available != vk.Result.SUCCESS || result_semaphore_render_finished != vk.Result.SUCCESS) {
                    panic("Creating semaphores failed")
                }
            }

            result_fence_from_bucket_index := vk.CreateFence(logical_device, &fence_createinfo, nil, &frame_sync_handles.fences_from_bucket_index[i])
            when ODIN_DEBUG {
                if (result_fence_from_bucket_index != vk.Result.SUCCESS) {
                    panic("Creating fence failed")
                }
            }
        }
        return
    }

    time_start = time.tick_now()
    time_frame_last = time_start
    // Main loop
    for !glfw.WindowShouldClose(application_state.window_handle) {
        UpdateFrame(&application_state, true)
    }

}

// Based on the given logical device, 
// it loads the given path to a SPIR-V, 
// and creates a shader module on the device
CreateShaderModuleFromDevice :: proc(path: string, device: vk.Device, allocator := context.allocator) -> (shader_module: vk.ShaderModule, success: bool) {
    shader_bytes: []u8
    shader_bytes, success = os.read_entire_file(path, allocator)

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