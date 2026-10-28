# Dashboard Reborn 实现计划

> 目标：在 macOS 26（Liquid Glass / 液态玻璃设计）上做一个替代旧版 Dashboard 的原生 App。
> 核心诉求：**点击时读取软件列表**；**长按进行分组、删除等管理操作**；整体交互尽量接近旧版 Dashboard。
>
> 结论先说：**可以做到。** 所需能力全部有公开 API，不需要私有接口、不需要注入系统进程、不需要关闭 SIP。
>
> **实施状态（2026-10-27）：已完成可运行原型。**
> 产物：`dist/Dashboard.app`；构建：`./build.sh`；启动：`open dist/Dashboard.app`。
> 自动验证：构建通过、扫描到 132 个 App、F12 注册成功、布局 / 分页 / 排序 / 背景 / 设置自测 28 项全过、LaunchServices 启动并写入 `layout.json`、运行时截图见 `docs/screenshot.png`。
> v1.1：顶部搜索（名称 / bundle id，名称命中优先），见 `docs/search.png`。
> v1.2：`Tab` / `Shift+Tab` 循环选择（末尾回绕）、蓝色高亮、`Enter` 打开，见 `docs/selection.png`。
> v1.3：分页（默认 35 个/页）、设置面板（每页 20/28/35 个、图标小/中/大）、`←` / `→` 翻页。
> v1.4：参考旧版 Launchpad 精简界面——去掉标题栏，只保留顶部居中大搜索框（620×46）、彩色渐变背景、底部圆点；见 `docs/screenshot.png`。
> v1.5：背景设置——极光 / 午夜星空 / 深海 / 紫罗兰 / 石墨 / 玫瑰，自选本地图片；搜索框避开刘海/菜单栏。
> v1.6：图标大小改为小 / 中 / 大 / 超大四档大按钮（64 / 70 / 90 / 100pt）。
> v1.7：每页容量改为按图标尺寸 / 页面高度自动计算；触控板横向交回系统 paged scroll，滚轮一次一页弹簧动画。

---

## 1. 可行性结论

| 需求 | 是否可行 | 实现方式 |
|---|---|---|
| 点击 Dashboard 时读取本机软件列表 | ✅ | `FileManager` 枚举 `/Applications`、`/System/Applications`、`~/Applications`，用 `Bundle` 读取 `CFBundleIdentifier` / 名称 |
| 显示 App 图标 | ✅ | `NSWorkspace.shared.icon(forFile:)`，内存缓存 |
| 点击图标启动 App | ✅ | `NSWorkspace.shared.openApplication(at:configuration:)` |
| 长按进入编辑模式 | ✅ | SwiftUI `onLongPressGesture(minimumDuration:)` + 抖动动画 |
| 拖拽一个 App 到另一个 App 上分组 | ✅ | 自研 `DragGesture` + 控件帧命中（不使用系统 `dropDestination`，避免离屏渲染出现禁用角标） |
| 拖动排序 | ✅ | 拖到图标边缘/空隙插入，显示插入线；页内排序 |
| 删除（从面板移除） | ✅ | 修改本地布局 JSON；不会卸载 App，符合旧版 Dashboard 语义 |
| 真正卸载 App（可选） | ✅ | `NSWorkspace.shared.recycle(_:)` 移到废纸篓，系统会弹授权 |
| 分组重命名 / 解散 / 移出成员 | ✅ | 本地数据模型 + 右键菜单 / 文件夹弹层；长按 1 秒进入编辑抖动、拖出弹层、只剩 1 个自动解散 |
| 搜索 App | ✅ | 顶部搜索框（铺满剩余宽度），按名称 / bundle id 过滤，名称命中优先 |
| 分页 | ✅ | 底部圆点、←/→；滚轮/双指一次动作只翻一页 |
| 设置 | ✅ | 齿轮面板：图标小/中/大/超大四档按钮，每页容量按尺寸自动计算；`UserDefaults` 持久化 |
| 背景 | ✅ | 极光 / 午夜星空 / 4 种纯色 / 自选图片；图片复制到 Application Support，设置持久化 |
| Tab 循环选择 | ✅ | 本地 keyDown 监听 + `selectedTileID`，末尾回绕，Shift+Tab 反向，跨页自动翻页 |
| 布局持久化 | ✅ | `~/Library/Application Support/DashboardReborn/layout.json` |
| 全屏 Dashboard 层 | ✅ | 无边框 `NSPanel` + `.statusBar` 层级 + `.canJoinAllSpaces` |
| 全局快捷键呼出 | ✅ | Carbon `RegisterEventHotKey`（F12），无需辅助功能权限 |
| Liquid Glass 外观 | ✅ | macOS 26 `glassEffect(_:in:)`；低版本回退 `ultraThinMaterial` |
| 菜单栏入口（无 Dock 图标） | ✅ | `NSStatusItem` + `LSUIElement = true` |

