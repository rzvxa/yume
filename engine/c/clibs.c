#include "SDL3/SDL.h"
#include "SDL3/SDL_vulkan.h"

#include "stb_image.h"

#include "vk_mem_alloc.h"
#include "vulkan/vulkan.h"

#include "cimgui.h"
#include "cimgui_impl_sdl3.h"
#include "cimgui_impl_vulkan.h"
#include "cimgui_internal.h"

#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#include "cimguizmo.h"
#undef CIMGUI_DEFINE_ENUMS_AND_STRUCTS

#define FLECS_CONFIG_HEADER
#include "flecs.h"
#undef FLECS_CONFIG_HEADER

#define UFBX_CONFIG_HEADER "ufbx_config.h"
#include "ufbx.h"
#undef UFBX_CONFIG_HEADER
