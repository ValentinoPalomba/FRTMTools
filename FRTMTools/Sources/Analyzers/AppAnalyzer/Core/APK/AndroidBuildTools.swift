import Foundation

enum AndroidBuildTools {
    static func locateExecutable(named executable: String) -> URL? {
        let fm = FileManager.default
        var searchRoots: [URL] = []
        let home = fm.homeDirectoryForCurrentUser
        searchRoots.append(home.appendingPathComponent("Library/Android/sdk/build-tools", isDirectory: true))
        searchRoots.append(URL(fileURLWithPath: "/Library/Android/sdk/build-tools", isDirectory: true))
        searchRoots.append(URL(fileURLWithPath: "/usr/local/share/android-sdk/build-tools", isDirectory: true))
        searchRoots.append(URL(fileURLWithPath: "/usr/local/opt/android-sdk/build-tools", isDirectory: true))

        let env = ProcessInfo.processInfo.environment
        if let androidHome = env["ANDROID_HOME"] {
            searchRoots.append(URL(fileURLWithPath: androidHome).appendingPathComponent("build-tools", isDirectory: true))
        }
        if let androidSDKRoot = env["ANDROID_SDK_ROOT"] {
            searchRoots.append(URL(fileURLWithPath: androidSDKRoot).appendingPathComponent("build-tools", isDirectory: true))
        }

        for root in searchRoots {
            guard fm.fileExists(atPath: root.path) else { continue }
            let versionDirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            let sorted = versionDirs.sorted {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
            }
            for dir in sorted {
                let candidate = dir.appendingPathComponent(executable)
                if fm.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}
