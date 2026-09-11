# 窗口边界、关闭清理与应用图标

日期：2026-09-12。

## 聚焦时的黑色矩形外框

截图中的直角黑边位于圆角玻璃外侧。原实现将 `NSGlassEffectView` 直接设为无边框面板的根视图，启用了系统窗口阴影，但没有独立的透明圆角容器。结合截图，优先怀疑聚焦时窗口 backing surface 的系统阴影/轮廓，而非 SwiftUI 的圆角描边；尚未通过实机前后截图确认唯一成因。

修复使用公开 API：

- 关闭 `NSPanel.hasShadow`，将阴影移入自有透明 `ShelfSurfaceView`，通过明确的圆角 `shadowPath` 绘制，形状不随 key 状态改变。
- 玻璃视图和内容统一采用 24 pt 圆角裁剪，容器关闭自身的 focus ring；保留子控件、文件选择和键盘操作。
- 内容仍为 320 × 280 pt，四周各留 20 pt 透明阴影空间，面板实际为 360 × 320 pt；屏幕定位按实际面板尺寸限界。
- 继续使用系统玻璃材质及“减少透明度”适配。

相关公开接口：[NSWindow.hasShadow](https://developer.apple.com/documentation/appkit/nswindow/hasshadow)、[NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)、[NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview)。

## 关闭即清空

关闭按钮、Esc、⌘W、`close()`、`performClose(_:)` 及应用退出统一进入清理路径。窗口仍可复用，但列表、选择、投放高亮和提示立即重置；重新呼出为空。

关闭时同时拆除 SwiftUI 内容视图，下次展示时重新创建，避免隐藏的旧行视图继续持有条目快照和文件租约。

已有源文件始终仅移除引用，不删除或移动原文件。应用接收的 promise 副本使用 `ManagedFileDirectory` 管理唯一目录：

- 接收回调持有目录，保证来源应用仍在写入时目录有效。
- 文件访问租约持有目录，覆盖元数据、缩略图和出站文件承诺；关闭不会中断正在消费的文件。
- 清空先切换 store generation、取消超时任务并释放接收器，晚到结果无法重新加入列表。
- 回调不再强持有 receiver，避免 receiver 与回调互相持有而妨碍清理。
- 最后一个目录持有者释放后，在清理队列删除整个托管目录，包括多文件 promise；目录不含用户的源文件。

关闭期间仍在执行的外部写入/读取结束后才删除对应临时文件。进程被强制终止时无法保证执行析构清理，保留原有的历史目录过期回收兜底。复制到剪贴板的托管文件 URL 也会随关闭清理而失效；需要长期保存时应先拖出到 Finder。

## 图标

使用内置 imagegen 生成原创位图，设计为青绿色圆角底板、白色文件及薄荷玻璃托盘。没有文字、箭头或徽章，强调临时收纳文件。

- 主图：`Layby/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`。
- Xcode：配置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`，提供全部 macOS 16–1024 px 图标尺寸。
- 本地脚本：复制 `Config/AppIcon.icns`，设置 `CFBundleIconFile = AppIcon`，在签名前打包资源。
- 缩放采用 `sips`，ICNS 采用系统 `iconutil`；保留透明通道。

生成提示词（内置工具，未使用 CLI）：

> Create a polished minimalist macOS application icon for Layby, a temporary file shelf. A single white softly rounded document card, with a tiny folded top right corner and NO writing or horizontal lines, is partially tucked inside a simple rounded open tray. The tray is frosted pale mint glass. Front-facing, clean geometric silhouette, extremely readable at small sizes. Background is a teal rounded-square macOS app tile with subtle luminous gradient from lighter mint teal upper left to deep muted teal lower right. Restrained modern native macOS glass aesthetic, soft dimensional edges, no decorative sparkles, no arrows, no lettering, no logos, no badge, no extra objects. Center composition with generous balanced spacing. 1024 x 1024 square canvas. Tile occupies about 84 percent of canvas width, has smooth continuous rounded corners, with transparent background outside tile and only a very subtle contact shadow. Deliver the icon alone, not a presentation mockup.

## 验证

- macOS 27 SDK 的完整本地构建、签名通过。
- Xcode Debug 构建及 AppIcon 资源编译通过。Xcode 当前自带 SDK 26.5，仍有 target 27.0 超出已知范围的环境警告。
- 16 项测试通过，新增覆盖全部关闭入口、原文件保留、租约释放后临时文件删除，以及关闭后晚到 promise 不复活且被清理。
- 已检查 128 px 图标缩略效果、各资源像素尺寸以及构建产物的图标配置。
- 当前没有完成 WindowServer 聚焦前后画面对比；此前独立 UI 实例的 Computer Use 访问未获许可，因此不将编译和单元测试计为实机视觉验收。

实机复查：运行最新构建，分别点击停放区和其他窗口观察四角；拖入文件后逐一使用关闭按钮、Esc、⌘W，重新呼出确认空列表；在多文件接收过程中关闭后重新呼出，确认旧文件不回流；检查 header 拖动和正文投放仍正常。