### 明确做不到 / 只能近似的部分

1. **无法凭空恢复系统自带的 Dashboard Space。** 旧版 Dashboard 是系统级独立 Space，能被 Mission Control、四指横扫识别。第三方 App 不能创建系统 Space，只能用“置顶无边框面板 + 全屏辅助”模拟。
2. **无法可靠拦截四指横扫。** 触控板全局手势没有公开 API；需要辅助功能权限的 `NSEvent` 全局监听也不稳定。方案用 F12 / 菜单栏图标代替。
3. **不能静默卸载 App。** 删除 `/Applications` 下的 App 必须经过用户授权；面板上的“×”只代表从 Dashboard 移除。
4. **沙盒版（Mac App Store）能力受限。** App Sandbox 下无法自由枚举 `/Applications`，建议 Developer ID 直接分发（不开启 App Sandbox）。
5. **旧版 `.wdgt` 小组件不能直接复用。** 如果后续要“小组件”而不仅是 App 图标，需要用 WidgetKit 重写，或嵌入 Web 内容。当前需求不涉及。
6. **多显示器 / 全屏 App 上的表现**是近似实现；面板默认出现在鼠标所在屏幕，覆盖全屏 App 需要额外适配。
7. **跨页拖拽分组未实现。** 分组需要先把两个 App 翻到同一页；后续可加拖动到边缘自动翻页。

---

## 2. 技术选型

- **语言**：Swift 5.9+（Xcode 26 自带 Swift 6.3）
- **UI**：SwiftUI 为主 + AppKit 窗口/菜单栏/NSWorkspace 桥接
  - 说明：**UIKit 是 iOS 专用**，macOS 不能直接用 UIKit 做桌面 App；对应框架是 AppKit，SwiftUI 则跨平台。
- **工程管理**：Swift Package Manager（SwiftPM）
  - 说明：本项目零第三方依赖，**不需要 CocoaPods**；SwiftPM 是 Xcode 原生方案，构建更轻。
- **为什么不用 UIKit**：UIKit 是 iOS / tvOS 框架，macOS 桌面 App 对应的是 AppKit；SwiftUI 在 macOS 上由 AppKit 承载。强行在 macOS 用 UIKit 需要 Catalyst，反而增加包体和适配成本。
- **最低系统**：macOS 14；Liquid Glass 分支用 `#available(macOS 26.0, *)` 保护
- **持久化**：Codable + JSON（数据量很小，无需 Core Data / SwiftData）
- **分发**：本地 ad-hoc 签名；正式分发用 Developer ID + 公证（Notarization）

---

## 3. 架构

