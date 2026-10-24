import ARKit
import AVFoundation
import SceneKit
import UIKit

/// Finds a horizontal surface, drops a glowing pumpkin box on it, and opens it on tap.
final class Tr3kPumpkinARViewController: UIViewController, ARSCNViewDelegate {
    var tier = "common"
    var prize = ""
    var onFinish: ((Bool, String) -> Void)?

    private let sceneView = ARSCNView(frame: .zero)
    private let hint = UILabel()
    private let actionButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let box = SCNNode()
    private let lid = SCNNode()
    private let lidHinge = SCNNode()
    private var prizeNode = SCNNode()
    private let glow = SCNLight()
    private var placed = false
    private var opened = false
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene = SCNScene()
        view.addSubview(sceneView)
        buildBox()
        layoutChrome()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARWorldTrackingConfiguration.isSupported else {
            finish(opened: false, reason: "unsupported")
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            finish(opened: false, reason: "camera_denied")
            return
        }
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    private func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        sceneView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        // If no surface shows up, float the box in front of the camera so the reveal still works.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.placeInFrontIfNeeded()
        }
    }

    // MARK: Placement

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { return }
        DispatchQueue.main.async {
            guard !self.placed else { return }
            self.placed = true
            let transform = simd_mul(plane.transform, simd_float4x4(translation: plane.center))
            self.drop(at: transform)
        }
    }

    private func placeInFrontIfNeeded() {
        guard !placed, !finished, let frame = sceneView.session.currentFrame else { return }
        placed = true
        let forward = simd_float4x4(translation: SIMD3<Float>(0, -0.25, -0.7))
        var transform = simd_mul(frame.camera.transform, forward)
        // Keep the box upright.
        let pos = transform.columns.3
        transform = simd_float4x4(translation: SIMD3<Float>(pos.x, pos.y, pos.z))
        drop(at: transform)
    }

    private func drop(at transform: simd_float4x4) {
        box.simdTransform = transform
        box.simdPosition.y += 0.3
        box.opacity = 0
        sceneView.scene.rootNode.addChildNode(box)
        box.runAction(.group([
            .fadeIn(duration: 0.3),
            .move(by: SCNVector3(0, -0.3, 0), duration: 0.45)
        ]))
        box.runAction(.repeatForever(.sequence([
            .customAction(duration: 1.2) { [weak self] _, t in self?.glow.intensity = 400 + 500 * sin(.pi * t / 1.2) }
        ])), forKey: "pulse")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        hint.text = "Tap the pumpkin box"
        actionButton.setTitle("Open it", for: .normal)
        actionButton.isEnabled = true
    }

    // MARK: Interaction

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard placed, !opened else { return }
        let hits = sceneView.hitTest(gesture.location(in: sceneView), options: nil)
        if hits.contains(where: { isPart(of: box, $0.node) }) { openBox() }
    }

    private func isPart(of root: SCNNode, _ node: SCNNode) -> Bool {
        var cur: SCNNode? = node
        while let n = cur { if n === root { return true }; cur = n.parent }
        return false
    }

    @objc private func primaryTapped() {
        if opened { finish(opened: true, reason: "opened") } else if placed { openBox() }
    }

    @objc private func closeTapped() {
        finish(opened: opened, reason: opened ? "opened" : "closed")
    }

    private func openBox() {
        guard !opened else { return }
        opened = true
        box.removeAction(forKey: "pulse")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        glow.intensity = 1800
        lidHinge.runAction(.group([
            .rotateBy(x: -.pi * 0.6, y: 0, z: 0, duration: 0.5),
            .move(by: SCNVector3(0, 0.03, 0), duration: 0.5)
        ]))
        let burst = SCNParticleSystem()
        burst.birthRate = 900
        burst.emissionDuration = 0.15
        burst.loops = false
        burst.particleLifeSpan = 0.9
        burst.particleSize = 0.006
        burst.spreadingAngle = 40
        burst.emittingDirection = SCNVector3(0, 1, 0)
        burst.particleVelocity = 0.5
        burst.particleVelocityVariation = 0.3
        burst.acceleration = SCNVector3(0, -0.6, 0)
        burst.particleColor = tierColor.withAlphaComponent(0.95)
        burst.blendMode = .additive
        let emitter = SCNNode()
        emitter.position = SCNVector3(0, 0.1, 0)
        emitter.addParticleSystem(burst)
        box.addChildNode(emitter)
        prizeNode.runAction(.sequence([
            .wait(duration: 0.25),
            .group([.fadeIn(duration: 0.25), .scale(to: 1, duration: 0.6), .move(by: SCNVector3(0, 0.16, 0), duration: 0.6)]),
            .repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3))
        ]))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.glow.intensity = 700 }
        let label = prize.isEmpty ? tierLabel : "\(tierLabel): \(prize)"
        hint.text = label
        actionButton.setTitle("Collect", for: .normal)
    }

    private func finish(opened: Bool, reason: String) {
        guard !finished else { return }
        finished = true
        onFinish?(opened, reason)
    }

    // MARK: Model

    private var tierColor: UIColor {
        switch tier.lowercased() {
        case "rare": return UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1)
        case "epic": return UIColor(red: 0.62, green: 0.32, blue: 0.95, alpha: 1)
        case "legendary", "gold": return UIColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 1)
        case "mythic": return UIColor(red: 0.95, green: 0.2, blue: 0.45, alpha: 1)
        default: return UIColor(red: 0.95, green: 0.85, blue: 0.6, alpha: 1)
        }
    }

    private var tierLabel: String {
        let t = tier.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Treasure" : t.prefix(1).uppercased() + t.dropFirst().lowercased()
    }

    private func buildBox() {
        let size: CGFloat = 0.16
        let pumpkin = SCNMaterial()
        pumpkin.lightingModel = .physicallyBased
        pumpkin.diffuse.contents = UIColor(red: 0.96, green: 0.48, blue: 0.08, alpha: 1)
        pumpkin.emission.contents = UIColor(red: 0.55, green: 0.2, blue: 0.0, alpha: 1)
        pumpkin.roughness.contents = 0.5
        let rib = SCNMaterial()
        rib.lightingModel = .physicallyBased
        rib.diffuse.contents = UIColor(red: 0.78, green: 0.33, blue: 0.04, alpha: 1)
        rib.emission.contents = UIColor(red: 0.35, green: 0.12, blue: 0.0, alpha: 1)
        let stemMat = SCNMaterial()
        stemMat.diffuse.contents = UIColor(red: 0.25, green: 0.42, blue: 0.15, alpha: 1)
        let face = SCNMaterial()
        face.diffuse.contents = UIColor.black
        face.emission.contents = UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1)

        let baseHeight = size * 0.75
        let base = SCNNode(geometry: SCNBox(width: size, height: baseHeight, length: size, chamferRadius: 0.02))
        base.geometry?.materials = [pumpkin]
        base.position = SCNVector3(0, Float(baseHeight / 2), 0)
        box.addChildNode(base)

        // Vertical ribs so it reads as a pumpkin.
        for x in [-0.045, 0.0, 0.045] {
            for z in [Float(size / 2) + 0.001, -Float(size / 2) - 0.001] {
                let r = SCNNode(geometry: SCNBox(width: 0.012, height: baseHeight * 0.95, length: 0.004, chamferRadius: 0.002))
                r.geometry?.materials = [rib]
                r.position = SCNVector3(Float(x), Float(baseHeight / 2), z)
                box.addChildNode(r)
            }
        }
        // Jack-o'-lantern face that glows.
        let eyeL = SCNNode(geometry: SCNPyramid(width: 0.03, height: 0.025, length: 0.004))
        let eyeR = eyeL.clone()
        let mouth = SCNNode(geometry: SCNBox(width: 0.07, height: 0.015, length: 0.004, chamferRadius: 0.006))
        [eyeL, eyeR, mouth].forEach { $0.geometry?.materials = [face] }
        eyeL.position = SCNVector3(-0.035, Float(baseHeight) * 0.6, Float(size / 2) + 0.003)
        eyeR.position = SCNVector3(0.035, Float(baseHeight) * 0.6, Float(size / 2) + 0.003)
        mouth.position = SCNVector3(0, Float(baseHeight) * 0.3, Float(size / 2) + 0.003)
        box.addChildNode(eyeL); box.addChildNode(eyeR); box.addChildNode(mouth)

        // Lid hinges on the back edge.
        lidHinge.position = SCNVector3(0, Float(baseHeight), -Float(size / 2))
        box.addChildNode(lidHinge)
        lid.geometry = SCNBox(width: size * 1.04, height: 0.03, length: size * 1.04, chamferRadius: 0.012)
        lid.geometry?.materials = [rib]
        lid.position = SCNVector3(0, 0.015, Float(size / 2))
        lidHinge.addChildNode(lid)
        let stem = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.04))
        stem.geometry?.materials = [stemMat]
        stem.position = SCNVector3(0, 0.035, 0)
        lid.addChildNode(stem)

        glow.type = .omni
        glow.color = UIColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 1)
        glow.intensity = 600
        glow.attenuationEndDistance = 1.2
        let glowNode = SCNNode()
        glowNode.light = glow
        glowNode.position = SCNVector3(0, Float(baseHeight) + 0.05, 0)
        box.addChildNode(glowNode)

        prizeNode = makePrize()
        prizeNode.opacity = 0
        prizeNode.scale = SCNVector3(0.01, 0.01, 0.01)
        prizeNode.position = SCNVector3(0, Float(baseHeight) * 0.6, 0)
        box.addChildNode(prizeNode)
    }

    private func makePrize() -> SCNNode {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = tierColor
        mat.emission.contents = tierColor.withAlphaComponent(0.6)
        mat.metalness.contents = 0.8
        mat.roughness.contents = 0.25
        let gem = SCNNode(geometry: SCNSphere(radius: 0.03))
        gem.geometry?.materials = [mat]
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.045, pipeRadius: 0.004))
        ring.geometry?.materials = [mat]
        ring.eulerAngles.x = .pi / 2
        let node = SCNNode()
        node.addChildNode(gem)
        node.addChildNode(ring)
        return node
    }

    private func layoutChrome() {
        hint.text = "Point your camera at the floor or a table"
        hint.textColor = .white
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.font = .systemFont(ofSize: 20, weight: .semibold)
        hint.layer.shadowColor = UIColor.black.cgColor
        hint.layer.shadowOpacity = 0.8
        hint.layer.shadowRadius = 4
        hint.layer.shadowOffset = .zero
        actionButton.setTitle("Looking for a surface…", for: .normal)
        actionButton.isEnabled = false
        actionButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        actionButton.backgroundColor = UIColor(red: 0.96, green: 0.48, blue: 0.08, alpha: 1)
        actionButton.setTitleColor(UIColor(red: 0.08, green: 0.07, blue: 0.05, alpha: 1), for: .normal)
        actionButton.layer.cornerRadius = 28
        actionButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [hint, actionButton, closeButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            actionButton.heightAnchor.constraint(equalToConstant: 64),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }
}

private extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
    }
}
