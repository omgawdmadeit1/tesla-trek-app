import Capacitor
import ARKit

@objc(Tr3kARPlugin)
public class Tr3kARPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "Tr3kARPlugin"
    public let jsName = "Tr3kAR"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise)
    ]

    @objc func isAvailable(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(["available": ARWorldTrackingConfiguration.isSupported])
        }
    }

    @objc func open(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let presenter = self.bridge?.viewController else {
                call.reject("The app view is not ready.")
                return
            }
            let view = Tr3kARViewController()
            view.modalPresentationStyle = .fullScreen
            view.rewardName = call.getString("rewardName") ?? "Collectible"
            view.rarity = call.getString("rarity") ?? "rare"
            view.kind = call.getString("kind") ?? "keychain"
            view.onFinish = { cracked, reason in
                presenter.dismiss(animated: true) {
                    call.resolve(["cracked": cracked, "reason": reason])
                }
            }
            presenter.present(view, animated: true)
        }
    }
}