```
Dashboard.app
├── AppMain.swift            程序入口；--scan-json / --render 调试模式
├── AppDelegate.swift        NSApplicationDelegate、菜单栏图标、F12 注册
├── DashboardController.swift 无边框全屏 NSPanel、显示/隐藏、Esc 处理
├── GlobalHotKey.swift       Carbon 全局热键
├── DashboardModel.swift     状态、扫描合并、分组/删除/重命名、持久化
├── AppScanner.swift         枚举 /Applications 等目录
├── SettingsOverlay.swift    图标大小 / 背景设置面板
├── LayoutStore.swift        layout.json 读写
├── Models.swift             AppInfo / Folder / Tile / DashboardLayout
├── IconProvider.swift       图标缓存
├── DashboardView.swift      居中搜索 + 分页网格 + 圆点 + Toast
├── TileView.swift           App 图标格、文件夹格、抖动、拖拽
├── FolderOverlay.swift      文件夹弹层
├── DashboardBackground.swift 极光/午夜/纯色/图片背景
└── GlassStyle.swift         Liquid Glass 容器 / 圆形按钮
```

### 数据模型

```swift
AppInfo   { path, name, bundleID }
Folder    { id: UUID, name, appPaths: [String] }
Tile      = .app(path) | .folder(Folder)
Layout    { tiles: [Tile], hidden: Set<String> }
```

- 以 **App 路径**作为稳定标识；`hidden` 保存“已从面板移除”的路径，重新扫描不会复活。
- 合并策略：保留用户排序/分组 → 删除磁盘上已不存在的 App → 把新发现的 App 追加到末尾。
- 每次 `show()` / 点击刷新都会重新扫描，满足“点击时读取软件列表”。

---

## 4. 交互设计（对齐旧版）

| 操作 | 行为 |
|---|---|
| 点击 App 图标 | 启动 App，并收起 Dashboard |
| 长按图标 1s | 进入编辑模式，图标开始轻微抖动 |
| 编辑模式下拖拽 A 到 B 的中心 | 合成文件夹（默认名“新建文件夹”），可重命名 |
| 拖拽 App 到文件夹 | 加入该文件夹 |
| 拖拽到图标边缘 / 空隙 | 插入排序，显示白色插入线 |
| `Tab` / `Shift+Tab` | 循环选中下一个 / 上一个，末尾回到开头，跨页自动翻页 |
| `Enter` | 打开选中 App 或进入选中文件夹 |
| `←` / `→` | 上一页 / 下一页 |
| 鼠标滚轮 / 两指滑动 | 一次动作翻一页，再次滚动才继续 |
| 点击空白背景 | 收起 Dashboard；编辑模式下先退出编辑 |
| 点击设置遮罩 | 关闭设置 |
| 点击底部圆点 | 跳到指定页 |
| 顶部搜索框 | 居中大搜索框；实时过滤；回车打开第一个，Esc 清除 |
| 右上角齿轮 | 设置图标大小与背景 |
| 点文件夹 | 打开文件夹弹层；点名称可直接改名 |
| 编辑模式点 ×（App） | 从面板移除，不卸载；Toast 明确提示 |
| 编辑模式点 ×（文件夹） | 解散文件夹，成员回到网格 |
| 文件夹内长按图标 1 秒 | 进入编辑模式，图标抖动并显示 × |
| 文件夹内点 × / 拖到弹层外 | 移出文件夹，回到网格；只剩 1 个时自动解散 |
| 右键 App | 打开 / 在访达中显示 / 从面板移除 / 移到废纸篓（系统 App 禁止） |
| Esc | 依次关闭文件夹 → 退出编辑 → 收起面板 |
| F12 | 全局显示/隐藏 Dashboard |
| 菜单栏图标 | 打开、重新扫描、重置布局、退出 |

视觉：
- 默认极光渐变；可切换午夜星空、纯色或自选图片
- 图标大小小/中/大/超大四档；小图标 9 列，其余 7 列；不足一页内容靠上排列
- 每页容量按图标尺寸与可用高度自动计算；横向分页 + 底部圆点；滚动条强制隐藏
- 顶部只保留居中大搜索框（620×46），无标题栏，并避开刘海 / 菜单栏；列表顶部额外留半个图标高度
- 背景可切换极光渐变、午夜星空、纯色或自选图片
- 搜索框 / 文件夹 / 设置 / Toast 使用玻璃或半透明材质；macOS < 26 回退毛玻璃
- 编辑态显示“编辑模式”徽标与底部操作提示

