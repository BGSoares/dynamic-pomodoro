import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Resource lookup that intentionally avoids `Bundle.module`.
///
/// The SPM-generated `Bundle.module` is a `static let` whose initializer
/// `Swift.fatalError`s when the resource bundle isn't at one of two
/// compile-baked paths. For an installed `.app` neither path exists, so
/// the very first access — e.g. `Activity.defaultLibrary` during
/// `AppDelegate.init()` — crashes before any `??` fallback can run.
enum BundleResource {
    private final class Anchor {}

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        for bundle in candidates {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

#if canImport(AppKit)
    static func image(forResource name: String) -> NSImage? {
        for bundle in candidates {
            if let image = bundle.image(forResource: name) {
                return image
            }
        }
        return nil
    }
#endif

    private static let spmBundleName = "DynamicPomodoro_DynamicPomodoro.bundle"

#if canImport(AppKit)
    private static let candidates: [Bundle] = {
        let anchor = Bundle(for: Anchor.self)
        let spmBundles = [Bundle.main.bundleURL, anchor.bundleURL].flatMap { base in
            [Bundle(url: base.appendingPathComponent(spmBundleName)),
             Bundle(url: base.deletingLastPathComponent().appendingPathComponent(spmBundleName))]
        }.compactMap { $0 }
        var seen = Set<String>()
        return ([Bundle.main, anchor] + spmBundles).filter { seen.insert($0.bundlePath).inserted }
    }()
#else
    /// Off macOS the process is always SPM-built (there is no installed-.app
    /// layout whose missing paths make `Bundle.module` trap), and the bundle
    /// directory is named `….resources` rather than `….bundle`, which the
    /// manual probing above would miss — so the generated accessor is both
    /// safe and the only correct answer here.
    private static let candidates: [Bundle] = [Bundle.module]
#endif
}
