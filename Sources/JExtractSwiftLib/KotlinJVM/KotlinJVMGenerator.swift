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
import SwiftJavaConfigurationShared
import SwiftSyntax
import SwiftSyntaxBuilder

import struct Foundation.URL
import class Foundation.FileManager
import struct Foundation.Data

package class KotlinJVMGenerator: Swift2JavaGenerator {
  let log: Logger
  let config: Configuration
  let analysis: AnalysisResult
  let swiftModuleName: String
  let kotlinPackage: String
  let swiftOutputDirectory: String
  let kotlinOutputDirectory: String
  var thunkRegistry: ThunkNameRegistry
  let lookupContext: SwiftTypeLookupContext
  var expectedOutputSwiftFileNames: Set<String>

  package init(
    config: Configuration,
    translator: Swift2JavaTranslator,
    kotlinPackage: String,
    swiftOutputDirectory: String,
    kotlinOutputDirectory: String
  ) {
    self.log = Logger(label: "kotlin-jvm-generator", logLevel: translator.log.logLevel)
    self.config = config
    self.analysis = translator.result
    self.swiftModuleName = translator.swiftModuleName
    self.kotlinPackage = kotlinPackage
    self.swiftOutputDirectory = swiftOutputDirectory
    self.kotlinOutputDirectory = kotlinOutputDirectory
    self.lookupContext = translator.lookupContext
    self.thunkRegistry = ThunkNameRegistry()

    if translator.config.writeEmptyFiles ?? false {
      self.expectedOutputSwiftFileNames = Set(
        translator.inputs.compactMap { (input) -> String? in
          guard let fileName = input.path.split(separator: "/").last else { return nil }
          guard fileName.hasSuffix(".swift") else { return nil }
          return String(fileName.replacing(".swift", with: "+SwiftJava.swift"))
        }
      )
      // Also include filtered-out files so SwiftPM gets the empty outputs it expects
      for path in translator.filteredOutPaths {
        if let fileName = path.split(separator: "/").last, fileName.hasSuffix(".swift") {
          self.expectedOutputSwiftFileNames.insert(
            String(fileName.replacing(".swift", with: "+SwiftJava.swift"))
          )
        }
      }
      self.expectedOutputSwiftFileNames.insert("\(translator.swiftModuleName)Module+SwiftJava.swift")
      self.expectedOutputSwiftFileNames.insert("Foundation+SwiftJava.swift")
    } else {
      self.expectedOutputSwiftFileNames = []
    }
  }

  package func generate() throws {
    var printer = CodePrinter()
    try writeKotlinSources(printer: &printer)

    let kotlinPackagePath = kotlinPackage.replacingOccurrences(of: ".", with: "/")
    let filename = "\(self.swiftModuleName).kt"
    if let outputFile = try printer.writeContents(
      outputDirectory: kotlinOutputDirectory,
      javaPackagePath: kotlinPackagePath,
      filename: filename
    ) {
      log.info("Generated: \((filename).bold) (at \(outputFile.absoluteString))")
    }

    try writeSwiftExpectedEmptySources()
  }

  package func writeKotlinSources(printer: inout CodePrinter) throws {
    printHeader(&printer)
    
    if !kotlinPackage.isEmpty {
      printer.print("package \(kotlinPackage)")
      printer.print("")
    }

    printer.print("import java.lang.foreign.*")
    printer.print("import java.lang.invoke.MethodHandle")
    printer.print("")

    printer.print("private val LIBRARIES_LOADED = run {")
    printer.print("    org.swift.swiftkit.core.SwiftLibraries.loadLibraryWithFallbacks(org.swift.swiftkit.core.SwiftLibraries.LIB_NAME_SWIFT_CORE)")
    printer.print("    org.swift.swiftkit.core.SwiftLibraries.loadLibraryWithFallbacks(org.swift.swiftkit.core.SwiftLibraries.LIB_NAME_SWIFT_JAVA)")
    printer.print("    org.swift.swiftkit.core.SwiftLibraries.loadLibraryWithFallbacks(org.swift.swiftkit.core.SwiftLibraries.LIB_NAME_SWIFT_RUNTIME_FUNCTIONS)")
    printer.print("    org.swift.swiftkit.core.SwiftLibraries.loadLibraryWithFallbacks(\"\(swiftModuleName)\")")
    printer.print("    true")
    printer.print("}")
    printer.print("")

    printer.print("private val SYMBOL_LOOKUP: SymbolLookup = SymbolLookup.loaderLookup().or(Linker.nativeLinker().defaultLookup())")
    printer.print("private fun findOrThrow(symbol: String): MemorySegment {")
    printer.print("    return SYMBOL_LOOKUP.find(symbol).orElseThrow { UnsatisfiedLinkError(\"unresolved symbol: $symbol\") }")
    printer.print("}")
    printer.print("")

    var translation = KotlinTranslation(
      config: config,
      knownTypes: SwiftKnownTypes(symbolTable: lookupContext.symbolTable),
      thunkRegistry: thunkRegistry
    )

    for funcDecl in analysis.importedGlobalFuncs {
      do {
        let translated = try translation.translate(funcDecl)
        printKotlinGlobalFunction(&printer, translated)
      } catch {
        log.info("Skipping '\(funcDecl.name)': \(error)")
      }
    }
  }

  func printHeader(_ printer: inout CodePrinter) {
    printer.print("// Generated by jextract-swift --lang kotlin-jvm")
    printer.print("// Swift module: \(swiftModuleName)")
    printer.print("")
  }

  func printKotlinGlobalFunction(_ printer: inout CodePrinter, _ translated: TranslatedKotlinFunctionDecl) {
    let funcName = translated.name
    let thunkName = translated.thunkName
    let params = translated.parameters

    printer.print("private val ADDR_\(funcName) = findOrThrow(\"\(thunkName)\")")
    
    let returnClass = translated.result.kotlinType == "Unit" ? "FunctionDescriptor.ofVoid(" : "FunctionDescriptor.of(\(translated.result.ffmLayout!)"
    let fFMLayouts = params.map { $0.ffmLayout }
    let descriptorArgs: String
    if translated.result.kotlinType == "Unit" {
        descriptorArgs = fFMLayouts.joined(separator: ", ")
    } else {
        descriptorArgs = fFMLayouts.isEmpty ? "" : ", " + fFMLayouts.joined(separator: ", ")
    }
    printer.print("private val DESC_\(funcName) = \(returnClass)\(descriptorArgs))")
    printer.print("private val HANDLE_\(funcName) = Linker.nativeLinker().downcallHandle(ADDR_\(funcName), DESC_\(funcName))")
    printer.print("")

    let paramString = params.map { "\($0.name): \($0.kotlinType)" }.joined(separator: ", ")
    let returnString = translated.result.kotlinType == "Unit" ? "" : ": \(translated.result.kotlinType) "
    
    printer.printBraceBlock("fun \(funcName)(\(paramString))\(returnString)") { printer in
      let argsToPass = params.map { p in
         if p.kotlinType == "Boolean" {
             return "if (\(p.name)) 1.toByte() else 0.toByte()"
         } else if p.ffmLayout == "ValueLayout.JAVA_LONG" && p.kotlinType == "Int" {
             // Upcast required if user passes 32-bit Int when Layout is LONG
             return "\(p.name).toLong()"
         }
         return p.name
      }.joined(separator: ", ")

      let downcall = "HANDLE_\(funcName).invokeExact(\(argsToPass))"

      if translated.result.kotlinType == "Unit" {
          printer.print("\(downcall)")
      } else if translated.result.kotlinType == "Boolean" {
          printer.print("return (\(downcall) as Byte) != 0.toByte()")
      } else if translated.result.ffmLayout == "ValueLayout.JAVA_LONG" && translated.result.kotlinType == "Int" {
          printer.print("return (\(downcall) as Long).toInt()")
      } else {
          printer.print("return \(downcall) as \(translated.result.kotlinType)")
      }
    }
    printer.print("")
  }

  func writeSwiftExpectedEmptySources() throws {
    guard !expectedOutputSwiftFileNames.isEmpty else { return }
    let fileManager = FileManager.default
    
    if !fileManager.fileExists(atPath: swiftOutputDirectory) {
      try? fileManager.createDirectory(atPath: swiftOutputDirectory, withIntermediateDirectories: true)
    }
    
    for file in expectedOutputSwiftFileNames {
      let url = URL(fileURLWithPath: swiftOutputDirectory).appendingPathComponent(file)
      let path = url.path
      if !fileManager.fileExists(atPath: path) {
        fileManager.createFile(atPath: path, contents: Data())
      }
    }
  }
}
