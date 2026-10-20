import ARKit
import AVFoundation
import SceneKit
import UIKit

final class Tr3kARViewController: UIViewController, ARSCNViewDelegate {
    var rewardName = "Collectible"
    var rarity = "rare"
    var kind = "keychain"
    var onFinish: ((Bool, String) -> Void)?

    private let sceneView = ARSCNView(frame: .zero)
    private let hint = UILabel()
    private let actionButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let cookie = SCNNode()
    private var shells: [SCNNode] = []
    private var shards: [SCNNode] = []
    private var rewardNode = SCNNode()
    private var burst = SCNParticleSystem()
    private var lamp = SCNLight()
    private var placed = false
    private var didCrack = false
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
        sceneView.scene = SCNScene()
        view.addSubview(sceneView)
        buildCookie()
        layoutChrome()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARWorldTrackingConfiguration.isSupported else {
            finish(cracked: false, reason: "unsupported")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.startSession()
                    } else {
                        self.finish(cracked: false, reason: "camera_denied")
                    }
                }
            }
        default:
            finish(cracked: false, reason: "camera_denied")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard !placed, sceneView.session.currentFrame != nil else { return }
        guard let frame = sceneView.session.currentFrame else { return }
        placed = true
        var forward = matrix_identity_float4x4
        forward.columns.3.z = -0.65
        let transform = simd_mul(frame.camera.transform, forward)
        DispatchQueue.main.async {
            self.cookie.simdTransform = transform
            self.sceneView.scene.rootNode.addChildNode(self.cookie)
        }
    }

    @objc private func primaryTapped() {
        if didCrack {
            finish(cracked: true, reason: "cracked")
        } else {
            crack()
        }
    }

    @objc private func closeTapped() {
        finish(cracked: didCrack, reason: didCrack ? "cracked" : "closed")
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !didCrack else { return }
        let point = gesture.location(in: sceneView)
        let hits = sceneView.hitTest(point, options: nil)
        if hits.contains(where: { hit in
            hit.node === self.cookie || hit.node.parent === self.cookie || self.shells.contains(where: { $0 === hit.node })
        }) {
            crack()
        }
    }

    private func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        sceneView.session.run(config)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tap)
    }

    private func buildCookie() {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.89, green: 0.69, blue: 0.35, alpha: 1)
        material.roughness.contents = 0.55
        let sphere = SCNSphere(radius: 0.065)
        sphere.materials = [material]
        for index in 0..<2 {
            let shell = SCNNode(geometry: sphere)
            shell.scale = SCNVector3(1.15, 0.42, 0.95)
            shell.position = SCNVector3(index == 0 ? -0.01 : 0.01, index == 0 ? 0.005 : -0.005, 0)
            if index == 1 { shell.eulerAngles.z = .pi }
            shell.name = "shell"
            shells.append(shell)
            cookie.addChildNode(shell)
        }
        for _ in 0..<6 {
            let box = SCNBox(width: 0.014, height: 0.008, length: 0.005, chamferRadius: 0.001)
            box.materials = [material]
            let shard = SCNNode(geometry: box)
            shard.isHidden = true
            shards.append(shard)
            cookie.addChildNode(shard)
        }
        rewardNode = makeReward()
        rewardNode.opacity = 0
        rewardNode.scale = SCNVector3(0.01, 0.01, 0.01)
        cookie.addChildNode(rewardNode)

        burst.birthRate = 0
        burst.particleLifeSpan = 0.7
        burst.particleSize = 0.008
        burst.spreadingAngle = 55
        burst.particleVelocity = 0.4
        burst.particleVelocityVariation = 0.25
        burst.particleColor = UIColor(white: 1, alpha: 0.95)
        burst.emitterShape = SCNSphere(radius: 0.01)
        burst.loops = false
        burst.acceleration = SCNVector3(0, -0.5, 0)
        let emitter = SCNNode()
        emitter.addParticleSystem(burst)
        cookie.addChildNode(emitter)

        lamp.type = .omni
        lamp.intensity = 0
        lamp.color = UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)
        let lampNode = SCNNode()
        lampNode.light = lamp
        cookie.addChildNode(lampNode)
    }

    private func makeReward() -> SCNNode {
        let node = SCNNode()
        let material = SCNMaterial()
        material.diffuse.contents = rarityUIColor(rarity)
        material.metalness.contents = kind == "keychain" ? 0.75 : 0.25
        material.roughness.contents = 0.35
        switch kind {
        case "keychain":
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.035, pipeRadius: 0.006))
            let charm = SCNNode(geometry: SCNSphere(radius: 0.016))
            charm.position = SCNVector3(0, -0.045, 0)
            ring.geometry?.materials = [material]
            charm.geometry?.materials = [material]
            node.addChildNode(ring)
            node.addChildNode(charm)
        case "skin":
            let slab = SCNNode(geometry: SCNBox(width: 0.08, height: 0.05, length: 0.008, chamferRadius: 0.004))
            slab.geometry?.materials = [material]
            node.addChildNode(slab)
        default:
            let ball = SCNNode(geometry: SCNSphere(radius: 0.03))
            ball.geometry?.materials = [material]
            node.addChildNode(ball)
        }
        return node
    }

    private func crack() {
        guard !didCrack else { return }
        didCrack = true
        hint.text = "\(rarityLabel(rarity)) \(rewardName)"
        actionButton.setTitle("Keep it", for: .normal)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        lamp.intensity = 1400
        burst.birthRate = 700
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.burst.birthRate = 0
            self.lamp.intensity = 120
        }
        if shells.count == 2 {
            shells[0].runAction(SCNAction.group([
                SCNAction.moveBy(x: -0.09, y: 0.03, z: 0.02, duration: 0.45),
                SCNAction.rotateBy(x: 0.5, y: 0.2, z: 0.8, duration: 0.45)
            ]))
            shells[1].runAction(SCNAction.group([
                SCNAction.moveBy(x: 0.09, y: 0.02, z: -0.02, duration: 0.45),
                SCNAction.rotateBy(x: -0.4, y: -0.3, z: -0.7, duration: 0.45)
            ]))
        }
        for (index, shard) in shards.enumerated() {
            shard.isHidden = false
            let angle = Float(index) / Float(shards.count) * Float.pi * 2
            shard.runAction(SCNAction.moveBy(
                x: CGFloat(cos(angle)) * 0.08,
                y: 0.04,
                z: CGFloat(sin(angle)) * 0.08,
                duration: 0.4
            ))
        }
        rewardNode.runAction(SCNAction.sequence([
            SCNAction.wait(duration: 0.2),
            SCNAction.group([
                SCNAction.fadeIn(duration: 0.25),
                SCNAction.scale(to: 1, duration: 0.7),
                SCNAction.moveBy(x: 0, y: 0.12, z: 0, duration: 0.7)
            ]),
            SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3.2))
        ]))
    }

    private func finish(cracked: Bool, reason: String) {
        guard !finished else { return }
        finished = true
        onFinish?(cracked, reason)
    }

    private func layoutChrome() {
        hint.text = "Tap the cookie"
        hint.textColor = .white
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.font = .systemFont(ofSize: 22, weight: .semibold)
        actionButton.setTitle("Tap the cookie", for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        actionButton.backgroundColor = UIColor(red: 0.89, green: 0.65, blue: 0.23, alpha: 1)
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
            actionButton.heightAnchor.constraint(equalToConstant: 72),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }
}

private func rarityLabel(_ rarity: String) -> String {
    switch rarity {
    case "common":
        return "Common"
    case "rare":
        return "Rare"
    case "epic":
        return "Epic"
    case "legendary":
        return "Legendary"
    default:
        return "Collectible"
    }
}

private func rarityUIColor(_ rarity: String) -> UIColor {
    switch rarity {
    case "common":
        return UIColor(red: 0.77, green: 0.75, blue: 0.71, alpha: 1)
    case "rare":
        return UIColor(red: 0.18, green: 0.44, blue: 0.75, alpha: 1)
    case "epic":
        return UIColor(red: 0.79, green: 0.54, blue: 0.10, alpha: 1)
    case "legendary":
        return UIColor(red: 0.89, green: 0.36, blue: 0.16, alpha: 1)
    default:
        return UIColor(red: 0.89, green: 0.65, blue: 0.23, alpha: 1)
    }
}
