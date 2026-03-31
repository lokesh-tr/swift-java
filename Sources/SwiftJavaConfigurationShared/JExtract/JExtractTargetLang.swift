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

/// Determines which target language JExtract should generate code for.
public enum JExtractTargetLang: String, Sendable, Codable {
  /// Java (default)
  case java

  /// Kotlin JVM
  case kotlinJvm = "kotlin-jvm"

  public static var `default`: JExtractTargetLang {
    .java
  }
}
