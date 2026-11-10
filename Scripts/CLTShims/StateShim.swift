// Compiled ONLY by Scripts/build-with-command-line-tools.sh, never by the Xcode project.
//
// Recent macOS SDKs declare `@State` as a macro implemented in SwiftUIMacros, a compiler plugin
// that ships with Xcode but not with the Command Line Tools. The `State` property wrapper
// struct still exists and behaves identically, so the build script rewrites `@State` to
// `@CLTState` in a temporary copy of the sources, and this wrapper forwards to SwiftUI.State.
import SwiftUI

@propertyWrapper
struct CLTState<Value>: DynamicProperty {
    private var storage: SwiftUI.State<Value>

    init(wrappedValue: Value) { storage = SwiftUI.State(wrappedValue: wrappedValue) }
    init(initialValue: Value) { storage = SwiftUI.State(initialValue: initialValue) }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }

    mutating func update() { storage.update() }
}

extension CLTState where Value: ExpressibleByNilLiteral {
    init() { self.init(wrappedValue: nil) }
}
