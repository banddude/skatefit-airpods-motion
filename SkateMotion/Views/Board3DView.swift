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

        if let q = orientation?.relativeQuaternion?.unit {
            // Relative quaternion uses the calibrated board basis,
            // retaining full rotation even across an upside-down flip.
            root.simdOrientation = simd_quatf(real: Float(q.w),
                imag: SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z)))
        } else {
            root.simdOrientation = simd_quatf(real: 1, imag: SIMD3(0, 0, 0))
        }
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

        let axleMaterial = material(BoardScenePalette.axle, roughness: 0.5)
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
            BoardScenePalette.ground.withAlphaComponent(0.18))]
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
        ambient.light?.color = BoardScenePalette.ground
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

#if !os(tvOS)
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
            HStack {
                Label(orientation?.deckFace ?? "Awaiting calibration",
                      systemImage: orientation?.isInverted == true
                        ? "arrow.down.circle.fill" : "rotate.3d")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(orientation?.isInverted == true ? .orange : .teal)
                Spacer()
            }
            Text(orientation?.fullAttitudeAvailable == true
                 ? "All-axis rotation, including flips. Yaw is relative and can drift. Translation and height are unknown."
                 : "Gravity-only tilt estimate: twist direction and yaw are not fully observable. Translation and height are unknown.")
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

#endif

private enum BoardScenePalette {
    static var axle: UIColor {
        #if os(tvOS)
        UIColor(white: 0.68, alpha: 1)
        #else
        .systemGray2
        #endif
    }
    static var ground: UIColor {
        #if os(tvOS)
        UIColor(white: 0.78, alpha: 1)
        #else
        .systemGray4
        #endif
    }
}
