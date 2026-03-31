package com.example.swift

fun main() {
    println("Invoking Kotlin-emitted FFM to Swift...")
    
    val x = returnInt()
    println("returnInt() = $x")

    val y = passingArguments(10, 5.5, true)
    println("passingArguments(10, 5.5, true) = $y")
    
    val z = passingArguments(10, 5.5, false)
    println("passingArguments(10, 5.5, false) = $z")

    println("Done!")
}
