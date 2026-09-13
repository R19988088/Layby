# 文件 Services

堆叠顶部右侧的向下箭头打开原生 Services 菜单，始终针对根层全部文件。堆叠底部的文件数量按钮继续进入网格/列表。列表、网格及其文件夹内容使用原生右键菜单：右键已选文件保留多选；右键未选文件先单独选中它。原有快速查看、Finder 定位、重新检查、移除和清空操作保留。Control-click 同样打开右键菜单。

堆叠菜单在应用未激活时先请求激活，收到 `NSApplication.didBecomeActiveNotification` 后使停放区取得键盘焦点，再在主队列下一轮打开菜单，避免激活过程打断菜单跟踪。等待期间的重复点击合并为一次；收起、隐藏或应用失焦会取消请求。若系统两秒内仍未允许激活，请求作废，避免稍后意外弹出。

这两个入口使用专门的文件服务目录，读取已安装 `.app`、`.service` 和 `.workflow` 的公开 `NSServices` 声明。目录在后台加载并缓存，菜单打开时按需后台刷新。支持文件 URL、文件路径列表、显式文件类型和路径上下文，过滤纯文本服务。右键菜单关闭系统的通用服务自动追加，避免出现重复或无关的文本操作。

菜单名称来自服务提供方，例如 Add to Dropover、Compress using Keka、Compress with Bandizip 和 Upload file in Transmit。点击时通过公开 `NSPerformService` 调用对应服务名称，使用菜单打开时冻结的完整文件集合。它不是“打开方式”或分享菜单，也不直接执行应用里的程序。

Finder 上下文的服务也会纳入文件菜单发现，但调用仍使用 Layby 的真实身份，遵守系统服务权限。此目录依据已安装声明生成，不保证与系统设置过滤后的 Finder 列表完全一致。系统禁用、限制上下文或服务提供方拒绝调用时，会明确显示失败信息。当前不支持将服务返回数据替换原文件。

文件传递同时提供现代 file URL/URL、旧式文件名数组和路径字符串别名，兼容 Dropover、Keka、Transmit、Parallels 等不同的输入声明。应用菜单的 Services 响应链仍可提供这些文件格式；胶囊不提供隐藏文件的 Services 请求。

操作范围内任何文件未就绪、缺少 URL/访问凭据时，都不提供服务，避免仅处理部分文件。实际写入前再次检查文件存在性。服务需要旧式文件名数组时发送全部路径；需要现代 file URL 时发送每个文件的 URL，不操作系统通用复制/粘贴剪贴板。

第三方可能在服务返回后异步打开文件，因此成功发送的文件访问凭据及临时目录持有到本次应用退出。清空或关闭停放区不会提前删除这些已交给服务的临时文件；未调用服务的临时文件仍沿用原清理规则。外部应用的沙盒访问、异步处理和写入行为需要针对具体服务验证；本次测试不调用用户安装的第三方服务。

## 验证

63 项回归测试通过，另一个原生菜单弹出/取消测试在独立进程通过。覆盖堆叠全量传递、列表/网格多选、右键焦点和 Services 响应链、现代 URL/旧式文件名格式、不完整选择拒绝传递、临时文件夹子项在停放区关闭后的存续，以及原生 Services 注册。新增验证真实安装的截图应用服务声明能进入目录，纯文本服务被过滤，菜单操作调用正确服务名称并传递冻结的文件集合。

原生菜单测试覆盖失焦后等待激活、首次打开后持续跟踪直到主动取消、重复请求合并、已激活时打开及收起取消待弹出菜单。独立测试应用使用完整的 `NSApplication.run()` 事件循环，避免命令行 Swift Testing 宿主在原生激活/菜单跟踪期间提前退出。自动调用没有真实鼠标点击授予的激活资格，因此测试在发出菜单请求后显式延迟授予激活；菜单展示和激活通知仍走真实系统路径。测试在结束时归还原前台应用，不执行第三方服务。单独运行：

```sh
bash scripts/test-services-popup.sh
```

使用与 Layby 相同沙盒权限的签名诊断程序验证了目录可读：本机发现 28 个文件服务，其中 Dropover 1 个、Keka 3 个、Bandizip 4 个、Transmit 1 个、Parallels 2 个。

原生窗口和私有剪贴板测试需要可访问桌面的执行环境。

## Apple 文档

- [Using Services](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/using.html)
- [Context menu plug-ins](https://developer.apple.com/documentation/appkit/nsmenu/allowscontextmenuplugins)
- [Service context restrictions](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html)