---

## 5. 实施步骤

1. **工程骨架**：SwiftPM executable + Info.plist + 打包脚本
2. **数据层**：AppScanner / Models / LayoutStore
3. **状态层**：DashboardModel（扫描合并、分组、删除、持久化）
4. **UI 层**：背景、图标网格、文件夹弹层、玻璃样式
5. **窗口层**：NSPanel、F12、菜单栏、Esc
6. **编译打包**：`swift build -c release` → `dist/Dashboard.app` → ad-hoc 签名
7. **验证**：
   - `--scan-json` 输出 App 数量与字段
   - `--render` 渲染 UI 预览图并肉眼检查
   - 启动 App，确认进程存活、布局 JSON 写入
   - 手工验收：点击、长按、拖拽、删除、重命名、重启恢复
8. **文档**：本计划 + README（构建/运行/权限说明）

---

## 6. 验收标准与结果

- [x] 启动后展示本机 App 图标（本机去重后 132 个，原始枚举 139 份）
- [x] 点击图标走 `NSWorkspace.openApplication`（已接线；启动外部 App 未做自动化点击）
- [x] 长按 1s 进入编辑模式，图标抖动（已实现）
- [x] 编辑模式下拖拽 A 到 B 生成文件夹（手势 + 命中逻辑已实现，数据层自测通过）
- [x] 拖动到边缘/空隙可插入排序，不足一页时内容靠上（数据层自测 + 运行时）
- [x] 文件夹可打开、改名、长按 1 秒进入编辑抖动、移出成员、解散；拖出弹层可用；只剩 1 个成员自动解散（数据层自测通过）
- [x] `Tab` 依次选择，最后一个之后回到第一个；`Shift+Tab` 反向（合成按键测试通过）
- [x] 选中项有明显蓝色高亮，Enter 可打开（运行时截图验证）
- [x] 顶部搜索能实时过滤，回车打开第一个结果（运行时截图验证）
- [x] 每页容量按图标尺寸自动计算，`←` / `→`、圆点、触控板可左右翻页（分页截图 + 按键测试）
- [x] 鼠标滚轮 / 触控板一次滚动只翻一页，不会连续翻多页（合成滚轮测试通过）
- [x] 点击空白背景可以收起 Dashboard，点击设置遮罩可以关闭设置（合成点击测试通过）
- [x] 设置面板可改图标小/中/大/超大，重启后保持；每页容量自动重算（设置持久化自测通过）
- [x] 背景可切换内置样式或自选图片并持久化（背景自测通过；选图面板需实机点一次）
- [x] 点 × 后从面板消失，重启后仍不出现（`hidden` 持久化自测通过）
- [x] “恢复被移除的 App”能把隐藏项加回（自测通过）
- [x] 布局在重启后保持（写入/读取 `layout.json` 自测通过）
- [x] F12 / 菜单栏开关（启动日志 `f12=true`；Esc 由本地事件监听处理）
- [x] macOS 26 Liquid Glass 已接入 `glassEffect`（缓存截图无法呈现模糊，需实机查看）

> 说明：构建、扫描、数据层分组/删除/持久化已自动验证；鼠标长按与拖拽的“手感”需要在真实窗口里人工点一次确认。

---

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| F12 被系统媒体键占用（需 Fn） | 菜单栏入口兜底；后续可加自定义快捷键 |
| 无边框面板抢不到键盘焦点 | `canBecomeKey = true` + `makeKey()` + 本地 Esc 监听 |
| 扫描 `/Applications` 较慢 | 同步扫描约百毫秒级；后续可改后台扫描 + 渐进渲染 |
| 沙盒限制目录读取 | 不做 App Sandbox；Developer ID 分发 |
| 误删 App | 面板删除只移除记录；真正卸载需二次确认并走系统废纸篓 |
| macOS 未来版本 API 变化 | 只依赖长期稳定的 AppKit / LaunchServices API；Liquid Glass 分支做版本保护 |

---

