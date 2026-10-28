import AppKit
import SwiftUI

@main
enum DashboardMain {

    @MainActor
    static func main() {
        let arguments = CommandLine.arguments

        // 调试：只扫描并输出 App 列表，不启动 UI。
        if arguments.contains("--scan-json") {
            let apps = AppScanner.scan()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(apps),
               let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            exit(0)
        }

        // 调试：核心数据逻辑自测（不会动真实布局，需设置 DASHBOARD_LAYOUT_PATH）。
        if arguments.contains("--self-test") {
            exit(runSelfTest())
        }

        // 调试：只创建 NSPanel + SwiftUI 视图，不显示，验证启动链路。
        if arguments.contains("--smoke-test") {
            exit(runSmokeTest())
        }

        // 调试：合成 Tab 按键，验证本地事件监听和循环选择。
        if arguments.contains("--key-test") {
            exit(runKeyTest())
        }

        // 调试：合成鼠标滚轮，验证一次滚动只翻一页。
        if arguments.contains("--scroll-test") {
            exit(runScrollTest())
        }

        // 调试：点击空白背景 / 设置遮罩是否能 dismiss。
        if arguments.contains("--dismiss-test") {
            exit(runDismissTest())
        }

        // 调试：真正显示面板，1.5 秒后把窗口内容存成 PNG 并退出。
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            runSnapshot(to: arguments[index + 1])
            exit(0)
        }

