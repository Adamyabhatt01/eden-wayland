// SPDX-FileCopyrightText: Copyright 2026 Eden Wayland Project
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Read-only probe: creates a real Wayland surface, then reports for every
// Vulkan physical device whether it can present on that surface, which queue
// family supports presentation, and which formats/present modes exist.
//
// It does not create a swapchain, render, or touch Eden data/counters.
//
// Build:
//   cc -O2 -o vk-present-probe tools/wayland/vk-present-probe.c $(pkg-config --cflags --libs wayland-client vulkan)
// Run:
//   ./vk-present-probe
//   prime-run ./vk-present-probe

#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VK_USE_PLATFORM_WAYLAND_KHR
#include <vulkan/vulkan.h>
#include <wayland-client.h>

struct registry_state {
    struct wl_compositor *compositor;
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    struct registry_state *state = data;
    if (strcmp(interface, wl_compositor_interface.name) != 0) {
        return;
    }
    const uint32_t bind_version = version < 4 ? version : 4;
    state->compositor =
        wl_registry_bind(registry, name, &wl_compositor_interface, bind_version);
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static const char *device_type_name(VkPhysicalDeviceType type) {
    switch (type) {
    case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:
        return "integrated";
    case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:
        return "discrete";
    case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:
        return "virtual";
    case VK_PHYSICAL_DEVICE_TYPE_CPU:
        return "cpu";
    default:
        return "other";
    }
}

static int has_device_extension(VkPhysicalDevice device, const char *wanted) {
    uint32_t count = 0;
    if (vkEnumerateDeviceExtensionProperties(device, NULL, &count, NULL) != VK_SUCCESS) {
        return 0;
    }
    VkExtensionProperties *props = calloc(count, sizeof(*props));
    if (props == NULL) {
        return 0;
    }
    if (vkEnumerateDeviceExtensionProperties(device, NULL, &count, props) != VK_SUCCESS) {
        free(props);
        return 0;
    }
    int found = 0;
    for (uint32_t i = 0; i < count; ++i) {
        if (strcmp(props[i].extensionName, wanted) == 0) {
            found = 1;
            break;
        }
    }
    free(props);
    return found;
}

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL) {
        fprintf(stderr, "FAIL: cannot connect to a Wayland display\n");
        return 1;
    }

    struct registry_state state = {0};
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, &state);
    wl_display_roundtrip(display);
    if (state.compositor == NULL) {
        fprintf(stderr, "FAIL: wl_compositor is not available\n");
        wl_registry_destroy(registry);
        wl_display_disconnect(display);
        return 1;
    }

    struct wl_surface *surface = wl_compositor_create_surface(state.compositor);
    if (surface == NULL) {
        fprintf(stderr, "FAIL: cannot create a wl_surface\n");
        wl_registry_destroy(registry);
        wl_display_disconnect(display);
        return 1;
    }

    VkApplicationInfo app_info = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "eden-wayland-vk-present-probe",
        .applicationVersion = 1,
        .pEngineName = "none",
        .engineVersion = 1,
        .apiVersion = VK_API_VERSION_1_1,
    };
    const char *extensions[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
    };
    VkInstanceCreateInfo instance_info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = 2,
        .ppEnabledExtensionNames = extensions,
    };
    VkInstance instance = VK_NULL_HANDLE;
    VkResult result = vkCreateInstance(&instance_info, NULL, &instance);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "FAIL: vkCreateInstance: %d\n", result);
        wl_surface_destroy(surface);
        wl_registry_destroy(registry);
        wl_display_disconnect(display);
        return 1;
    }

    VkWaylandSurfaceCreateInfoKHR surface_info = {
        .sType = VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .display = display,
        .surface = surface,
    };
    VkSurfaceKHR vk_surface = VK_NULL_HANDLE;
    result = vkCreateWaylandSurfaceKHR(instance, &surface_info, NULL, &vk_surface);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "FAIL: vkCreateWaylandSurfaceKHR: %d\n", result);
        vkDestroyInstance(instance, NULL);
        wl_surface_destroy(surface);
        wl_registry_destroy(registry);
        wl_display_disconnect(display);
        return 1;
    }

    uint32_t device_count = 0;
    vkEnumeratePhysicalDevices(instance, &device_count, NULL);
    VkPhysicalDevice *devices = calloc(device_count ? device_count : 1, sizeof(*devices));
    if (devices == NULL || device_count == 0) {
        fprintf(stderr, "FAIL: no Vulkan physical devices\n");
        free(devices);
        vkDestroySurfaceKHR(instance, vk_surface, NULL);
        vkDestroyInstance(instance, NULL);
        wl_surface_destroy(surface);
        wl_registry_destroy(registry);
        wl_display_disconnect(display);
        return 1;
    }
    vkEnumeratePhysicalDevices(instance, &device_count, devices);

    int present_capable = 0;
    printf("Wayland surface: created (VK_KHR_wayland_surface)\n");
    for (uint32_t i = 0; i < device_count; ++i) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(devices[i], &props);

        uint32_t family_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &family_count, NULL);
        VkQueueFamilyProperties *families = calloc(family_count ? family_count : 1,
                                                   sizeof(*families));
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &family_count, families);

        int present_family = -1;
        VkBool32 family_present = VK_FALSE;
        VkBool32 family_wayland = VK_FALSE;
        VkQueueFlags present_flags = 0;
        for (uint32_t f = 0; f < family_count; ++f) {
            VkBool32 wayland_support =
                vkGetPhysicalDeviceWaylandPresentationSupportKHR(devices[i], f, display);
            VkBool32 surface_support = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(devices[i], f, vk_surface, &surface_support);
            if (surface_support && present_family < 0) {
                present_family = (int)f;
                family_present = surface_support;
                family_wayland = wayland_support;
                present_flags = families[f].queueFlags;
            }
        }
        free(families);

        printf("\nGPU%u: %s [%s] vendor=0x%04x api=%u.%u.%u\n", i, props.deviceName,
               device_type_name(props.deviceType), props.vendorID, VK_API_VERSION_MAJOR(props.apiVersion),
               VK_API_VERSION_MINOR(props.apiVersion), VK_API_VERSION_PATCH(props.apiVersion));
        printf("  swapchain extension: %s\n",
               has_device_extension(devices[i], VK_KHR_SWAPCHAIN_EXTENSION_NAME) ? "yes" : "no");
        printf("  present family: %s", present_family >= 0 ? "yes" : "no");
        if (present_family >= 0) {
            printf(" (index %d, surface=%u wayland=%u graphics=%s)", present_family,
                   (unsigned)family_present, (unsigned)family_wayland,
                   (present_flags & VK_QUEUE_GRAPHICS_BIT) ? "yes" : "no");
        }
        printf("\n");

        if (present_family < 0) {
            continue;
        }
        present_capable = 1;

        VkSurfaceCapabilitiesKHR caps;
        if (vkGetPhysicalDeviceSurfaceCapabilitiesKHR(devices[i], vk_surface, &caps) == VK_SUCCESS) {
            printf("  images: min=%u max=%u current=%ux%u\n", caps.minImageCount,
                   caps.maxImageCount, caps.currentExtent.width, caps.currentExtent.height);
            printf("  supported usage: 0x%x composite alpha: 0x%x\n",
                   (unsigned)caps.supportedUsageFlags, (unsigned)caps.supportedCompositeAlpha);
        }

        uint32_t format_count = 0;
        vkGetPhysicalDeviceSurfaceFormatsKHR(devices[i], vk_surface, &format_count, NULL);
        VkSurfaceFormatKHR *formats = calloc(format_count ? format_count : 1, sizeof(*formats));
        vkGetPhysicalDeviceSurfaceFormatsKHR(devices[i], vk_surface, &format_count, formats);
        printf("  formats (%u):", format_count);
        for (uint32_t f = 0; f < format_count && f < 6; ++f) {
            printf(" %u/%u", (unsigned)formats[f].format, (unsigned)formats[f].colorSpace);
        }
        if (format_count > 6) {
            printf(" ...");
        }
        printf("\n");
        free(formats);

        uint32_t mode_count = 0;
        vkGetPhysicalDeviceSurfacePresentModesKHR(devices[i], vk_surface, &mode_count, NULL);
        VkPresentModeKHR *modes = calloc(mode_count ? mode_count : 1, sizeof(*modes));
        vkGetPhysicalDeviceSurfacePresentModesKHR(devices[i], vk_surface, &mode_count, modes);
        printf("  present modes (%u):", mode_count);
        for (uint32_t m = 0; m < mode_count; ++m) {
            switch (modes[m]) {
            case VK_PRESENT_MODE_IMMEDIATE_KHR:
                printf(" immediate");
                break;
            case VK_PRESENT_MODE_MAILBOX_KHR:
                printf(" mailbox");
                break;
            case VK_PRESENT_MODE_FIFO_KHR:
                printf(" fifo");
                break;
            case VK_PRESENT_MODE_FIFO_RELAXED_KHR:
                printf(" fifo_relaxed");
                break;
            default:
                printf(" %u", (unsigned)modes[m]);
                break;
            }
        }
        printf("\n");
        free(modes);
    }

    free(devices);
    vkDestroySurfaceKHR(instance, vk_surface, NULL);
    vkDestroyInstance(instance, NULL);
    wl_surface_destroy(surface);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);

    printf("\nResult: %s\n", present_capable ? "at least one GPU can present on Wayland"
                                             : "no GPU can present on this Wayland surface");
    return present_capable ? 0 : 2;
}
