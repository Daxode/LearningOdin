package playing_with_vulkan

import vk "vendor:vulkan"

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