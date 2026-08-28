#if !canImport(Combine)
import Foundation

/// Linux has no Combine. The pure core uses exactly two of its names —
/// `ObservableObject` (a conformance on `Settings`) and `@Published` (whose
/// enclosing `didSet` persists each value to UserDefaults) — so shim those
/// two names rather than drag in a replacement dependency. Nothing here
/// publishes: on Linux there are no views and nothing observes; the shims
/// exist so `Settings` compiles unmodified. Compiles to nothing on macOS.
protocol ObservableObject: AnyObject {}

@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif
