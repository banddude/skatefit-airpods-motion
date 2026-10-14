import SceneKit
import SwiftUI
import simd

/// A real-time 3D visualization built entirely from native geometry,
/// driven by the board's calibrated pitch, roll, and relative yaw.
struct Board3DView: UIViewRepresentable {
    let orientation: BoardOrientation?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isPlaying = true
        view.preferredFramesPerSecond = 30
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.scene = Self.makeScene()
        view.accessibilityLabel = "3D skateboard preview showing relative pitch, roll and yaw"
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let root = view.scene?.rootNode.childNode(
            withName: "boardRoot", recursively: false) else { return }

        let pitch = Float((orientation?.pitchDegrees ?? 0) * .pi / 180)
        let roll = Float((orientation?.rollDegrees ?? 0) * .pi / 180)
        let yaw = Float((orientation?.yawDegrees ?? 0) * .pi / 180)

        // +pitch tips the nose along +X up; roll flips around board length;
        // yaw rotates in the horizontal plane. Relative yaw may drift.
        let qPitch = simd_quatf(angle: pitch, axis: SIMD3<Float>(0, 0, 1))
        let qRoll = simd_quatf(angle: roll, axis: SIMD3<Float>(1, 0, 0))
        let qYaw = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        root.simdOrientation = qYaw * qPitch * qRoll
    }

    private static func material(_ color: UIColor, roughness: CGFloat = 0.8) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .physicallyBased
        m.roughness.contents = roughness
        m.isDoubleSided = true
        return m
    }

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let board = SCNNode()
        board.name = "boardRoot"
        scene.rootNode.addChildNode(board)

        let deckGeometry = SCNBox(
            width: 3.7, height: 0.13, length: 0.86, chamferRadius: 0.09)
        deckGeometry.materials = [material(.systemTeal)]
        let deck = SCNNode(geometry: deckGeometry)
        board.addChildNode(deck)

        let grip = SCNNode(geometry: SCNBox(
            width: 3.48, height: 0.012, length: 0.76, chamferRadius: 0.045))
        grip.geometry?.materials = [material(.darkGray)]
        grip.position = SCNVector3(0, 0.075, 0)
        board.addChildNode(grip)

        let axleMaterial = material(.systemGray2, roughness: 0.5)
        let wheelMaterial = material(.white, roughness: 0.8)
        let bearingMaterial = material(.darkGray)

        for along in [-1.13, 1.13] {
            let truck = SCNNode(geometry: SCNBox(
                width: 0.20, height: 0.20, length: 1.15,
                chamferRadius: 0.03))
            truck.geometry?.materials = [axleMaterial]
            truck.position = SCNVector3(along, -0.16, 0)
            board.addChildNode(truck)
            for lateral in [-0.48, 0.48] {
                let wheel = SCNNode(geometry: SCNCylinder(
                    radius: 0.215, height: 0.13))
                wheel.geometry?.materials = [wheelMaterial]
                wheel.position = SCNVector3(along, -0.33, lateral)
                wheel.eulerAngles.x = .pi / 2
                board.addChildNode(wheel)

                let axle = SCNNode(geometry: SCNCylinder(
                    radius: 0.055, height: 0.14))
                axle.geometry?.materials = [bearingMaterial]
                axle.position = SCNVector3(along, -0.33, lateral)
                axle.eulerAngles.x = .pi / 2
                board.addChildNode(axle)
            }
        }

        let ground = SCNNode(geometry: SCNBox(
            width: 5.3, height: 0.025, length: 2.7, chamferRadius: 0))
        ground.geometry?.materials = [material(
            UIColor.systemGray4.withAlphaComponent(0.18))]
        ground.position = SCNVector3(0, -0.68, 0)
        scene.rootNode.addChildNode(ground)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 46
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 100
        camera.position = SCNVector3(4.7, 3.25, 7.4)
        camera.look(at: SCNVector3(0, -0.1, 0))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor.systemGray4
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 1600
        key.position = SCNVector3(-2, 5, 6)
        scene.rootNode.addChildNode(key)
        return scene
    }
}

struct Board3DCard: View {
    let orientation: BoardOrientation?
    let recording: Bool

    private func value(_ degrees: Double?) -> String {
        guard let degrees else { return "—" }
        return String(format: "%+.0f°", degrees)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("3D board motion")
                    .font(.headline)
                Spacer()
                if recording {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.teal)
                }
            }

            Board3DView(orientation: orientation)
                .frame(height: 185)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(false)

            HStack(spacing: 8) {
                axisMetric("Pitch", value(orientation?.pitchDegrees))
                axisMetric("Roll", value(orientation?.rollDegrees))
                axisMetric("Yaw", orientation?.headingAvailable == true
                           ? value(orientation?.yawDegrees) : "—")
            }
            Text(orientation?.headingAvailable == true
                 ? "Yaw is relative to the flat calibration pose. Heading can drift."
                 : "Calibrate flat, tail and nose to activate all three axes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(17)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 19))
    }

    private func axisMetric(_ name: String, _ reading: String) -> some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(reading)
                .font(.title3.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 11))
    }
}
