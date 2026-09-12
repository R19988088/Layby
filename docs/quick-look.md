# 文件快速查看

列表与网格视图中，选中文件后按空格打开 macOS 原生快速查看；按住 Command 可选择多个文件，然后一起预览。右键文件的“快速查看”菜单会预览该文件。没有选中文件、文件仍在接收或不可用时，不启动预览。堆叠视图仍用于整体拖出文件。

预览打开时再次按空格或 Esc 只关闭预览，停放区的文件保留。关闭停放区会先结束预览，再按原有逻辑清理文件；切回堆叠、清空选择或移除全部预览文件也结束预览。预览期间更改选择会更新预览内容。界面入口随应用的中英文设置切换。

## 实现

- `ShelfQuickLookController` 接入系统共享的 `QLPreviewPanel`，提供数据源并管理预览会话。`ShelfPanel` 通过 AppKit 响应链的接管与释放回调设置数据源和代理，遵守只能修改自己控制的预览面板的约束。
- `ShelfPanel` 和文件拖拽视图处理无修饰键的空格；预览期间的本地事件监听仅处理本应用停放区与预览面板的事件，不注册全局空格快捷键。按键重复不会反复开关窗口。
- `ShelfStore.previewItems` 只返回展开状态下选中的就绪文件，按停放区顺序提供。文件、选择与展示模式改变时同步更新预览。
- `ShelfPreviewItem` 保留 `FileAccessLease`，让沙盒文件访问权限与接收文件的临时目录在系统读取期间保持有效。退出预览后释放数据源项目及缓存；最后一个读取者释放后，既有临时文件回收机制负责删除托管目录，原文件不被删除。
- 继续使用 accessory 应用模式；快速查看不改变应用的 Dock 显示策略。

## 验证

自动化测试覆盖就绪文件筛选、网格/列表与堆叠的预览边界、临时文件的读取和释放、组合键与按键重复过滤，以及 Esc 优先关闭预览。

在已登录的 macOS 桌面运行 `bash scripts/test-quick-look.sh`，可验证真实沙盒 AppKit 应用中列表和网格文件行接收空格后打开系统面板、传入正确文件、Esc/空格关闭、再次打开，以及关闭停放区后的清理。测试短暂显示窗口，仅使用自行生成的测试文件。不同格式的渲染、多选浏览和右键菜单仍可做人工验收。

### 首次空格无法打开的修复

原实现先对隐藏的 `QLPreviewPanel` 调用 `updateController()`，随后要求 `beginPreviewPanelControl` 已完成，才显示窗口。原生面板在这一阶段尚未进入接管流程，导致提前返回；空格被当作未处理输入，触发系统提示音。修复后先让原生面板显示、进入响应链接管流程，在 `beginControl` 内设置并加载数据源，再检查接管结果。真实事件循环测试在修复前复现了列表和网格失败，修复后两种视图均能打开和重开预览。

系统 API 参考：[QLPreviewPanel](https://developer.apple.com/documentation/quicklookui/qlpreviewpanel)、[currentController](https://developer.apple.com/documentation/quicklookui/qlpreviewpanel/currentcontroller)、[QLPreviewItem](https://developer.apple.com/documentation/quicklookui/qlpreviewitem)。
