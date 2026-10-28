import AppKit
import SwiftUI

final class DashboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class DashboardController {

    let model: DashboardModel
    private let panel: DashboardPanel
    private var hostingView: NSHostingView<DashboardView>!
    private var escapeMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollAccumulator: CGFloat = 0
    private var scrollForward = false
    private var scrollDidPage = false
    private var scrollCooldownUntil = Date.distantPast

    init() {
        model = DashboardModel()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        panel = DashboardPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.acceptsMouseMovedEvents = true

        let root = DashboardView(model: model, onClose: { [weak self] in self?.hide() })
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: screen.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        hostingView = host

        model.onClose = { [weak self] in self?.hide() }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event) ?? event
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }

            if event.keyCode == 53 { // Esc
                self.handleEscape()
                return nil
            }

            // 文件夹 / 设置弹层里仍使用系统的焦点行为。
            guard self.model.openedFolderID == nil, !self.model.isShowingSettings else { return event }

            if !self.isEditingText {
                if event.keyCode == 123 { // ←
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        self.model.previousPage()
                    }
                    return nil
                }
                if event.keyCode == 124 { // →
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        self.model.nextPage()
                    }
                    return nil
                }
            }

            if event.keyCode == 48 { // Tab / Shift+Tab
                if self.isEditingText {
                    self.panel.makeFirstResponder(self.panel.contentView)
                }
                self.model.selectNext(forward: !event.modifierFlags.contains(.shift))
                return nil
            }

            if (event.keyCode == 36 || event.keyCode == 76), // Return / 小键盘 Enter
               !self.isEditingText {
                if self.model.activateSelection() {
                    return nil
                }
            }

            return event
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    var isVisible: Bool { panel.isVisible }

    var panelWindowNumber: Int { panel.windowNumber }

    func show() {
        model.clearSearch()
        model.clearSelection()
        model.currentPage = 0
        model.isShowingSettings = false
        model.refresh()
        if let screen = targetScreen {
            panel.setFrame(screen.frame, display: true)
            hostingView.frame = CGRect(origin: .zero, size: screen.frame.size)
        }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func showSettings() {
        show()
        model.isShowingSettings = true
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func resetLayout() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "重置 Dashboard 布局？"
        alert.informativeText = "现有分组、排序和“已移除”记录都会被清空，所有 App 重新出现。"
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")

        // 面板在 .statusBar 层级，会盖住普通 NSAlert；先收起再弹窗。
        let wasVisible = panel.isVisible
        if wasVisible { hide() }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            model.resetLayout()
        }
        if wasVisible { show() }
    }

    private var targetScreen: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    func capturePanel(to path: String) {
        guard panel.isVisible else {
            print("capture: panel not visible")
            return
        }
        panel.displayIfNeeded()
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            print("capture: no bitmap rep")
            return
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("capture: no png")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("captured \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        } catch {
            print("capture write failed: \(error)")
        }
    }

    /// 一次滚动只翻一页；触控板手势 / 鼠标滚轮都按“一次动作 = 一页”处理。
    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible,
              model.openedFolderID == nil,
              !model.isShowingSettings else {
            return event
        }

        let now = Date()
        let phase = event.phase
        let precise = event.hasPreciseScrollingDeltas
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        // 触控板横向滑动交回系统分页 ScrollView，跟手、带惯性吸附。
        if precise, abs(dx) >= abs(dy) {
            return event
        }

        if phase == .began || phase == .mayBegin {
            scrollAccumulator = 0
            scrollDidPage = false
            scrollForward = false
        }

        if phase == .ended || phase == .cancelled {
            scrollAccumulator = 0
            scrollDidPage = false
            scrollForward = false
            return nil
        }

        // 惯性阶段直接吃掉，不再翻页。
        if event.momentumPhase != [] {
            return nil
        }

        // 无 phase 的鼠标滚轮 / 部分鼠标：每次新动作前重置。
        if phase == [] && now >= scrollCooldownUntil {
            scrollAccumulator = 0
            scrollDidPage = false
            scrollForward = false
        }

        guard now >= scrollCooldownUntil else { return nil }

        let horizontal = abs(dx) >= abs(dy)
        let delta = horizontal ? dx : dy
        guard abs(delta) > 0.001 else { return nil }

        if scrollAccumulator == 0 {
            if horizontal {
                // NSEvent: 向左滑 deltaX 为正；向左滑 = 下一页。
                scrollForward = delta > 0
            } else if precise {
                // 触控板向上滑 = 下一页。
                scrollForward = delta > 0
            } else {
                // 鼠标滚轮向下 = 下一页。
                scrollForward = delta < 0
            }
        }

        scrollAccumulator += abs(delta)
        let threshold: CGFloat = precise ? 5.0 : 0.01
        guard !scrollDidPage, scrollAccumulator >= threshold else { return nil }

        if model.pageCount > 1 {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                if scrollForward {
                    model.nextPage()
                } else {
                    model.previousPage()
                }
            }
        }

        scrollDidPage = true
        scrollCooldownUntil = now.addingTimeInterval(precise ? 0.24 : 0.38)
        return nil
    }

    private var isEditingText: Bool {
        panel.firstResponder is NSTextView || panel.firstResponder is NSTextField
    }

    private func handleEscape() {
        if model.isShowingSettings {
            model.isShowingSettings = false
            return
        }
        if !model.searchText.isEmpty {
            model.clearSearch()
            return
        }
        if model.openedFolderID != nil {
            withAnimation(.snappy(duration: 0.2)) {
                model.openedFolderID = nil
            }
        } else if model.isEditing {
            model.endEditing()
        } else {
            hide()
        }
    }

    @objc private func screenParametersChanged() {
        guard panel.isVisible, let screen = targetScreen else { return }
        panel.setFrame(screen.frame, display: true)
        hostingView.frame = CGRect(origin: .zero, size: screen.frame.size)
    }
}
