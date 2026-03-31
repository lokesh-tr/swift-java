//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CodePrinting
@testable import JExtractSwiftLib
import SwiftJavaConfigurationShared
import Testing

@Suite("Kotlin Generation Tests")
struct KotlinGenerationTests {

  @Test("Generate Kotlin top level functions")
  func testKotlinTopLevelFunctions() throws {
    let input = """
    public func mySyncFunc(a: Int, b: Double, flag: Bool) {}
    public func returnsInt() -> Int32 { return 0 }
    """

    var config = Configuration()
    config.swiftModule = "SwiftModule"
    config.lang = .kotlinJvm
    let translator = Swift2JavaTranslator(config: config)
    try translator.analyze(path: "/fake/Fake.swift", text: input)
    
    let generator = KotlinJVMGenerator(
        config: config,
        translator: translator,
        kotlinPackage: "com.example.swift",
        swiftOutputDirectory: "/fake",
        kotlinOutputDirectory: "/fake"
    )

    var printer = CodePrinter()
    try generator.writeKotlinSources(printer: &printer)
    let output = printer.finalize()
    
    #expect(output.contains("fun mySyncFunc(a: Int, b: Double, flag: Boolean)"))
    #expect(output.contains("fun returnsInt(): Int"))
    #expect(output.contains("invokeExact("))
    #expect(output.contains("private val SYMBOL_LOOKUP: SymbolLookup"))
  }
}
