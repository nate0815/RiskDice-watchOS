//
//  DiceScene.swift
//  RiskDice Watch App
//
//  骰子與它活動的空間。**沒有骰盤、沒有箱子** —— 錶面本身就是場地：
//  鏡頭從正上方往下看，隱形的邊界貼齊螢幕四邊，骰子撞到螢幕邊緣就彈回來。
//

import SceneKit
import UIKit

nonisolated enum DiceScene {

    /// ⚠️⚠️ **場景單位不是公尺，是「公尺 × `unitsPerMetre`」。**
    ///
    /// SceneKit 的物理引擎（Bullet）對**比它的碰撞邊界還小的物體**會失常 ——
    /// 用真實公尺尺度（骰子才 0.022 m）時，骰子會直接穿過地面消失，
    /// 而且不會有任何錯誤訊息。放大到這個尺度之後物體大小落在引擎的正常範圍內。
    ///
    /// ⚠️ 改這個值**不能**照比例去改重力 —— 見 `gravityMagnitude`。
    private static let unitsPerMetre: Float = 100

    /// 重力大小（場景單位／秒²）。**工作值，而且刻意不是物理正確的值。**
    ///
    /// 物理正確的值是 `9.8 × unitsPerMetre` = 980，但那個量級下 SceneKit 的求解器會垮掉：
    /// 每個時間步骰子掉的距離跟碰撞邊界同一個數量級，於是每步穿透、每步被推開 ——
    /// **骰子會從場地中央一路「爬」到牆角，永遠停不下來**，而且不會有任何錯誤訊息。
    /// （排除過程：阻尼拉到 0.95、質量從 0.008 改成 1.0、碰撞形狀換成盒子，三個都無效；
    /// 重力降回 -9.8 立刻就停了。）
    ///
    /// 重力的方向是「朝錶面裡面」（−y）。鏡頭從正上方看，所以骰子彈起來就是朝使用者飛過來。
    ///
    /// 代價是下落比真實世界慢。真正要調到「像在丟骰子」是之後的工作，
    /// 而那**必須在實機上調**。
    private static let gravityMagnitude: Float = 120

    /// 真實世界的尺寸（公尺）。
    private enum RealSize {
        /// 骰子外接球半徑。⚠️ 換算成場景單位後不能小於約 1。
        static let dieRadius: Float = 0.011
    }

    /// 構圖（全部是工作值）。
    private enum Framing {
        /// 骰子直徑占畫面寬度的比例。大一點字看得清楚，小一點骰子才有地方彈。
        static let dieWidthFraction: Float = 0.36
        /// 鏡頭的垂直視角。窄一點透視變形小（骰子在邊上不會被拉歪），
        /// 寬一點彈起來時「朝你飛過來」的感覺比較強。
        static let fieldOfViewDegrees: Float = 30
        /// 畫面看得到的範圍比場地大多少。邊界順著鏡頭的視線傾斜（見 `Arena`），
        /// 所以骰子本來就不會超出畫面；這一圈只是讓它不要緊貼著螢幕的實體邊框。
        static let overscan: Float = 1.04
        /// 角落切掉的長度，相對於場地半寬。對應錶面的圓角。
        static let cornerCutFraction: Float = 0.30
        /// 天花板高度，相對於鏡頭高度。
        static let ceilingFraction: Float = 0.5
    }

    private static func u(_ metres: Float) -> Float { metres * unitsPerMetre }

    /// 骰子外接球半徑（場景單位）。
    static let dieRadius: Float = RealSize.dieRadius * unitsPerMetre

    static let dieNodeName = "die"

    // MARK: - 場地

    /// 鏡頭離地面多高，才會讓場地剛好填滿畫面。
    private static func cameraHeight(aspect: Float) -> Float {
        let halfWidth = dieRadius / Framing.dieWidthFraction
        let halfFieldOfView = Framing.fieldOfViewDegrees * .pi / 180 / 2
        // 垂直視角 → 地面上看得到的半高是 h·tan(θ/2)，半寬再乘上寬高比。
        return halfWidth * Framing.overscan / (aspect * tan(halfFieldOfView))
    }

    /// 依畫面的寬高比算出場地範圍 —— 場地的形狀跟著錶面走。
    ///
    /// - Parameter aspect: 畫面的寬 ÷ 高。
    static func arena(aspect: Float) -> Arena {
        let halfWidth = dieRadius / Framing.dieWidthFraction
        return Arena(
            halfWidth: halfWidth,
            halfDepth: halfWidth / aspect,
            cornerCut: halfWidth * Framing.cornerCutFraction,
            ceilingY: cameraHeight(aspect: aspect) * Framing.ceilingFraction,
            apexY: cameraHeight(aspect: aspect)
        )
    }

    // MARK: - 組場景

    /// - Parameter aspect: 畫面的寬 ÷ 高。場地與鏡頭都由它決定。
    static func make(aspect: Float) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black

        scene.physicsWorld.gravity = SCNVector3(0, -gravityMagnitude, 0)

        // 時間步長調細，讓比較大的重力也穩得住。預設是 1/60。
        // ⚠️ 這會增加 CPU 負擔，而**手錶上順不順還沒驗過**（實機部署卡住）。
        scene.physicsWorld.timeStep = 1.0 / 180

        let arena = arena(aspect: aspect)

        scene.rootNode.addChildNode(makeGround(arena: arena))
        for boundary in makeBoundaries(arena: arena) {
            scene.rootNode.addChildNode(boundary)
        }
        scene.rootNode.addChildNode(makeDie())
        scene.rootNode.addChildNode(makeCamera(height: cameraHeight(aspect: aspect)))
        scene.rootNode.addChildNode(makeKeyLight(arena: arena))
        scene.rootNode.addChildNode(makeFillLight())

        return scene
    }

    // MARK: - 骰子

    private static func makeDie() -> SCNNode {
        let node = SCNNode(geometry: makeDieGeometry())
        node.name = dieNodeName
        // 起點：場地中央、離地一點點。朝向在 `DiceController` 啟動時抽。
        node.position = SCNVector3(0, dieRadius * 1.3, 0)

        // 凸包：正二十面體本來就是凸的，所以凸包跟真實形狀完全一致，
        // 而且比逐三角形的碰撞便宜很多。
        let shape = SCNPhysicsShape(
            geometry: node.geometry!,
            options: [.type: SCNPhysicsShape.ShapeType.convexHull]
        )
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        // ⚠️ 質量要配合場景尺度，不是填真骰子的 0.008 kg。
        body.mass = 1.0
        // 彈性與摩擦是**兩個物體相乘**的：骰子 × 地面／邊界（見 `staticBody`）。
        body.restitution = 0.75
        body.friction = 0.6
        body.rollingFriction = 0.15           // 沒有這個，二十面體會像球一樣滾不停
        body.damping = 0.05
        body.angularDamping = 0.20
        // ⚠️ 讓引擎能把骰子判定為「靜止」並停止模擬它。
        //    關掉（或阻尼太低）的話骰子會**永遠微微抖動**，停不下來 ——
        //    碰撞邊界讓它在接觸面上持續被推開又落回。畫面上看得出來，但不會有錯誤。
        body.allowsResting = true
        node.physicsBody = body

        return node
    }

    private static func makeDieGeometry() -> SCNGeometry {
        #if DEBUG
        if DebugOptions.numberedFaces {
            let materials = (0..<Icosahedron.faceCount).map {
                dieMaterial(texture: DieFaceTexture.debugNumber($0))
            }
            return Icosahedron.makeNumberedGeometry(radius: dieRadius, materials: materials)
        }
        #endif

        return Icosahedron.makeGeometry(
            radius: dieRadius,
            jiMaterial: dieMaterial(texture: DieFaceTexture.ji),
            xiongMaterial: dieMaterial(texture: DieFaceTexture.xiong)
        )
    }

    /// 霧面黑。
    ///
    /// 底色是純黑，純黑在漫射光下不管怎麼照都是黑的 —— 二十個面會糊成一塊剪影，
    /// 看不出它是立體的。所以給一點**很寬、很淡的高光**：每個面依照它對著光的角度
    /// 亮度略有不同，稜線才看得出來。亮度壓得很低，看起來仍然是霧面而不是亮面塑膠。
    private static func dieMaterial(texture: CGImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = texture
        material.specular.contents = UIColor(white: 0.22, alpha: 1)
        material.shininess = 0.08
        return material
    }

    // MARK: - 場地：地面與隱形邊界

    /// 地面。**看得到的只有這一片** —— 它填滿整個畫面，所以看起來是「錶面」而不是一個盤子。
    ///
    /// 不用純黑：骰子是黑的，地面也黑的話骰子的輪廓會消失，只剩字浮在空中。
    private static func makeGround(arena: Arena) -> SCNNode {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = UIColor(white: 0.20, alpha: 1)

        // 畫出來的範圍比場地大很多：邊緣要落在畫面外，才不會看到「一塊板子的邊」。
        let visible = SCNPlane(width: CGFloat(arena.halfWidth * 8), height: CGFloat(arena.halfDepth * 8))
        visible.firstMaterial = material
        let node = SCNNode(geometry: visible)
        node.eulerAngles.x = -.pi / 2          // SCNPlane 預設是立著的，放平

        // 碰撞用一塊厚板，不用薄平面 —— 厚的才不會被高速的骰子穿過去。
        let slab = SCNBox(
            width: CGFloat(arena.halfWidth * 8),
            height: CGFloat(boundaryThickness),
            length: CGFloat(arena.halfDepth * 8),
            chamferRadius: 0
        )
        let collider = SCNNode()
        collider.position = SCNVector3(0, -boundaryThickness / 2, 0)
        collider.physicsBody = staticBody(shape: slab, restitution: 0.8)

        let ground = SCNNode()
        ground.addChildNode(node)
        ground.addChildNode(collider)
        return ground
    }

    /// 邊界碰撞體的厚度。厚一點才擋得住高速的骰子（薄的會被一步跨過去）。
    private static let boundaryThickness: Float = 4

    /// 隱形的邊界：八道往內傾斜的側面（四邊加四個斜角）與天花板。
    /// **只有碰撞體，沒有任何看得到的東西。**
    ///
    /// 側面為什麼是斜的，見 `Arena` 的說明：它們順著鏡頭的視線，
    /// 所以骰子不管彈多高，都是在螢幕邊緣反彈。
    private static func makeBoundaries(arena: Arena) -> [SCNNode] {
        let t = boundaryThickness
        var nodes: [SCNNode] = []

        // 每道側面是一塊厚板，內側表面剛好落在邊界平面上。
        // 板子開得比需要的大（往下埋進地面、往兩旁蓋過隔壁），縫隙才不會漏。
        let span = (arena.halfWidth + arena.halfDepth) * 4
        let slant = arena.ceilingY * 3

        for side in arena.sides {
            let normal = arena.outwardNormal(of: side)
            // 板子自己的三個軸：x 是厚度方向（朝外的法線）、z 沿著邊界水平延伸、y 沿著斜面往上。
            let along = SIMD3<Float>(-side.direction.z, 0, side.direction.x)
            let up = simd_cross(along, normal)

            // 邊界平面上、半個天花板高度的那一點，再往外退半個厚度就是板子的中心。
            let midHeight = arena.ceilingY / 2
            let onPlane = side.direction * (side.distance * (1 - midHeight / arena.apexY))
                + SIMD3<Float>(0, midHeight, 0)

            let box = SCNBox(width: CGFloat(t), height: CGFloat(slant), length: CGFloat(span), chamferRadius: 0)
            let node = SCNNode()
            node.simdPosition = onPlane + normal * (t / 2)
            node.simdOrientation = simd_quatf(simd_float3x3(columns: (normal, up, along)))
            node.physicsBody = staticBody(shape: box, restitution: 0.85)
            nodes.append(node)
        }

        // 天花板：擋住往鏡頭飛的骰子。正常丟擲碰不到它，是保險。
        let lid = SCNBox(width: CGFloat(span), height: CGFloat(t), length: CGFloat(span), chamferRadius: 0)
        let ceiling = SCNNode()
        ceiling.position = SCNVector3(0, arena.ceilingY + t / 2, 0)
        ceiling.physicsBody = staticBody(shape: lid, restitution: 0.3)
        nodes.append(ceiling)

        return nodes
    }

    private static func staticBody(shape geometry: SCNGeometry, restitution: CGFloat) -> SCNPhysicsBody {
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: geometry, options: nil))
        body.restitution = restitution
        body.friction = 0.8
        return body
    }

    // MARK: - 鏡頭與光

    /// 鏡頭在場地正上方往下看：畫面的右是 +x、畫面的下是 +z。
    private static func makeCamera(height: Float) -> SCNNode {
        let camera = SCNCamera()
        // ⚠️ 預設 zNear 是 1.0。場景放大到這個尺度之後剛好不會被裁掉，
        //    但縮回公尺尺度就會畫面全黑 —— 而且不會有任何錯誤訊息。
        camera.zNear = 0.5
        camera.zFar = Double(height * 3)
        camera.projectionDirection = .vertical
        camera.fieldOfView = CGFloat(Framing.fieldOfViewDegrees)

        let node = SCNNode()
        node.camera = camera
        node.position = SCNVector3(0, height, 0)
        // 不用 look(at:) —— 視線跟「上方」(0,1,0) 平行時它算不出畫面該朝哪邊轉。
        node.eulerAngles.x = -.pi / 2
        return node
    }

    /// 主光：從畫面左上方斜斜照下來，並且投影子。
    ///
    /// **影子是俯視時唯一的高度線索** —— 骰子彈起來時影子會跟它分開、落地時合在一起。
    /// 沒有影子的話，從正上方看只看得到骰子忽大忽小。
    /// ⚠️ 影子有效能成本，而**手錶上跑不跑得動還沒驗過**（實機部署卡住）。
    private static func makeKeyLight(arena: Arena) -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = 900
        light.castsShadow = true
        light.shadowMode = .forward
        light.shadowColor = UIColor(white: 0, alpha: 0.75)
        light.shadowRadius = 4
        light.shadowSampleCount = 8
        light.shadowMapSize = CGSize(width: 512, height: 512)
        // 平行光的影子範圍要自己給，預設值只蓋得到原點附近一小塊。
        light.orthographicScale = CGFloat(arena.halfDepth * 2.2)
        light.zNear = 1
        light.zFar = CGFloat(arena.ceilingY * 6)

        let node = SCNNode()
        node.light = light
        node.position = SCNVector3(-arena.halfWidth * 1.2, arena.ceilingY * 2.2, -arena.halfDepth * 1.2)
        node.look(at: SCNVector3(0, 0, 0))
        return node
    }

    private static func makeFillLight() -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 450          // 太低的話背向主光的面會全黑，字看不見

        let node = SCNNode()
        node.light = light
        return node
    }
}
