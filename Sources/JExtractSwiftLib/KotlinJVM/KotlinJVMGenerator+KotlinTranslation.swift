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

import SwiftJavaConfigurationShared

enum KotlinTranslationError: Error, CustomStringConvertible {
  case unsupportedType(SwiftType)

  var description: String {
    switch self {
    case .unsupportedType(let type):
      return "Unsupported type for Kotlin generation: \(type)"
    }
  }
}

package struct TranslatedKotlinFunctionDecl {
  let name: String
  let thunkName: String
  let parameters: [TranslatedKotlinParameter]
  let result: TranslatedKotlinResult
}

package struct TranslatedKotlinParameter {
  let name: String
  let kotlinType: String
  let ffmLayout: String
}

package struct TranslatedKotlinResult {
  let kotlinType: String
  let ffmLayout: String? // nil for Unit
}

package struct KotlinTranslation {
  let config: Configuration
  let knownTypes: SwiftKnownTypes
  var thunkRegistry: ThunkNameRegistry

  mutating func translate(_ decl: ImportedFunc) throws -> TranslatedKotlinFunctionDecl {
    let funcName = decl.name
    let thunkName = thunkRegistry.functionThunkName(decl: decl)

    var parameters: [TranslatedKotlinParameter] = []
    for param in decl.functionSignature.parameters {
      let paramName = param.parameterName ?? "arg"
      let mapped = try translateType(param.type)
      parameters.append(
        TranslatedKotlinParameter(name: paramName, kotlinType: mapped.kotlinType, ffmLayout: mapped.ffmLayout)
      )
    }

    let resultMapped = try translateResultType(decl.functionSignature.result.type)

    return TranslatedKotlinFunctionDecl(
      name: funcName,
      thunkName: thunkName,
      parameters: parameters,
      result: resultMapped
    )
  }

  private func translateType(_ swiftType: SwiftType) throws -> (kotlinType: String, ffmLayout: String) {
    if let cType = try? CType(cdeclType: swiftType) {
      switch cType.javaType {
      case .long: return ("Int", "ValueLayout.JAVA_LONG")
      case .int: return ("Int", "ValueLayout.JAVA_INT")
      case .boolean: return ("Boolean", "ValueLayout.JAVA_BYTE")
      case .double: return ("Double", "ValueLayout.JAVA_DOUBLE")
      case .float: return ("Float", "ValueLayout.JAVA_FLOAT")
      case .byte: return ("Byte", "ValueLayout.JAVA_BYTE")
      case .short: return ("Short", "ValueLayout.JAVA_SHORT")
      case .char: return ("Char", "ValueLayout.JAVA_CHAR")
      default: throw KotlinTranslationError.unsupportedType(swiftType)
      }
    }
    throw KotlinTranslationError.unsupportedType(swiftType)
  }

  private func translateResultType(_ swiftType: SwiftType) throws -> TranslatedKotlinResult {
    if case .tuple(let tuple) = swiftType, tuple.isEmpty {
      return TranslatedKotlinResult(kotlinType: "Unit", ffmLayout: nil)
    }
    let mapped = try translateType(swiftType)
    return TranslatedKotlinResult(kotlinType: mapped.kotlinType, ffmLayout: mapped.ffmLayout)
  }
}
