<p align="center">
  <a href="https://swiftpackageindex.com/firebase/firebase-ios-sdk">
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffirebase%2Ffirebase-ios-sdk%2Fbadge%3Ftype%3Dplatforms"/>
  </a>
  <a href="https://swiftpackageindex.com/firebase/firebase-ios-sdk">
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffirebase%2Ffirebase-ios-sdk%2Fbadge%3Ftype%3Dswift-versions"/>
  </a>
</p>

# Pendo Crash Reporter Engine (Forked from Firebase)

This repository is a stripped-down fork of the [Firebase iOS SDK](https://github.com/firebase/firebase-ios-sdk). It isolates the core device-side crash capture engine of **Firebase Crashlytics** specifically for integration into the **Pendo iOS SDK**.

### Modifications from Upstream
- **Removed Network/Upload Logic**: Stripped GoogleDataTransport to ensure crashes are processed and saved locally without being uploaded to Google servers.
- **Removed Firebase Core Dependency**: Removed initialization ties to `FIRApp`, allowing standalone initialization.
- **Removed Extraneous Modules**: Stripped Analytics, Performance, Messaging, FBLPromises, nanopb, and other unneeded Firebase products.
- **Custom Delegate Implementation**: Added `PNDCrashReporterDelegate` to provide Phase 2 report parsing directly to the Pendo SDK.
- **Symbol Collision Prevention**: Implemented a macro-based prefixing system (`PNDCrashReporter+Namespace.h`) that renames all underlying `FIR*` classes, structs, and constants to `PND_FIR*` at compile time. This ensures that an app containing both the Pendo SDK and the full Firebase SDK will not encounter duplicate symbol linker errors or undefined runtime behavior.

## Installation via CocoaPods

To consume this engine in a project (like the Pendo SDK), you must specify the exact repository branch and the specific version tag that contains our rebased changes.

Add the following to your `Podfile`:

```ruby
pod 'PendoCrashReporter', :git => 'https://github.com/pendo-io/firebase-ios-sdk.git', :tag => 'pendo-12.11.0'
```

*Note: Ensure the `tag` matches the current version specified in the `PendoCrashReporter.podspec`.*

## License

The contents of this repository are licensed under the
[Apache License, version 2.0](http://www.apache.org/licenses/LICENSE-2.0).
