import Foundation

/// 扫描本机标准位置下的 App。只读，不需要任何隐私权限。
enum AppScanner {

    static let defaultRoots: [String] = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications"
    ]

    static func scan(roots: [String] = defaultRoots) -> [AppInfo] {
        let fm = FileManager.default
        var seenPaths = Set<String>()
        var seenBundleIDs = Set<String>()
        var result: [AppInfo] = []

        for root in roots {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }
                // .app 是包，找到后不再深入，避免把 App 内嵌的 helper 也当成独立 App。
                enumerator.skipDescendants()

                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
                let path = url.standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { continue }
                // 同一个 App 在多个目录各有一份时，保留先扫描到的那份。
                guard seenBundleIDs.insert(bundleID).inserted else { continue }

                let name = fm.displayName(atPath: path)
                result.append(AppInfo(path: path, name: name, bundleID: bundleID))
            }
        }

        return result.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
