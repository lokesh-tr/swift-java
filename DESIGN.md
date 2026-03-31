# Kotlin JVM Target for JExtract

> **Swift-to-Kotlin Interop PoC [Hard, 350 hours]**
> *Test Tasks by Lokesh T. R. - Google Summer of Code 2026*

This document breaks down how the `--lang kotlin-jvm` feature works in `swift-java` and details the design decisions I made while building it.

## Architecture

The `--lang kotlin-jvm` flag generates Kotlin bindings for Swift binaries. The generator scans the Swift AST for top-level functions and maps primitive Swift types (like `Int`, `Bool`, `Double`) to their Kotlin equivalents.

Instead of just spitting out empty stubs, the code generates working bindings using the Java Foreign Function & Memory (FFM) API. For each Swift function, it drops in memory lookup calls via `SymbolLookup`, sets up `FunctionDescriptor` models for the arguments, and writes `invokeExact()` calls to bridge the two languages.

The codebase strictly separates text formatting from syntax analysis. The actual translation rules live in `KotlinJVMGenerator+KotlinTranslation.swift`. This file figures out the exact layout boundaries by evaluating `CType.javaType`. Moving the FFM type mapping out of the main loop means the `KotlinJVMGenerator` class only has to worry about printing text based on a clean intermediate model.

To prove it works end-to-end, check out the `Samples/KotlinExample` Gradle module. It builds a small Swift library (`MySwiftLib.swift`), links it, and runs a Kotlin `Main.kt` app that successfully calls the Swift primitives.

## Design Questions

### Trade-offs and shortcuts
I only implemented top-level functions. I skipped translating Swift objects and complex `.foreign` struct layouts to keep things simple and constrained strictly to primitives.

I also didn't implement string buffers. While strings are technically mapped inside the translation layer, the generator just drops them during FFM construction. Passing allocated string pointers requires complex memory templates and `Arena` handling that felt out of scope for a primitive-focused PoC.

I ignored callbacks and closures since FFI upcall stubs require a lot of C-bridge boilerplate. Error handling (mapping `throws` to Kotlin Exceptions) and `async` methods were also skipped.

For numeric types, Swift usually treats `Int` as a 64-bit integer, but the generator maps it to a 32-bit Kotlin `Int` to satisfy the requested type mappings. It works fine for basic type comparisons but obviously truncates larger values at runtime.

### What an ideal complete solution looks like
A production solution would generate full Kotlin data classes that mirror Swift structs by mapping memory offsets against `GroupLayout` abstractions.

Instead of blocking threads, the generated bindings would wrap Swift `async` methods in native Kotlin Coroutines (`suspend` functions). It would also wrap native pointers in `Arena.ofConfined().use { ... }` blocks to guarantee memory safety and prevent lifecycle leaks.

Code-wise, the current `FFMSwift2JavaGenerator` and the new `KotlinJVMGenerator` should be merged. The tool should parse the Swift AST into a single unified model, and then just pass that model to either a Java or Kotlin formatter. This would get rid of a lot of duplicate AST traversal logic.

### What's next if more time was available
The very first thing I'd build is `swift_std_String` memory translation via `MemorySegment`. Getting utf-8 byte arrays cleanly moving between Swift and Kotlin `Arena` contexts is critical.

After that, I'd add FFI upcall configurations to support closures. This would let developers pass Kotlin lambdas straight into Swift contexts.

Finally, I'd resolve the Gradle plugin constraints. Right now the sample is hardcoded to require JDK 25. A real solution should degrade gracefully and handle varying Gradle plugin versions and environments smoothly.

## Execution and Testing

### Requirements
* JDK 25 or higher
* Swift 6.2 or higher
* Gradle 8.0 or higher

### Running the Tests
To run the automated tests that verify AST parsing and Kotlin string generation:
```bash
swiftly run swift test --filter KotlinGenerationTests
```

### Running the End-to-End Example
To compile the mock Swift library and trigger the actual Kotlin execution:
```bash
./gradlew :Samples:KotlinExample:run
```
