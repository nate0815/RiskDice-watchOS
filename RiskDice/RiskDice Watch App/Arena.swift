//
//  Arena.swift
//  RiskDice Watch App
//
//  骰子活動的空間 —— 就是錶面那一塊，沒有畫出來的盤子或箱子。
//
//  ⭐ **純資料 ＋ 純函式**，不碰 SceneKit。邊界怎麼變成碰撞體是 `DiceScene` 的事；
//     這裡只回答「這個點離邊界多遠」「把它拉回裡面是哪裡」，所以測得了。
//

import simd

/// 場地的範圍（場景單位，見 `DiceScene.unitsPerMetre`）。
///
/// 座標：x 是畫面的左右、z 是畫面的上下（+z 朝畫面下方）、y 是離開錶面朝向使用者的方向。
/// 地面在 y = 0。
///
/// ⚠️ **邊界不是垂直的牆，是往內傾斜、在鏡頭的位置收成一點的斜面**（一個截頭的角錐）。
/// 鏡頭從正上方用透視看下來，骰子彈得越高、離鏡頭越近，投影到畫面上就越往外 ——
/// 邊界如果是垂直的，骰子彈高又靠邊時會有一半跑出螢幕。讓邊界順著鏡頭的視線傾斜，
/// 「在場內」就等於「在畫面內」，不管骰子彈多高都剛好在螢幕邊緣反彈。
///
/// 四個角各被一道斜邊切掉 —— 錶面的角是圓的，不切的話骰子滾進角落會被圓角裁到。
nonisolated struct Arena: Equatable {
    /// 地面高度上，左右邊界到中心的距離。
    let halfWidth: Float
    /// 地面高度上，上下邊界到中心的距離。
    let halfDepth: Float
    /// 地面高度上，每個角沿著邊被切掉的長度。
    let cornerCut: Float
    /// 隱形天花板的高度。
    let ceilingY: Float
    /// 所有側面邊界交會的那一點的高度 —— 就是鏡頭的高度。
    let apexY: Float

    /// 一道側面邊界：地面高度上是 `direction · p = distance` 這條線，往上朝 `apexY` 收攏。
    struct Side: Equatable {
        /// 水平方向上朝外的單位向量（y 分量是 0）。
        var direction: SIMD3<Float>
        /// 地面高度上，這道邊界離中心多遠。
        var distance: Float
    }

    /// 八道側面邊界：四邊加四個斜角。
    var sides: [Side] {
        let diagonal = (halfWidth + halfDepth - cornerCut) / Float(2).squareRoot()
        let r = 1 / Float(2).squareRoot()
        return [
            Side(direction: SIMD3<Float>(1, 0, 0), distance: halfWidth),
            Side(direction: SIMD3<Float>(-1, 0, 0), distance: halfWidth),
            Side(direction: SIMD3<Float>(0, 0, 1), distance: halfDepth),
            Side(direction: SIMD3<Float>(0, 0, -1), distance: halfDepth),
            Side(direction: SIMD3<Float>(r, 0, r), distance: diagonal),
            Side(direction: SIMD3<Float>(r, 0, -r), distance: diagonal),
            Side(direction: SIMD3<Float>(-r, 0, r), distance: diagonal),
            Side(direction: SIMD3<Float>(-r, 0, -r), distance: diagonal),
        ]
    }

    /// 這道邊界朝外的單位法線。因為邊界往內傾斜，法線會稍微朝上。
    func outwardNormal(of side: Side) -> SIMD3<Float> {
        simd_normalize(side.direction * apexY + SIMD3<Float>(0, side.distance, 0))
    }

    /// 一個點在這道邊界的內側多深（負的表示已經穿出去了）。
    func depthInside(_ side: Side, at position: SIMD3<Float>) -> Float {
        // 平面通過地面上的那條線與頂點 (0, apexY, 0)：
        //   apexY · (direction · p) + distance · y = distance · apexY
        let numerator = side.distance * apexY
            - apexY * simd_dot(side.direction, position)
            - side.distance * position.y
        return numerator / (apexY * apexY + side.distance * side.distance).squareRoot()
    }

    /// 一個點離最近的邊界（含地面與天花板）多遠。負的表示在場外。
    func clearance(at position: SIMD3<Float>) -> Float {
        var nearest = min(position.y, ceilingY - position.y)
        for side in sides {
            nearest = min(nearest, depthInside(side, at: position))
        }
        return nearest
    }

    /// 骰子的中心是不是跑到場外了。
    ///
    /// - Parameter tolerance: 容許超出多少還不算出界。正常碰撞時骰子中心離邊界至少有
    ///   內切球半徑那麼遠，所以這個值不必大；它只是用來吸收求解器瞬間的穿透。
    func isOutOfBounds(_ position: SIMD3<Float>, tolerance: Float) -> Bool {
        clearance(at: position) < -tolerance
    }

    /// 把一個點拉回場內，並且離每一道邊界（含地面與天花板）至少 `margin`。
    ///
    /// 重丟時用：骰子換了一個隨機朝向之後，原本貼著邊界的位置可能會讓它的角插進去。
    /// `margin` 取外接球半徑就保證任何朝向都不會穿過邊界。
    func clampedInside(_ position: SIMD3<Float>, margin: Float) -> SIMD3<Float> {
        var p = position
        p.y = min(max(p.y, margin), ceilingY - margin)

        // 高度定了之後只在水平方向上移動。推離一道邊界可能會碰到隔壁那道（角落），
        // 所以多繞幾圈；八道邊界的夾角都是鈍角，幾圈就收斂了。
        for _ in 0..<8 {
            var moved = false
            for side in sides {
                let shortfall = margin - depthInside(side, at: p)
                guard shortfall > 1e-5 else { continue }
                // 沿著 −direction 水平移動 δ，深度增加 δ · apexY / √(apexY² + distance²)。
                let slope = apexY / (apexY * apexY + side.distance * side.distance).squareRoot()
                p -= side.direction * (shortfall / slope)
                moved = true
            }
            if !moved { break }
        }
        return p
    }
}
