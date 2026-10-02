//
//  TestSupport.swift
//  RiskDice Watch AppTests
//

/// 固定種子的亂數產生器 —— 讓統計測試可重現，不會偶爾紅一次。
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
