object vgVulkanDataModule1: TvgVulkanDataModule1
  Instance = vgInstance1
  PhysicalDevice = vgPhysicalDevice1
  ScreenDevice = vgScreenRenderDevice1
  Linker = vgLinker1
  Height = 480
  Width = 640
  object vgInstance1: TvgInstance
    ApplicationName = 'Vulkan Graphics'
    APIVersion = VG_API_VERSION_1_3
    EngineName = 'Vulkan Graphics Engine'
    Extensions = <
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_device_group_creation'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '23'
        ExtImplementationProp = 'VK_KHR_display'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_external_fence_capabilities'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_external_memory_capabilities'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_external_semaphore_capabilities'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_get_display_properties2'
      end
      item
        ExtMode = VGE_MUST_HAVE
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '2'
        ExtImplementationProp = 'VK_KHR_get_physical_device_properties2'
      end
      item
        ExtMode = VGE_MUST_HAVE
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_get_surface_capabilities2'
      end
      item
        ExtMode = VGE_MUST_HAVE
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '25'
        ExtImplementationProp = 'VK_KHR_surface'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_surface_maintenance1'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_surface_protected_capabilities'
      end
      item
        ExtMode = VGE_MUST_HAVE
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '6'
        ExtImplementationProp = 'VK_KHR_win32_surface'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '10'
        ExtImplementationProp = 'VK_EXT_debug_report'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '2'
        ExtImplementationProp = 'VK_EXT_debug_utils'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_EXT_direct_mode_display'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_EXT_surface_maintenance1'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '5'
        ExtImplementationProp = 'VK_EXT_swapchain_colorspace'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_NV_external_memory_capabilities'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_KHR_portability_enumeration'
      end
      item
        ExtLayerIndexProp = '4294967295'
        ExtSpecVersionProp = '1'
        ExtImplementationProp = 'VK_LUNARG_direct_driver_loading'
      end>
    Layers = <
      item
        Description = 'NVIDIA Optimus layer'
        LayerNameProp = 'VK_LAYER_NV_optimus'
        LaySpecVersionProp = '4211029'
        LayImplementationProp = '1'
      end
      item
        Description = 'NVIDIA Presentation Layer'
        LayerNameProp = 'VK_LAYER_NV_present'
        LaySpecVersionProp = '4211029'
        LayImplementationProp = '1'
      end
      item
        Description = 'Steam Overlay Layer'
        LayerNameProp = 'VK_LAYER_VALVE_steam_overlay'
        LaySpecVersionProp = '4202632'
        LayImplementationProp = '1'
      end
      item
        Description = 'Steam Pipeline Caching Layer'
        LayerNameProp = 'VK_LAYER_VALVE_steam_fossilize'
        LaySpecVersionProp = '4202632'
        LayImplementationProp = '1'
      end
      item
        Description = 'Debugging capture layer for RenderDoc'
        LayerNameProp = 'VK_LAYER_RENDERDOC_Capture'
        LaySpecVersionProp = '4211012'
        LayImplementationProp = '46'
      end>
    RenderToScreen = True
    DescriptorIndexing = False
    DynamicRendering = True
    Left = 56
    Top = 32
  end
  object vgPhysicalDevice1: TvgPhysicalDevice
    DeviceSelect = vgdsAutomatic
    DeviceIndex = 0
    Instance = vgInstance1
    LogicalDevice = vgScreenRenderDevice1
    Left = 136
    Top = 152
  end
  object vgScreenRenderDevice1: TvgScreenRenderDevice
    PhysicalDevice = vgPhysicalDevice1
    DescriptorIndexingON = True
    DynamicRenderingON = True
    ShaderObjectsON = False
    Left = 160
    Top = 304
  end
  object vgLinker1: TvgLinker
    ScreenDevice = vgScreenRenderDevice1
    FrameCount = 3
    SwapChain.ImagesColorSpaces = <>
    SwapChain.PresentModes = <>
    SwapChain.ImageSharingMode = SM_EXCLUSIVE
    SwapChain.ImageUsage = [IU_TRANSFER_SRC, IU_TRANSFER_DST, IU_COLOR_ATTACHMENT]
    SwapChain.CompositeAlpha = [CA_OPAQUE]
    SwapChain.ForceCompositeAlpha = False
    SwapChain.Clipped = True
    SwapChain.SRGB = True
    SwapChain.ImageViewType = IVT_2D
    SwapChain.ComponentRed = CS_IDENTITY
    SwapChain.ComponentGreen = CS_IDENTITY
    SwapChain.ComponentBlue = CS_IDENTITY
    SwapChain.ComponentAlpha = CS_IDENTITY
    SwapChain.ImageAspectFlags = [IA_COLOR_BIT]
    RenderTarget = RT_SCREEN
    Left = 328
    Top = 128
  end
end
