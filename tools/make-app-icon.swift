//
//  make-app-icon.swift
//
//  畫 app 圖示：一顆正對著鏡頭的黑色二十面骰，正中央那一面是紅字「大凶」，其餘是白字「大吉」。
//  （圖示自己畫，一個二十面體。）
//
//  用法（在 repo 根目錄）：
//      swift tools/make-app-icon.swift <輸出的 png 路徑>
//
//  幾何是真的算出來的：十二個頂點、二十個面，轉到其中一面正對鏡頭，正投影到平面上。
//  骰面文字的排法照 `DieFaceTexture.swift`（同樣的三角形、同樣的字級比例與位置）。
//
//  ⚠️ 手錶的圖示會被裁成**圓形**：骰子要整顆落在內切圓裡，四個角落只能是背景。
//  ⚠️ 輸出不能有透明度 —— iOS 的圖示有 alpha 會被拒絕。
//

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import simd

// MARK: - 可調的數字

let canvas = 1024
/// 骰子輪廓的最大半徑，佔畫布寬度的比例。圓形裁切的半徑是 0.5，留一點邊。
let dieRadiusFraction = 0.405
let doomColor = CGColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1)      // 同 DieFaceTexture.xiong
let luckColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let lightDirection = simd_normalize(SIMD3<Double>(-0.45, 0.55, 0.70))

// MARK: - 二十面體

let phi = (1 + 5.0.squareRoot()) / 2
var vertices: [SIMD3<Double>] = []
for s1 in [-1.0, 1.0] {
    for s2 in [-1.0, 1.0] {
        vertices.append(SIMD3(0, s1, s2 * phi))
        vertices.append(SIMD3(s1, s2 * phi, 0))
        vertices.append(SIMD3(s2 * phi, 0, s1))
    }
}

/// 找出所有的面：三個頂點兩兩相距一個邊長（= 2）。
var faces: [[Int]] = []
for i in 0..<12 {
    for j in (i + 1)..<12 {
        for k in (j + 1)..<12 {
            let ab = simd_distance(vertices[i], vertices[j])
            let bc = simd_distance(vertices[j], vertices[k])
            let ca = simd_distance(vertices[k], vertices[i])
            if abs(ab - 2) < 1e-6, abs(bc - 2) < 1e-6, abs(ca - 2) < 1e-6 {
                faces.append([i, j, k])
            }
        }
    }
}
precondition(faces.count == 20, "二十面體應該有二十個面，算出 \(faces.count) 個")

// MARK: - 轉到其中一面正對鏡頭、那一面的一個頂點朝上

let front = faces[0]
let frontCentre = (vertices[front[0]] + vertices[front[1]] + vertices[front[2]]) / 3
let zAxis = simd_normalize(frontCentre)
let towardApex = vertices[front[0]] - frontCentre
let yAxis = simd_normalize(towardApex - simd_dot(towardApex, zAxis) * zAxis)
let xAxis = simd_cross(yAxis, zAxis)

func toView(_ p: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(simd_dot(p, xAxis), simd_dot(p, yAxis), simd_dot(p, zAxis))
}
let viewVertices = vertices.map(toView)

let maxRadius = viewVertices.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }.max()!
let scale = Double(canvas) * dieRadiusFraction / maxRadius
let centre = Double(canvas) / 2

func project(_ p: SIMD3<Double>) -> CGPoint {
    CGPoint(x: centre + p.x * scale, y: centre + p.y * scale)
}

// MARK: - 畫布

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("建不出點陣圖 context") }

// 背景：深灰，中間亮一點、往外暗下去。跟 app 裡的底同一個調子。
let side = CGFloat(canvas)
let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.42, green: 0.42, blue: 0.47, alpha: 1),
        CGColor(red: 0.20, green: 0.20, blue: 0.23, alpha: 1),
        CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1),
    ] as CFArray,
    locations: [0, 0.55, 1]
)!
context.drawRadialGradient(
    background,
    startCenter: CGPoint(x: side * 0.5, y: side * 0.54), startRadius: 0,
    endCenter: CGPoint(x: side * 0.5, y: side * 0.5), endRadius: side * 0.74,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// MARK: - 看得到的面

struct VisibleFace {
    var points: [CGPoint]        // 逆時針（從鏡頭看）
    var normal: SIMD3<Double>
    var isFront: Bool
}

var visible: [VisibleFace] = []
for (index, face) in faces.enumerated() {
    var corners = face.map { viewVertices[$0] }
    var normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
    let centroid = (corners[0] + corners[1] + corners[2]) / 3
    if simd_dot(normal, centroid) < 0 {          // 讓法線朝外、頂點順序逆時針
        corners.swapAt(1, 2)
        normal = -normal
    }
    guard normal.z > 1e-6 else { continue }      // 背對鏡頭的不畫
    // 文字的「上」朝畫面上最高的那個頂點，轉到那個頂點排第一個（順序仍是逆時針）。
    let top = (0..<3).max { corners[$0].y < corners[$1].y }!
    let ordered = (0..<3).map { corners[(top + $0) % 3] }
    visible.append(VisibleFace(points: ordered.map(project), normal: normal, isFront: index == 0))
}

// 骰子的影子：先把整個輪廓塗一次，帶柔邊的陰影。
context.saveGState()
context.setShadow(
    offset: CGSize(width: side * 0.012, height: -side * 0.022), blur: side * 0.05,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.65)
)
context.beginTransparencyLayer(auxiliaryInfo: nil)
context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
for face in visible {
    context.addLines(between: face.points)
    context.closePath()
    context.fillPath()
}
context.endTransparencyLayer()
context.restoreGState()