## 8. 实施与验证结果（2026-10-27）

- 环境：macOS 26.5.2 (25F84)，Xcode 26.6，Swift 6.3.3，macOS SDK 26.5
- `glassEffect` 在 SwiftUICore 中可用（macOS 26.0+）
- 扫描：标准目录原始枚举 139 份，按 bundle id 去重后 **132 个 App**
- 构建：`swift build -c release` 通过；`dist/Dashboard.app` ad-hoc 签名，`codesign --verify --deep --strict` 通过
- 逻辑自测：`--self-test` **28 项全部 PASS**（扫描、Tab / 跨页、排序、自动容量、建组、重命名、移出、隐藏、恢复、解散、搜索保留、落盘、设置 / 背景持久化）
- 键盘测试：`--key-test` 合成真实 Tab / Shift+Tab / ← / → 事件，5 项 PASS
- 滚动测试：`--scroll-test` 合成鼠标滚轮，3 项 PASS（翻一页、冷却内不连翻、再次滚动再翻一页）
- 点击测试：`--dismiss-test` 合成点击，2 项 PASS（空白背景收起、设置遮罩关闭）
- 图片选择：`--picker-test` 确认 `NSOpenPanel` 以 sheet 显示且成为 key window，可见性 PASS
- 启动链路：`--smoke-test` 输出 `panel-created apps=132 tiles=132 f12=true`
- 运行时截图：`--snapshot` 真实面板 3024×1964，见 `docs/screenshot.png`
- 搜索：运行时输入 “Google” 得到 11 个匹配，名称命中排在 bundle id 命中之前，见 `docs/search.png`
- 选中：`--snapshot` 设置第 5 个图标为选中，蓝色描边/光晕正常，见 `docs/selection.png`
- 分页：中图标自动 35 个/页、共 4 页；小图标自动 45 个/页；底部只显示圆点，`docs/screenshot.png`
- 设置：图标小/中/大/超大四档按钮、自动每页容量、背景预设与选图入口，深色玻璃面板，见 `docs/settings.png`
- 背景：极光默认、午夜星空还原、纯色/自选图片；自选图片复制到 `Application Support/DashboardReborn/Backgrounds/`
- LaunchServices：`open dist/Dashboard.app` 成功启动，并写入
  `~/Library/Application Support/DashboardReborn/layout.json`（7647 bytes）
- 屏幕录制权限不可用，因此真实窗口截图通过 `NSView.cacheDisplay` 获取；Liquid Glass 的模糊层不会被缓存图完整呈现

### 复现命令

```bash
cd DashboardReborn
./build.sh
open dist/Dashboard.app

# 自动验证（28 项）
DASHBOARD_LAYOUT_PATH=$PWD/.build/selftest.json \
DASHBOARD_SETTINGS_SUITE=dash.self \
DASHBOARD_BACKGROUND_DIR=$PWD/.build/backgrounds \
dist/Dashboard.app/Contents/MacOS/Dashboard --self-test

# 合成点击：空白背景 / 设置遮罩 dismiss（2 项）
DASHBOARD_LAYOUT_PATH=$PWD/.build/dismisstest.json \
DASHBOARD_SETTINGS_SUITE=dash.dismiss \
dist/Dashboard.app/Contents/MacOS/Dashboard --dismiss-test

# 合成滚轮：一次滚动只翻一页（3 项）
DASHBOARD_LAYOUT_PATH=$PWD/.build/scrolltest.json \
DASHBOARD_SETTINGS_SUITE=dash.scroll \
dist/Dashboard.app/Contents/MacOS/Dashboard --scroll-test

# 合成按键（5 项）
DASHBOARD_LAYOUT_PATH=$PWD/.build/keytest.json \
DASHBOARD_SETTINGS_SUITE=dash.key \
dist/Dashboard.app/Contents/MacOS/Dashboard --key-test

dist/Dashboard.app/Contents/MacOS/Dashboard --scan-json | python3 -c "import json,sys;print(len(json.load(sys.stdin)))"
```
