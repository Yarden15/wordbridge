import Foundation

/// Finds the model file and the `llama-server` binary.
///
/// Layout searched (first match wins):
///   - the model chosen in the menu (UserDefaults "modelPath")
///   - ~/Library/Application Support/Wordbridge/models/<model>.gguf
///   - /Volumes/<any drive>/Wordbridge/models/<model>.gguf
/// `llama-server` is looked for in "<Wordbridge folder>/llama.cpp[/<build>]/llama-server",
/// then in Homebrew's bin folders.
enum ModelLocator {
    /// Preferred models, best first (see tools/model-bench/results.md).
    static let preferredModels = [
        "gemma-4-E4B-it-Q4_K_M.gguf",
        "gemma-4-E2B-it-Q4_K_M.gguf",
    ]

    static let modelPathKey = "modelPath"
    static let serverPathKey = "serverPath"

    static var appSupportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Wordbridge", directoryHint: .isDirectory)
    }

    static var modelURL: URL? {
        let fm = FileManager.default
        if let path = UserDefaults.standard.string(forKey: modelPathKey), fm.fileExists(atPath: path) {
            return URL(filePath: path)
        }
        for dir in modelSearchFolders {
            for name in preferredModels {
                let url = dir.appending(path: name)
                if fm.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    static var modelSearchFolders: [URL] {
        var folders = [appSupportFolder.appending(path: "models", directoryHint: .isDirectory)]
        let volumes = (try? FileManager.default.contentsOfDirectory(
            at: URL(filePath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []
        for volume in volumes {
            folders.append(volume.appending(path: "Wordbridge/models", directoryHint: .isDirectory))
        }
        return folders
    }

    static func serverURL(forModel model: URL) -> URL? {
        let fm = FileManager.default
        if let path = UserDefaults.standard.string(forKey: serverPathKey), fm.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }

        // <Wordbridge folder>/models/<model>.gguf  →  <Wordbridge folder>/llama.cpp
        let llamaFolder = model.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "llama.cpp", directoryHint: .isDirectory)
        var candidates = [llamaFolder.appending(path: "llama-server")]
        let builds = ((try? fm.contentsOfDirectory(at: llamaFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // newest build first
        candidates += builds.map { $0.appending(path: "llama-server") }
        candidates += ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"].map { URL(filePath: $0) }

        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    /// "gemma-4-E4B-it-Q4_K_M.gguf" → "gemma-4-E4B"
    static func displayName(for model: URL) -> String {
        var name = model.deletingPathExtension().lastPathComponent
        for suffix in ["-it", "-Q4_K_M", "-Q4_0", "-Q8_0"] {
            if let range = name.range(of: suffix) { name = String(name[..<range.lowerBound]) }
        }
        return name
    }
}
