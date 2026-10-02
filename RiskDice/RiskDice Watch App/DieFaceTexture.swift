//
//  DieFaceTexture.swift
//  RiskDice Watch App
//
//  骰面的貼圖。啟動時用系統字型在程式裡畫出來 —— 零外部素材。
//
//  ⚠️ 不能用 `UIGraphicsImageRenderer` 畫 —— 它在 watchOS 上不存在
//     （`'UIGraphicsImageRenderer' is unavailable in watchOS`）。
//     這裡直接開 `CGContext` ＋ 用 Core Text 排字，兩者在 watchOS 上都有。
//

import CoreGraphics
import CoreText
import UIKit

nonisolated enum DieFaceTexture {

    /// 貼圖邊長（像素）。只有兩張，而且骰子在錶上很小，256 夠用。
    private static let size = 256

    /// 白字「大吉」。十九個面共用同一張。
    static let ji = make(text: ("大", "吉"), color: UIColor.white.cgColor)

    /// 紅字「大凶」。只有一個面用（`Icosahedron.doomFaceIndex`）。
    static let xiong = make(
        text: ("大", "凶"),
        color: UIColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1).cgColor
    )

    #if DEBUG
    /// **只給驗證用**：畫上面編號的骰面（見 `Icosahedron.makeNumberedGeometry`）。
    /// 大凶那一面仍然用紅字，順便對 `Icosahedron.doomFaceIndex`。
    static func debugNumber(_ faceIndex: Int) -> CGImage {
        let color = Icosahedron.isDoom(faceIndex)
            ? UIColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1).cgColor
            : UIColor.white.cgColor
        return make(text: ("#", "\(faceIndex)"), color: color)
    }
    #endif

    /// 畫一張骰面：黑底，中央直書兩個字。
    ///
    /// 整張圖都塗黑、不只塗三角形區域 —— UV 取樣落在三角形外時（邊緣的反鋸齒）
    /// 才不會吃到未定義的顏色。
    private static func make(text: (String, String), color: CGColor) -> CGImage {
        let side = CGFloat(size)
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("建不出點陣圖 context —— 參數寫錯了才會發生")
        }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        let fontSize = side * 0.30
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)

        // ⚠️ Core Graphics 的原點在**左下**、y 向上；而 SceneKit 取樣貼圖時
        //    UV 的 (0,0) 在**左上**、y 向下。兩者相反，所以這裡的 y 要翻過來算。
        //    三角形在 UV 空間的三個頂點是 (0.5,0.04)、(0.03,0.90)、(0.97,0.90)，
        //    文字塊放在 UV y ≈ 0.56（重心略上方，因為兩個字是上下排的）。
        let centerY = side * (1 - 0.56)
        let gap = fontSize * 0.52

        draw(text.0, font: font, color: color, centeredAt: CGPoint(x: side / 2, y: centerY + gap), in: context)
        draw(text.1, font: font, color: color, centeredAt: CGPoint(x: side / 2, y: centerY - gap), in: context)

        guard let image = context.makeImage() else {
            preconditionFailure("CGContext.makeImage() 失敗")
        }
        return image
    }

    private static func draw(
        _ string: String,
        font: UIFont,
        color: CGColor,
        centeredAt center: CGPoint,
        in context: CGContext
    ) {
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ] as CFDictionary

        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        context.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.origin.x,
            y: center.y - bounds.height / 2 - bounds.origin.y
        )
        CTLineDraw(line, context)
    }
}
