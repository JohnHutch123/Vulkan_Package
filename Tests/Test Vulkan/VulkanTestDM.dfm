object vgVulkanDataModule1: TvgVulkanDataModule1
  Instance = vgInstance1
  PhysicalDevice = vgPhysicalDevice1
  ScreenDevice = vgScreenDevice1
  Linker = vgLinker1
  Renderer = vgRenderer1
  Scene = vgScene1
  ToolManager = vgToolManager1
  Height = 480
  Width = 640
  object vgInstance1: TvgInstance
    ApplicationName = 'Vulkan Graphics'
    APIVersion = VG_API_VERSION_1_3
    EngineName = 'Vulkan Graphics Engine'
    Extensions = <>
    Layers = <>
    RenderToScreen = True
    DescriptorIndexing = False
    DynamicRendering = True
    Left = 32
    Top = 32
  end
  object vgPhysicalDevice1: TvgPhysicalDevice
    DeviceSelect = vgdsAutomatic
    DeviceIndex = 0
    Instance = vgInstance1
    LogicalDevice = vgScreenDevice1
    Left = 32
    Top = 112
  end
  object vgScreenDevice1: TvgScreenRenderDevice
    PhysicalDevice = vgPhysicalDevice1
    DescriptorIndexingON = True
    DynamicRenderingON = True
    ShaderObjectsON = False
    Scene = vgScene1
    Left = 32
    Top = 192
  end
  object vgLinker1: TvgLinker
    ScreenDevice = vgScreenDevice1
    Renderer = vgRenderer1
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
    ToolManager = vgToolManager1
    RenderTarget = RT_SCREEN
    Left = 232
    Top = 32
  end
  object vgRenderer1: TvgRenderEngine_Single
    Linker = vgLinker1
    RenderPass.Linker = vgLinker1
    RenderPass.Attachments = <>
    RenderPass.SubPasses = <>
    RenderPass.SubPassDependencies = <>
    RenderPass.ColourFormat = UNDEFINED
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
    Left = 432
    Top = 32
  end
  object vgScene1: TvgScene
    SceneState = SS_READY
    Linker = vgLinker1
    Left = 432
    Top = 112
  end
  object vgToolManager1: TvgToolManager
    Linker = vgLinker1
    MouseSensitivity = 0.400000005960464500
    Scene = vgScene1
    Renderer = vgRenderer1
    ActionMode = TAM_CAMERA_ORBIT
    Left = 432
    Top = 192
  end
end
