# Layby · Icon Composer SVG 分层套装

这套图形延续现有 Layby 图标的语义：一张白色文件暂存在薄荷色托盘中。素材采用 Icon Composer 需要的平面、实色源图形；圆角图标蒙版、背景渐变、Liquid Glass、投影和高光在 Icon Composer 中完成。

## 文件

`layers/` 中的 4 个文件才是导入素材。它们都是 1024 × 1024、使用相同坐标的完整画布，导入后会自动保持对齐。

| 深度组（由后向前） | SVG | 建议颜色 | 建议材质 |
| --- | --- | --- | --- |
| 1 · Rear Tray | `01-tray-rear.svg` | `#61CDB7` | Liquid Glass 开；较低透明度；轻阴影 |
| 2 · Document | `02-document.svg` | `#F5F9F7` | Liquid Glass 关；中等阴影 |
| 2 · Document | `03-document-fold.svg` | `#DCEDEA` | 与文件主体同组；无独立阴影 |
| 3 · Front Tray | `04-tray-front.svg` | `#96E3D0` | Liquid Glass 开；中等透明度；轻阴影 |

`Layby-master.svg` 是便于继续修改的合成母版，不要作为单一图层导入。`preview/Layby-preview.svg` 只用于预览完整构图，里面的背景、渐变、描边和阴影也不要导入。

## 导入步骤

1. 在 Icon Composer 新建图标，启用 iOS、iPadOS 和 macOS；画布保持 1024。
2. 在 Canvas 中设置背景渐变。默认外观可从左上 `#6DE6CE` 渐变至右下 `#075064`；深色外观可用 `#0B5360` 至 `#052F3A`。
3. 建立 3 个组，按 `Rear Tray → Document → Front Tray` 从后向前排列。
4. 将 `01-tray-rear.svg` 放入第 1 组；将 `02-document.svg` 和 `03-document-fold.svg` 依文件名顺序放入第 2 组；将 `04-tray-front.svg` 放入第 3 组。
5. 先在默认外观中调整玻璃强度和阴影，再检查 Dark、Clear 和 Tinted。Mono 外观建议让 Icon Composer 自动着色，文件主体保持最亮层级。
6. 在 16 px、32 px 和 64 px 预览尺寸检查折角和托盘凹口；若小尺寸显得拥挤，将整个构图等比缩至 94%–96%，不要分别移动图层。

不要额外导入圆角矩形作为底板。Icon Composer 会按平台应用正确的图标蒙版和边缘高光。
