import Capacitor
import UIKit
import WebKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = Tr3kBridgeViewController()
        window.makeKeyAndVisible()
        self.window = window

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}

/// Capacitor bridge that follows the window it is in.
///
/// The WKWebView is the view controller's view, so a fold or unfold changes
/// `view.bounds` directly. Layout uses that bounds, the size class, and the
/// safe area. It does not read the main screen or the device orientation.
final class Tr3kBridgeViewController: CAPBridgeViewController {
    private var surfaceScheduled = false
    private var lastSignature = ""
    private var hingePayload: [String: Any]?
    private var lastHingeStatus: String?
    private var hingeCoachPending = false
    #if TR3K_DUO_SDK
    private var hingeInteraction: UIHingeInteraction?
    #endif

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        installHingeIfAvailable()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([
                UITraitHorizontalSizeClass.self,
                UITraitVerticalSizeClass.self
            ]) { (controller: Self, _) in
                controller.scheduleSurface()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pinWebViewToContainer()
        scheduleSurface()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.scheduleSurface()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass
            || traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass else {
            return
        }
        scheduleSurface()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        scheduleSurface()
    }

    /// A future Capacitor that wraps the web view in another view still has to
    /// track this controller's bounds. When the web view is the root view,
    /// UIKit already sizes it with the window.
    private func pinWebViewToContainer() {
        guard let webView, webView !== view, webView.superview === view else { return }
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if webView.frame != view.bounds {
            webView.frame = view.bounds
        }
    }

    private func scheduleSurface() {
        guard !surfaceScheduled else { return }
        surfaceScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.surfaceScheduled = false
            self.publishSurface()
        }
    }

    private func publishSurface() {
        guard let webView = (view as? WKWebView) ?? self.webView else { return }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let wide = traitCollection.horizontalSizeClass == .regular
        let safe = view.safeAreaInsets
        let scale = view.window?.windowScene?.screen.scale ?? 1
        let vbar = verticalBarEdgeLabel()
        let hingeStatus = hingePayload?["status"] as? String ?? ""
        let coach = hingeCoachPending
        let signature = [
            wide ? "1" : "0",
            String(Int(bounds.width.rounded())),
            String(Int(bounds.height.rounded())),
            String(Int(safe.top.rounded())),
            String(Int(safe.left.rounded())),
            String(Int(safe.bottom.rounded())),
            String(Int(safe.right.rounded())),
            String(format: "%.2f", scale),
            vbar,
            hingeStatus
        ].joined(separator: "|")
        guard signature != lastSignature || coach else { return }
        lastSignature = signature
        hingeCoachPending = false

        var payload: [String: Any] = [
            "wide": wide,
            "width": Double(bounds.width),
            "height": Double(bounds.height),
            "scale": Double(scale),
            "safe": [
                "top": Double(safe.top),
                "left": Double(safe.left),
                "bottom": Double(safe.bottom),
                "right": Double(safe.right)
            ],
            "vbar": vbar,
            "coach": coach
        ]
        if let hingePayload {
            payload["hinge"] = hingePayload
        } else {
            payload["hinge"] = NSNull()
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.__tr3kApplySurface && window.__tr3kApplySurface(\(json))", completionHandler: nil)
    }

    private func verticalBarEdgeLabel() -> String {
        #if TR3K_DUO_SDK
        if #available(iOS 27.1, *) {
            switch traitCollection.verticalBarEdge {
            case .leading:
                return "leading"
            case .trailing:
                return "trailing"
            case .unspecified:
                return "none"
            @unknown default:
                return "none"
            }
        }
        #endif
        return "none"
    }

    private func noteHinge(_ payload: [String: Any]?) {
        let status = payload?["status"] as? String
        if status == "partiallyOpen", lastHingeStatus != "partiallyOpen" {
            hingeCoachPending = true
        }
        lastHingeStatus = status
        hingePayload = payload
        lastSignature = ""
        scheduleSurface()
    }

    #if TR3K_DUO_SDK
    private func installHingeIfAvailable() {
        guard hingeInteraction == nil else { return }
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                guard let hinge = update.hinge else {
                    self.noteHinge(nil)
                    return
                }
                self.noteHinge([
                    "status": Self.hingeStatusName(hinge.status),
                    "angle": Double(hinge.angle)
                ])
            }
            view.addInteraction(interaction)
            hingeInteraction = interaction
        }
    }

    private static func hingeStatusName(_ status: UIHinge.Status) -> String {
        switch status {
        case .closed:
            return "closed"
        case .partiallyOpen:
            return "partiallyOpen"
        case .fullyOpen:
            return "fullyOpen"
        @unknown default:
            return "unknown"
        }
    }
    #else
    private func installHingeIfAvailable() {}
    #endif
}
