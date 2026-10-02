//
//  Icosahedron.swift
//  RiskDice Watch App
//
//  正二十面體的幾何。SceneKit 沒有內建這個形狀，要自己算。
//

import SceneKit

nonisolated enum Icosahedron {

    /// 面數。
    static let faceCount = 20

    /// 哪一面是「大凶」。**恰好一面**，其餘十九面都是大吉。
    ///
    /// ⚠️ 這個值是任意選的，而且**必須保持只有一個** —— 機率的正確性靠的是
    /// 「二十面對稱 ＋ 初始朝向均勻隨機」，不是靠這個編號（見 README.zh-TW.md
    /// 「機率為什麼是精確的 1/20」）。改成兩面大凶就等於偷偷把機率變成 2/20。
    static let doomFaceIndex = 0

    /// 十二個頂點，用黃金比例構造。先不正規化，`makeGeometry` 會縮放到指定半徑。
    ///
    /// 這是正二十面體的標準構造：三個互相垂直的黃金矩形，十二個角就是十二個頂點。
    private static let rawVertices: [SIMD3<Float>] = {
        let t = (1 + sqrt(Float(5))) / 2
        return [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ]
    }()

    /// 二十個面，每個面三個頂點編號。繞序是**從外面看逆時針**，法線才會朝外。
    private static let faceIndices: [(Int, Int, Int)] = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]

    /// 每個面的三個頂點在貼圖上的位置。二十個面共用同一組 —— 貼圖裡只畫一個三角形，
    /// 每一面都把它完整貼一次。
    ///
    /// 第一個點是三角形的頂端（文字的「上」）。因為二十面都用同一組 UV，
    /// 文字相對於每個面的方向是一致的；但骰子停下來時那個面朝哪邊是隨機的，
    /// 所以**字不一定是正的** —— 這是刻意的，真的骰子也是這樣。
    private static let faceUVs: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.04),
        CGPoint(x: 0.03, y: 0.90),
        CGPoint(x: 0.97, y: 0.90),
    ]

    /// 建出骰子的幾何。
    ///
    /// - 頂點**不共用**：二十面 × 三頂點 = 六十個頂點。正二十面體的一個頂點本來被五個面
    ///   共用，但共用的話沒辦法給每個面自己的 UV 與法線 —— 會變成平滑著色，看起來像顆球。
    /// - 分成兩個 element：十九個大吉面一組、一個大凶面一組，各自對應一個材質。
    ///   這樣只有兩次材質切換，不是二十次。
    static func makeGeometry(radius: Float, jiMaterial: SCNMaterial, xiongMaterial: SCNMaterial) -> SCNGeometry {
        let jiFaces = (0..<faceCount).filter { !isDoom($0) }
        let xiongFaces = (0..<faceCount).filter { isDoom($0) }
        return makeGeometry(
            radius: radius,
            faceGroups: [jiFaces, xiongFaces],
            materials: [jiMaterial, xiongMaterial]
        )
    }

    #if DEBUG
    /// **只給驗證用**：二十個面各用一個材質，才能在每一面畫上自己的編號。
    ///
    /// 用途是驗證「程式讀出的面與畫面上朝上的面一致」—— 十九個大吉面長得一模一樣，
    /// 不標編號就只對得出大凶那一面。產品不會走到這裡（見 `DebugOptions`）。
    static func makeNumberedGeometry(radius: Float, materials: [SCNMaterial]) -> SCNGeometry {
        precondition(materials.count == faceCount, "每一面要有一個材質")
        return makeGeometry(
            radius: radius,
            faceGroups: (0..<faceCount).map { [$0] },
            materials: materials
        )
    }
    #endif

    /// - Parameter faceGroups: 哪些面共用同一個材質。第 n 組對應 `materials[n]`。
    private static func makeGeometry(
        radius: Float,
        faceGroups: [[Int]],
        materials: [SCNMaterial]
    ) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var elements: [SCNGeometryElement] = []

        let unitVertices = rawVertices.map { simd_normalize($0) * radius }

        for group in faceGroups {
            var indices: [Int32] = []

            for faceIndex in group {
                let face = faceIndices[faceIndex]
                let a = unitVertices[face.0]
                let b = unitVertices[face.1]
                let c = unitVertices[face.2]

                // 平面著色：整個面共用一條法線，稜線才會是銳利的。
                let normal = simd_normalize(simd_cross(b - a, c - a))

                let base = Int32(positions.count)
                for (offset, vertex) in [a, b, c].enumerated() {
                    positions.append(SCNVector3(vertex.x, vertex.y, vertex.z))
                    normals.append(SCNVector3(normal.x, normal.y, normal.z))
                    uvs.append(faceUVs[offset])
                }
                indices.append(contentsOf: [base, base + 1, base + 2])
            }

            elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs),
            ],
            elements: elements
        )
        geometry.materials = materials
        return geometry
    }

    /// 第 `faceIndex` 面的朝外方向（骰子自己的座標系，單位向量）。
    ///
    /// 這是結果判讀的材料：骰子停下後，把這二十條方向轉到世界座標，
    /// 最接近正上方的那一條就是朝上的面。**純函式，不碰畫面也不碰物理引擎**，
    /// 所以寫得了單元測試。
    static func faceNormal(_ faceIndex: Int) -> SIMD3<Float> {
        let face = faceIndices[faceIndex]
        let a = simd_normalize(rawVertices[face.0])
        let b = simd_normalize(rawVertices[face.1])
        let c = simd_normalize(rawVertices[face.2])
        return simd_normalize(simd_cross(b - a, c - a))
    }

    /// 第 `faceIndex` 面是不是大凶。
    static func isDoom(_ faceIndex: Int) -> Bool {
        faceIndex == doomFaceIndex
    }
}
