object vgVulkanDataModule1: TvgVulkanDataModule1
  Instance = vgInstance1
  PhysicalDevice = vgPhysicalDevice1
  ScreenDevice = vgScreenRenderDevice1
  Linker = vgLinker1
  Renderer = vgRenderEngine_Single1
  Scene = vgScene1
  ToolManager = vgToolManager1
  Height = 385
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
    Left = 75
    Top = 32
  end
  object vgPhysicalDevice1: TvgPhysicalDevice
    DeviceSelect = vgdsAutomatic
    DeviceIndex = 0
    Instance = vgInstance1
    LogicalDevice = vgScreenRenderDevice1
    Left = 75
    Top = 112
  end
  object vgScreenRenderDevice1: TvgScreenRenderDevice
    PhysicalDevice = vgPhysicalDevice1
    DescriptorIndexingON = True
    DynamicRenderingON = True
    ShaderObjectsON = False
    Scene = vgScene1
    Left = 75
    Top = 192
  end
  object vgLinker1: TvgLinker
    ScreenDevice = vgScreenRenderDevice1
    Renderer = vgRenderEngine_Single1
    FrameCount = 3
    SwapChain.ImagesColorSpaces = <
      item
        ImageFormat = B8G8R8A8_UNORM
        ColorSpace = SRGB_NONLINEAR_KHR
      end
      item
        ImageFormat = B8G8R8A8_SRGB
        ColorSpace = SRGB_NONLINEAR_KHR
      end
      item
        ImageFormat = R8G8B8A8_UNORM
        ColorSpace = SRGB_NONLINEAR_KHR
      end
      item
        ImageFormat = R8G8B8A8_SRGB
        ColorSpace = SRGB_NONLINEAR_KHR
      end
      item
        ImageFormat = A2B10G10R10_UNORM_PACK32
        ColorSpace = SRGB_NONLINEAR_KHR
      end>
    SwapChain.PresentModes = <
      item
        PresentMode = PM_MAILBOX
      end
      item
        PresentMode = PM_FIFO
      end
      item
        PresentMode = PM_FIFO_RELAXED
      end
      item
        PresentMode = PM_IMMEDIATE
      end
      item
        PresentMode = PM_SHARED_DEMAND_REFRESH
      end
      item
        PresentMode = PM_SHARED_CONTINUOUS_REFRESH
      end>
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
    ToolManager = vgToolManager1
    RenderTarget = RT_SCREEN
    Left = 200
    Top = 32
  end
  object vgRenderEngine_Single1: TvgRenderEngine_Single
    Linker = vgLinker1
    RenderPass.Linker = vgLinker1
    RenderPass.Attachments = <
      item
        Name = 'MSAA'
        AttachType = atMSAA
        AttachmentIndex = 0
        LoadOp = LOAD_OP_CLEAR
        StoreOp = STORE_OP_DONT_CARE
        StencilLoadOp = LOAD_OP_DONT_CARE
        StencilStoreOp = STORE_OP_DONT_CARE
        InitialLayout = IMAGE_UNDEFINED
        FinalLayout = COLOR_ATTACHMENT_OPTIMAL
        Location = 0
        ImageBufferSize = 3
      end
      item
        Name = 'Screen_Attachment'
        AttachType = atScreen
        AttachmentIndex = 1
        LoadOp = LOAD_OP_DONT_CARE
        StoreOp = STORE_OP_STORE
        StencilLoadOp = LOAD_OP_DONT_CARE
        StencilStoreOp = STORE_OP_DONT_CARE
        InitialLayout = IMAGE_UNDEFINED
        FinalLayout = PRESENT_SRC_KHR
        Location = 0
        ImageBufferSize = 3
      end
      item
        Name = 'DepthStencil_Attachment'
        AttachType = atDepthStencil
        AttachmentIndex = 2
        LoadOp = LOAD_OP_CLEAR
        StoreOp = STORE_OP_DONT_CARE
        StencilLoadOp = LOAD_OP_CLEAR
        StencilStoreOp = STORE_OP_DONT_CARE
        InitialLayout = IMAGE_UNDEFINED
        FinalLayout = DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        Location = 0
        ImageBufferSize = 3
      end>
    RenderPass.SubPasses = <
      item
        Name = 'G_BUFFER'
        PipelineBindPoint = BP_GRAPHICS
        InputAttachments = <>
        ColorAttachments = <
          item
            Layout = COLOR_ATTACHMENT_OPTIMAL
            AttachmentIndex = 0
          end>
        ResolveAttachment = <
          item
            Layout = COLOR_ATTACHMENT_OPTIMAL
            AttachmentIndex = 1
          end>
        DepthStencilAttachment = <
          item
            Layout = DEPTH_STENCIL_ATTACHMENT_OPTIMAL
            AttachmentIndex = 2
          end>
        PreserveAttachments = <>
      end>
    RenderPass.SubPassDependencies = <
      item
        Name = 'Dependency_1'
        SrcStageMask = [EARLY_FRAGMENT_TESTS_BIT, COLOR_ATTACHMENT_OUTPUT_BIT]
        DstStageMask = [EARLY_FRAGMENT_TESTS_BIT, COLOR_ATTACHMENT_OUTPUT_BIT]
        SrcAccessMask = []
        DstAccessMask = [COLOR_ATTACHMENT_WRITE_BIT, DEPTH_STENCIL_ATTACHMENT_WRITE_BIT]
        DependencyFlags = [BY_REGION_BIT]
        SubPassLinks = (
          -1
          0)
      end
      item
        Name = 'Dependency_2'
        SrcStageMask = [EARLY_FRAGMENT_TESTS_BIT, COLOR_ATTACHMENT_OUTPUT_BIT]
        DstStageMask = [EARLY_FRAGMENT_TESTS_BIT, COLOR_ATTACHMENT_OUTPUT_BIT]
        SrcAccessMask = []
        DstAccessMask = [COLOR_ATTACHMENT_WRITE_BIT, DEPTH_STENCIL_ATTACHMENT_WRITE_BIT]
        DependencyFlags = [BY_REGION_BIT]
        SubPassLinks = (
          -1
          0)
      end
      item
        Name = 'Depth Dependency'
        SrcStageMask = [EARLY_FRAGMENT_TESTS_BIT, COLOR_ATTACHMENT_OUTPUT_BIT]
        DstStageMask = [EARLY_FRAGMENT_TESTS_BIT, COLOR_ATTACHMENT_OUTPUT_BIT]
        SrcAccessMask = []
        DstAccessMask = [COLOR_ATTACHMENT_WRITE_BIT, DEPTH_STENCIL_ATTACHMENT_WRITE_BIT]
        DependencyFlags = [BY_REGION_BIT]
        SubPassLinks = (
          -1
          0)
      end>
    RenderPass.ColourFormat = B8G8R8A8_UNORM
    RenderPass.DepthFormat = DB_D32_SFLOAT
    RenderPass.BufDepthON = True
    RenderPass.BufStencilON = False
    RenderPass.BufDepthCompare = CO_LESS_OR_EQUAL
    RenderPass.MSAASample = COUNT_04_BIT
    RenderPass.SubPassSet = [SPS_G_BUFFER]
    BaseScene = vgScene1
    GlobalRes.Descriptors = <
      item
        Name = 'ModelViewProj'
        DescriptorName = 'UBO_4x4MatrixS'
      end
      item
        Name = 'Lights'
        DescriptorName = 'StorageBuffer_Light'
      end>
    SelectMode = smNone
    MVPMatrixON = False
    ShaderUseDouble = False
    Scene = vgScene1
    Left = 360
    Top = 32
  end
  object vgScene1: TvgScene
    SceneState = SS_READY
    Linker = vgLinker1
    Left = 360
    Top = 112
  end
  object vgToolManager1: TvgToolManager
    Linker = vgLinker1
    MouseSensitivity = 0.400000005960464500
    Scene = vgScene1
    Renderer = vgRenderEngine_Single1
    ActionMode = TAM_CAMERA_ORBIT
    Left = 360
    Top = 192
  end
end
