public func returnInt() -> Int {
  return 42
}

public func passingArguments(a: Int, b: Double, flag: Bool) -> Double {
  if flag {
    return Double(a) + b
  } else {
    return Double(a) - b
  }
}