/// 把 `DieFaceTexture` 那個貼圖空間（原點在左上、y 向下、邊長 1）的三角形，對到畫面上的三角形。
func textureToScreen(_ p: [CGPoint]) -> CGAffineTransform {
    // 貼圖上的三個頂點：上、左下、右下（同 DieFaceTexture 的註解）。
    let u: [CGPoint] = [CGPoint(x: 0.5, y: 0.04), CGPoint(x: 0.03, y: 0.90), CGPoint(x: 0.97, y: 0.90)]
    let du1 = u[1].x - u[0].x, dv1 = u[1].y - u[0].y
    let du2 = u[2].x - u[0].x, dv2 = u[2].y - u[0].y
    let det = du1 * dv2 - du2 * dv1
    let dx1 = p[1].x - p[0].x, dy1 = p[1].y - p[0].y
    let dx2 = p[2].x - p[0].x, dy2 = p[2].y - p[0].y
    let a = (dx1 * dv2 - dx2 * dv1) / det
    let c = (dx2 * du1 - dx1 * du2) / det
    let b = (dy1 * dv2 - dy2 * dv1) / det
    let d = (dy2 * du1 - dy1 * du2) / det
    let tx = p[0].x - a * u[0].x - c * u[0].y
    let ty = p[0].y - b * u[0].x - d * u[0].y
    return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
}

/// 圖示縮到手錶上只有幾十個像素寬，筆畫要粗才看得出字。
/// 依序找系統裡有的粗體中文字型；都沒有才退回系統字型。
let glyphFontCandidates = ["PingFangTC-Semibold", "PingFangTC-Medium", "HiraginoSans-W7", "STHeitiTC-Medium"]
let glyphFontName: String? = glyphFontCandidates.first { NSFont(name: $0, size: 10) != nil }

func glyphFont(size: CGFloat) -> NSFont {
    if let name = glyphFontName, let font = NSFont(name: name, size: size) { return font }
    return NSFont.systemFont(ofSize: size, weight: .heavy)
}

func drawGlyph(_ string: String, fontSize: CGFloat, color: CGColor, centredAtTexture point: CGPoint) {
    let font = glyphFont(size: fontSize)
    // 負的筆畫寬度＝填色之外再描一圈邊（單位是字級的百分比），把字加粗。
    // 系統的中文字型最粗也不夠粗，縮到手錶上會糊成細線。
    let attributes = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
        kCTStrokeColorAttributeName: color,
        kCTStrokeWidthAttributeName: -7.0 as CFNumber,
    ] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attributes)!)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.saveGState()
    context.translateBy(x: point.x, y: point.y)
    context.scaleBy(x: 1, y: -1)                 // 貼圖空間的 y 向下，字要翻回來才是正的
    context.textPosition = CGPoint(x: -bounds.width / 2 - bounds.origin.x, y: -bounds.height / 2 - bounds.origin.y)
    CTLineDraw(line, context)
    context.restoreGState()
}

// 由遠到近畫（看得到的面彼此不重疊，順序其實無所謂，但邊線疊起來比較好看）。
for face in visible.sorted(by: { $0.normal.z < $1.normal.z }) {
    let lit = max(0, simd_dot(face.normal, lightDirection))
    let shade = 0.035 + 0.17 * pow(lit, 1.4)
    context.setFillColor(CGColor(red: shade, green: shade, blue: shade * 1.06, alpha: 1))
    context.addLines(between: face.points)
    context.closePath()
    context.fillPath()

    // 文字：照 DieFaceTexture 的排法 —— 兩個字直書，字級是貼圖邊長的 0.30，中心在 y = 0.56。
    context.saveGState()
    context.addLines(between: face.points)
    context.closePath()
    context.clip()
    context.concatenate(textureToScreen(face.points))
    let fontSize: CGFloat = 0.30
    let gap = fontSize * 0.52
    let color = face.isFront ? doomColor : luckColor
    drawGlyph("大", fontSize: fontSize, color: color, centredAtTexture: CGPoint(x: 0.5, y: 0.56 - gap))
    drawGlyph(face.isFront ? "凶" : "吉", fontSize: fontSize, color: color, centredAtTexture: CGPoint(x: 0.5, y: 0.56 + gap))
    context.restoreGState()

    // 邊線：讓黑色的面彼此分得開。
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.setLineWidth(side * 0.004)
    context.setLineJoin(.round)
    context.addLines(between: face.points)
    context.closePath()
    context.strokePath()
}

// MARK: - 輸出

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("用法：swift tools/make-app-icon.swift <輸出的 png 路徑>\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("寫不出 png") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("寫不出 png") }
print("wrote \(url.path)  \(image.width)x\(image.height)  visible faces: \(visible.count)  font: \(glyphFontName ?? "system heavy")")