        // 调试：把主界面离屏渲染成 PNG，方便无录屏权限时检查 UI。
        if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
            renderPreview(to: arguments[index + 1])
            exit(0)
        }

        // 调试：只渲染一个图标格子 / 一个原始图标，用于定位绘制问题。
        if let index = arguments.firstIndex(of: "--render-tile"), index + 2 < arguments.count {
            renderTile(appPath: arguments[index + 1], to: arguments[index + 2])
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--render-icon"), index + 2 < arguments.count {
            renderIcon(appPath: arguments[index + 1], to: arguments[index + 2])
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--render-row"), index + 1 < arguments.count {
            renderRow(to: arguments[index + 1])
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--render-icons"), index + 1 < arguments.count {
            renderIcons(to: arguments[index + 1])
            exit(0)
        }

        _ = NSApplication.shared
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    @MainActor
    private static func runSmokeTest() -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let controller = DashboardController()
        controller.model.refresh()
        let hotKey = GlobalHotKey {}
        print("smoke-test: panel-created apps=\(controller.model.visibleAppCount) tiles=\(controller.model.layout.tiles.count) f12=\(hotKey.isRegistered)")
        return controller.model.visibleAppCount > 0 ? 0 : 1
    }

    @MainActor
    private static func runKeyTest() -> Int32 {
        var failures = 0
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let controller = DashboardController()
        controller.show()
        let tiles = controller.model.visibleTiles
        guard tiles.count >= 2 else {
            print("KEY-TEST FAILED: 没有足够的 App")
            return 1
        }

        func postKey(_ keyCode: UInt16) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controller.panelWindowNumber,
                context: nil as NSGraphicsContext?,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            ) else { return }
            NSApp.postEvent(event, atStart: false)
        }

        func postTab(shift: Bool = false) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: shift ? [.shift] : [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controller.panelWindowNumber,
                context: nil as NSGraphicsContext?,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                isARepeat: false,
                keyCode: 48
            ) else { return }
            NSApp.postEvent(event, atStart: false)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            postTab()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let firstOK = controller.model.selectedTileID == tiles[0].id
                print((firstOK ? "PASS  " : "FAIL  ") + "Tab 键选中第一个")
                if !firstOK { failures += 1 }

                controller.model.selectedTileID = tiles.last?.id
                postTab()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let wrapOK = controller.model.selectedTileID == tiles[0].id
                    print((wrapOK ? "PASS  " : "FAIL  ") + "Tab 键从最后一个回绕到第一个")
                    if !wrapOK { failures += 1 }

                    controller.model.selectedTileID = tiles[0].id
                    postTab(shift: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        let prevOK = controller.model.selectedTileID == tiles.last?.id
                        print((prevOK ? "PASS  " : "FAIL  ") + "Shift+Tab 从第一个回绕到最后一个")
                        if !prevOK { failures += 1 }

                        controller.model.goToPage(0)
                        postKey(124) // →
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            let rightOK = controller.model.currentPage == 1
                            print((rightOK ? "PASS  " : "FAIL  ") + "→ 键翻到下一页")
                            if !rightOK { failures += 1 }

                            postKey(123) // ←
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                let leftOK = controller.model.currentPage == 0
                                print((leftOK ? "PASS  " : "FAIL  ") + "← 键翻到上一页")
                                if !leftOK { failures += 1 }

                                print(failures == 0 ? "KEY-TEST OK" : "KEY-TEST FAILED")
                                exit(failures == 0 ? 0 : 1)
                            }
                        }
                    }
                }
            }
        }

        NSApp.run()
        return 0
    }

    @MainActor
    private static func runScrollTest() -> Int32 {
        var failures = 0
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let controller = DashboardController()
        controller.show()

        func postWheel(_ deltaY: CGFloat) {
            guard let cgEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: Int32(deltaY),
                wheel2: 0,
                wheel3: 0
            ), let event = NSEvent(cgEvent: cgEvent) else { return }
            NSApp.postEvent(event, atStart: false)
        }

        func check(_ condition: Bool, _ label: String) {
            print((condition ? "PASS  " : "FAIL  ") + label)
            if !condition { failures += 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            controller.model.goToPage(0)
            postWheel(-1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                check(controller.model.currentPage == 1, "滚轮向下只翻到下一页")

                // 冷却期内再次滚动不应连续翻页。
                postWheel(-1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    check(controller.model.currentPage == 1, "连续滚动不会连翻多页")

                    // 冷却结束后再滚一次，才翻到下一页。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
                        postWheel(-1)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                            check(controller.model.currentPage == 2, "再次滚动再翻一页")
                            print(failures == 0 ? "SCROLL-TEST OK" : "SCROLL-TEST FAILED")
                            exit(failures == 0 ? 0 : 1)
                        }
                    }
                }
            }
        }

        NSApp.run()
        return 0
    }

    @MainActor
    private static func runDismissTest() -> Int32 {
        var failures = 0
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let controller = DashboardController()
        controller.show()

        func click(x: CGFloat, y: CGFloat) {
            let point = NSPoint(x: x, y: y)
            guard let down = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controller.panelWindowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ), let up = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + 0.05,
                windowNumber: controller.panelWindowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 0
            ) else { return }
            NSApp.postEvent(down, atStart: false)
            NSApp.postEvent(up, atStart: false)
        }

        func check(_ condition: Bool, _ label: String) {
            print((condition ? "PASS  " : "FAIL  ") + label)
            if !condition { failures += 1 }
        }

        let height = NSScreen.main?.frame.height ?? 900

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            click(x: 40, y: height - 320)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                check(!controller.isVisible, "点击空白背景收起 Dashboard")

                controller.show()
                controller.model.isShowingSettings = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    click(x: 40, y: 40)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        check(!controller.model.isShowingSettings, "点击设置遮罩关闭设置")
                        print(failures == 0 ? "DISMISS-TEST OK" : "DISMISS-TEST FAILED")
                        exit(failures == 0 ? 0 : 1)
                    }
                }
            }
        }

        NSApp.run()
        return 0
    }

    @MainActor
    private static func runSnapshot(to path: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let controller = DashboardController()
        controller.show()
        if let query = ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_SEARCH"], !query.isEmpty {
            controller.model.searchText = query
        }
        if let raw = ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_SELECT"], !raw.isEmpty {
            // 等 SwiftUI 完成首次布局后再设选中，模拟真实 Tab 操作。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                let tiles = controller.model.visibleTiles
                if raw == "last" {
                    controller.model.selectedTileID = tiles.last?.id
                } else if let index = Int(raw), tiles.indices.contains(index) {
                    controller.model.selectedTileID = tiles[index].id
                } else {
                    controller.model.selectedTileID = tiles.first?.id
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let raw = ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_ICON"] {
                let side: Double?
                switch raw {
                case "small": side = 64
                case "medium": side = 70
                case "large": side = 90
                default: side = Double(raw)
                }
                if let side {
                    controller.model.iconSide = side
                }
            }
            if let raw = ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_PAGE"],
               let page = Int(raw) {
                controller.model.goToPage(page)
            }
            if let raw = ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_BACKGROUND"],
               let style = BackgroundStyle(rawValue: raw) {
                controller.model.selectBackground(style)
            }
            if let imagePath = ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_BACKGROUND_IMAGE"],
               !imagePath.isEmpty {
                controller.model.setCustomBackground(from: URL(fileURLWithPath: imagePath))
            }
            if ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_DEMO_FOLDER"] == "1" {
                let paths = controller.model.visibleTiles.compactMap { tile -> String? in
                    if case .app(let path) = tile { return path }
                    return nil
                }
                if paths.count >= 2 {
                    controller.model.drop(path: paths[1], onto: "app:\(paths[0])")
                    if let folder = controller.model.layout.tiles.compactMap(\.folder).first(where: {
                        $0.appPaths.contains(paths[0])
                    }) {
                        controller.model.renameFolder(id: folder.id, name: "我的分组")
                    }
                }
                controller.model.goToPage(0)
            }
            if ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_EDIT"] == "1" {
                controller.model.isEditing = true
            }
            if ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_SETTINGS"] == "1" {
                controller.model.isShowingSettings = true
            }
        }

        let delay = Double(ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_DELAY"] ?? "") ?? 2.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            controller.capturePanel(to: path)
            exit(0)
        }
        NSApp.run()
    }

    @MainActor
    private static func runSelfTest() -> Int32 {
        var failures: [String] = []

        func check(_ condition: Bool, _ label: String) {
            print((condition ? "PASS  " : "FAIL  ") + label)
            if !condition { failures.append(label) }
        }

        let model = DashboardModel()
        model.refresh()
        check(model.layout.tiles.count > 5, "扫描并生成布局（\(model.layout.tiles.count) 个格子）")
        check(!model.layout.tiles.isEmpty, "布局非空")

        let tileIDs = model.visibleTiles.map(\.id)
        if tileIDs.count >= 2 {
            model.clearSelection()
            model.selectNext(forward: true)
            check(model.selectedTileID == tileIDs[0], "Tab 首次选择第一个")
            model.selectNext(forward: false)
            check(model.selectedTileID == tileIDs[tileIDs.count - 1], "Shift+Tab 从第一个回绕到最后一个")
            model.selectNext(forward: true)
            check(model.selectedTileID == tileIDs[0], "Tab 从最后一个回绕到第一个")

            model.currentPage = 0
            let capacity = model.pageCapacity
            model.selectedTileID = tileIDs[capacity - 1]
            model.selectNext(forward: true)
            check(model.selectedTileID == tileIDs[capacity], "Tab 跨页选中下一页第一个")
            check(model.currentPage == 1, "Tab 跨页时自动翻页")
            check(
                model.pageCount == (tileIDs.count + capacity - 1) / capacity,
                "页数计算正确"
            )
            model.goToPage(999)
            check(model.currentPage == model.pageCount - 1, "页码越界自动收敛")
            model.goToPage(0)
            model.clearSelection()
        }

        let initialPaths = model.layout.tiles.compactMap { tile -> String? in
            if case .app(let path) = tile { return path }
            return nil
        }
        guard initialPaths.count >= 3 else {
            print("FAIL  可用的 App 数量不足，无法继续自测")
            return 1
        }

        if let reorderPath = initialPaths.first {
            let total = model.layout.tiles.count
            model.moveApp(path: reorderPath, to: total)
            check(model.layout.tiles.last == .app(reorderPath), "拖动排序到页尾")
            model.moveApp(path: reorderPath, to: 0)
            check(model.layout.tiles.first == .app(reorderPath), "拖动排序到页首")
        }

        let first = initialPaths[0]
        let second = initialPaths[1]

        model.drop(path: second, onto: "app:\(first)")
        guard let createdFolder = model.layout.tiles.compactMap(\.folder).first(where: {
            $0.appPaths.contains(first) && $0.appPaths.contains(second)
        }) else {
            print("FAIL  拖拽归组没有生成文件夹")
            return 1
        }
        check(true, "拖拽归组生成文件夹")
        check(model.layout.tiles.filter { $0.folder?.id == createdFolder.id }.count == 1, "文件夹只出现一次")

        model.renameFolder(id: createdFolder.id, name: "自测分组")
        check(model.folder(id: createdFolder.id)?.name == "自测分组", "文件夹重命名")

        model.removeFromFolder(folderID: createdFolder.id, path: second)
        check(model.layout.tiles.contains(.app(second)), "成员移出文件夹回到网格")
        check(model.folder(id: createdFolder.id)?.appPaths == [first], "文件夹保留剩余成员")

        model.removeFromDashboard(first)
        check(model.layout.hidden.contains(first), "从面板移除并记录隐藏")
        check(!model.layout.tiles.contains(.app(first)), "移除后网格不再出现")

        model.restoreHiddenApps()
        check(!model.layout.hidden.contains(first), "恢复被移除的 App")
        check(model.layout.tiles.contains(.app(first)), "恢复后回到网格")

        let pathsAfterRestore = model.layout.tiles.compactMap { tile -> String? in
            if case .app(let path) = tile { return path }
            return nil
        }
        if pathsAfterRestore.count >= 2 {
            model.drop(path: pathsAfterRestore[1], onto: "app:\(pathsAfterRestore[0])")
            if let folder = model.layout.tiles.compactMap(\.folder).first {
                let members = folder.appPaths
                model.dissolveFolder(id: folder.id)
                check(
                    members.allSatisfy { model.layout.tiles.contains(.app($0)) },
                    "解散文件夹后成员回到网格"
                )
            } else {
                check(false, "解散文件夹前未能创建文件夹")
            }
        }

        if let victim = model.layout.tiles.compactMap({ tile -> String? in
            if case .app(let path) = tile { return path }
            return nil
        }).first {
            model.removeFromDashboard(victim)

            // 新建一个 model，模拟 App 重启后重新读取磁盘布局。
            let reloaded = DashboardModel()
            reloaded.refresh()
            check(reloaded.layout.hidden.contains(victim), "重启后隐藏状态保持")
            check(!reloaded.layout.tiles.contains(.app(victim)), "重启后被移除项仍不出现")
            reloaded.restoreHiddenApps()
        }

        if let override = ProcessInfo.processInfo.environment["DASHBOARD_LAYOUT_PATH"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: override)),
           let decoded = try? JSONDecoder().decode(DashboardLayout.self, from: data) {
            check(!decoded.tiles.isEmpty, "布局已写入磁盘（\(data.count) bytes）")
        } else {
            check(false, "读取磁盘布局失败")
        }

        // 设置持久化：写入后新建 model 应能读回。
        model.iconSide = 90
        let reloadedSettings = DashboardModel()
        check(reloadedSettings.iconSide == 90, "图标大小设置持久化")

        let totalTiles = model.layout.tiles.count
        model.updatePageCapacity(20)
        check(model.pageCount == (totalTiles + 19) / 20, "每页容量自动分页")
        model.updatePageCapacity(35)
        reloadedSettings.iconSide = 70

        model.backgroundStyle = .midnight
        let reloadedBackground = DashboardModel()
        check(reloadedBackground.backgroundStyle == .midnight, "背景设置持久化")
        reloadedBackground.backgroundStyle = .aurora

        print(failures.isEmpty ? "SELF-TEST OK" : "SELF-TEST FAILED: \(failures.count)")
        return failures.isEmpty ? 0 : 1
    }

    @MainActor
    private static func renderTile(appPath: String, to path: String) {
        _ = NSApplication.shared
        let app = AppInfo(
            path: appPath,
            name: (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""),
            bundleID: nil
        )
        let view = AppTileView(
            app: app,
            isEditing: false,
            jiggleSeed: 0,
            onOpen: {},
            onEnterEdit: {},
            onRemove: {},
            onTrash: {},
            onReveal: {}
        )
        .padding(40)
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))
        .frame(width: 300, height: 300)

        render(view, to: path)
    }

    @MainActor
    private static func renderIcon(appPath: String, to path: String) {
        _ = NSApplication.shared
        let icon = IconProvider.shared.icon(for: appPath)
        let view = Image(nsImage: icon)
            .resizable()
            .frame(width: 74, height: 74)
            .shadow(color: .black.opacity(0.45), radius: 9, x: 0, y: 6)
            .padding(40)
            .background(Color(red: 0.07, green: 0.09, blue: 0.14))
            .frame(width: 300, height: 300)

        render(view, to: path)
    }

    @MainActor
    private static func renderRow(to path: String) {
        _ = NSApplication.shared
        let apps = Array(AppScanner.scan().prefix(8))
        let view = HStack(spacing: 16) {
            ForEach(apps) { app in
                AppTileView(
                    app: app,
                    isEditing: false,
                    jiggleSeed: 0,
                    onOpen: {},
                    onEnterEdit: {},
                    onRemove: {},
                    onTrash: {},
                    onReveal: {}
                )
            }
        }
        .padding(40)
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))

        render(view, to: path)
    }

    @MainActor
    private static func renderIcons(to path: String) {
        _ = NSApplication.shared
        let apps = Array(AppScanner.scan().prefix(8))
        let view = HStack(spacing: 16) {
            ForEach(apps) { app in
                Image(nsImage: IconProvider.shared.icon(for: app.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 74, height: 74)
                    .shadow(color: .black.opacity(0.45), radius: 9, x: 0, y: 6)
                    .frame(width: 92, height: 92)
            }
        }
        .padding(40)
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))

        render(view, to: path)
    }

    @MainActor
    private static func render<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = CGFloat(Double(ProcessInfo.processInfo.environment["DASHBOARD_RENDER_SCALE"] ?? "") ?? 2)

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            return
        }

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try png.write(to: url)
            print("rendered \(url.path) (\(Int(image.size.width))x\(Int(image.size.height)))")
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        }
    }

    @MainActor
    private static func renderPreview(to path: String) {
        _ = NSApplication.shared

        let model = DashboardModel()
        model.refresh()
        if ProcessInfo.processInfo.environment["DASHBOARD_RENDER_EDIT"] == "1" {
            model.isEditing = true
        }
        if let query = ProcessInfo.processInfo.environment["DASHBOARD_RENDER_SEARCH"], !query.isEmpty {
            model.searchText = query
        }

        let width = CGFloat(Double(ProcessInfo.processInfo.environment["DASHBOARD_RENDER_WIDTH"] ?? "") ?? 1600)
        let height = CGFloat(Double(ProcessInfo.processInfo.environment["DASHBOARD_RENDER_HEIGHT"] ?? "") ?? 1000)
        let content = DashboardView(model: model, preview: true, onClose: {})
            .frame(width: width, height: height)

        render(content, to: path)
    }
}
