package playing_with_vulkan

import "vendor:glfw"
import vk "vendor:vulkan"
import "core:time"

when #config(DAX_DEBUG_CMD, true) {
    DAX_DEBUG :: true
} else {DAX_DEBUG :: false}

u32set :: bit_set[u32(0)..<u32(32);u32]
u16set :: bit_set[u16(0)..<u16(16);u16]
u8set :: bit_set[u8(0)..<u8(8);u8]

VulkanInstanceExists :: struct {
    exists_vk_layer_khr_validation: b8,
    exists_vk_ext_debug_utils: b8,
}

SurfaceDevice :: struct {
    device_picked: vk.PhysicalDevice,
    surface_present_mode: vk.PresentModeKHR,
    surface_format: vk.SurfaceFormatKHR,
    family_index_graphics, family_index_presentation: u32,
}

FRAME_IN_Q_MAX : u8 : 6
FrameSyncHandles :: struct {
    semaphores_image_available: [FRAME_IN_Q_MAX]vk.Semaphore,
    semaphores_render_finished: [FRAME_IN_Q_MAX]vk.Semaphore,
    fences_from_bucket_index: [FRAME_IN_Q_MAX]vk.Fence,
    fences_from_image_index:  [FRAME_IN_Q_MAX]vk.Fence, // Borrow of fences_from_bucket_index
}

DeviceQueues :: struct {
    graphics, presentation: vk.Queue,
}

SwapchainData :: struct {
    swapchain_khr: vk.SwapchainKHR,
    surface_extent: vk.Extent2D,
    pipeline: vk.Pipeline, 
    pipeline_layout: vk.PipelineLayout,
    command_pool: vk.CommandPool,
    swapchain_buffers: SwapchainBuffers,
}

SwapchainBuffers :: struct {
    images:             []vk.Image, 
    image_views:        []vk.ImageView,
    framebuffers:       []vk.Framebuffer,
    command_buffers:    []vk.CommandBuffer,
}

Material :: struct {
    vertex: vk.ShaderModule,
    fragment: vk.ShaderModule,
}

GraphicsPipelineInfo :: struct {
    stage_vertex_createinfo, stage_fragment_createinfo: vk.PipelineShaderStageCreateInfo,
    
    viewport: vk.Viewport,
    scissor: vk.Rect2D,
    viewport_state_createinfo: vk.PipelineViewportStateCreateInfo,
    
    vertex_input_createinfo: vk.PipelineVertexInputStateCreateInfo,
    assembly_input_createinfo: vk.PipelineInputAssemblyStateCreateInfo, 
    rasterizer_createinfo: vk.PipelineRasterizationStateCreateInfo,
    
    multisampling_createinfo: vk.PipelineMultisampleStateCreateInfo,
    blend_alpha: vk.PipelineColorBlendAttachmentState,
    blend_createinfo: vk.PipelineColorBlendStateCreateInfo,
    
    //dynamic_states: [2]vk.DynamicState,
    //dynamic_state_createinfo: vk.PipelineDynamicStateCreateInfo,
    
    createinfo: vk.GraphicsPipelineCreateInfo,
}

// FrameDrawResult :: enum u8 {
//     SUCCESS,
//     FAILED_SWAPCHAIN_SWAP,
//     FAILED_ACQUIRE_NEXT_IMAGE,
//     FAILED_QUEUE_PRESENT,
// }

FrameState :: struct {
    time_start: time.Tick,
    time_frame_last: time.Tick,
    time_frame_current: time.Tick,
    time_delta: f64,
    current_bucket_index:u8,
}

ApplicationState :: struct { // Use for state not for argument passing with callback
    window_handle: glfw.WindowHandle,
    app_instance: vk.Instance,
    logical_device: vk.Device,
    
    surface_khr : vk.SurfaceKHR,
    surface_device: SurfaceDevice,
    renderpass_default: vk.RenderPass,
    device_queues: DeviceQueues,

    triangle_pipeline_info: GraphicsPipelineInfo,
    triangle_material: Material,
    
    should_swap: b8,
    frame_sync_handles: FrameSyncHandles,
    using swapchain_data: SwapchainData,
    using exists_in_instance: VulkanInstanceExists, // Only filled in debug
    using frame_state: FrameState,
}