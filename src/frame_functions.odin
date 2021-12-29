package playing_with_vulkan

import "core:c"
import "core:fmt"
import vk "vendor:vulkan"
import "core:time"
import "vendor:glfw"

DrawFrame::proc(logical_device: vk.Device, 
                frame_sync_handles: ^FrameSyncHandles, 
                swapchain_khr: ^vk.SwapchainKHR, 
                device_queues: DeviceQueues, 
                command_buffers: ^[]vk.CommandBuffer, 
                current_bucket_index: ^u8, 
                application_state: ^ApplicationState) {
    defer current_bucket_index^ = (current_bucket_index^+1)%FRAME_IN_Q_MAX

    // Wait till bucket is ready
    vk.WaitForFences(logical_device, 1, &frame_sync_handles.fences_from_bucket_index[current_bucket_index^], false, c.UINT64_MAX)
    vk.ResetFences(logical_device, 1, &frame_sync_handles.fences_from_bucket_index[current_bucket_index^])
    
    // Acquire image to draw
    image_index: u32
    result_acquire_next_image := vk.AcquireNextImageKHR(logical_device, swapchain_khr^, c.UINT64_MAX, frame_sync_handles.semaphores_image_available[current_bucket_index^], 0, &image_index)
    when DAX_DEBUG {if result_acquire_next_image!= vk.Result.SUCCESS{fmt.println("Couldn't acquire next image: ", result_acquire_next_image)}}
    
    // Submit the command to draw
    wait_mask := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
    submit_info := vk.SubmitInfo {
        sType = vk.StructureType.SUBMIT_INFO,
        waitSemaphoreCount = 1,
        pWaitSemaphores = &frame_sync_handles.semaphores_image_available[current_bucket_index^],
        pWaitDstStageMask = &wait_mask,
        commandBufferCount = 1,
        pCommandBuffers = &command_buffers[image_index],
        signalSemaphoreCount = 1,
        pSignalSemaphores = &frame_sync_handles.semaphores_render_finished[current_bucket_index^],
    }

    // Make sure to wait with submitting a queue for an image who's already in flight
    if frame_sync_handles.fences_from_image_index[image_index] != 0 {
        vk.WaitForFences(logical_device, 1, &frame_sync_handles.fences_from_image_index[image_index], false, c.UINT64_MAX)
    }
    
    result_queue_submit := vk.QueueSubmit(device_queues.graphics, 1, &submit_info, frame_sync_handles.fences_from_bucket_index[current_bucket_index^])
    when DAX_DEBUG {
        if result_queue_submit != vk.Result.SUCCESS {
            panic("Submitting queue failed")
        }
    }
    frame_sync_handles.fences_from_image_index[image_index] = frame_sync_handles.fences_from_bucket_index[current_bucket_index^]

    // Present Result
    present_info := vk.PresentInfoKHR {
        sType = vk.StructureType.PRESENT_INFO_KHR,
        waitSemaphoreCount = 1,
        pWaitSemaphores = &frame_sync_handles.semaphores_render_finished[current_bucket_index^],
        swapchainCount = 1,
        pSwapchains = swapchain_khr,
        pImageIndices = &image_index,
    }
    result_queue_present_khr := vk.QueuePresentKHR(device_queues.presentation, &present_info)
    if result_queue_present_khr == vk.Result.ERROR_OUT_OF_DATE_KHR || application_state.should_swap {
        SwapSwapchain(application_state)
        return
    } else {when DAX_DEBUG {if result_queue_present_khr!= vk.Result.SUCCESS{fmt.println("Couldn't queue for presentation: ", result_queue_present_khr)}}}
}

UpdateFrame::proc(using application_state: ^ApplicationState, $should_draw: b8) {
    time_frame_current = time.tick_now()
    time_delta = time.duration_seconds(time.tick_diff(time_frame_last, time_frame_current))
    glfw.PollEvents();

    // Draw frame
    when should_draw {
        DrawFrame(application_state.logical_device, &frame_sync_handles, &swapchain_khr, device_queues, &swapchain_buffers.command_buffers, &current_bucket_index, application_state)
    }

    fmt.println("Delta Seconds:", time_delta)
    time_frame_last = time_frame_current
}