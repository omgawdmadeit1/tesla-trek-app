import Capacitor

@objc(Tr3kARPlugin)
public class Tr3kARPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "Tr3kARPlugin"
    public let jsName = "Tr3kAR"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openSettings", returnType: CAPPluginReturnPromise)
    ]

    @objc func isAvailable(_ call: CAPPluginCall) {
        Tr3kARAccess.check(subject: "fortune cookie", prompt: false) { payload in
            var fields = Tr3kARAccess.fields(payload)
            fields["available"] = (fields["supported"] as? Bool) == true
            call.resolve(fields)
        }
    }

    @objc func openSettings(_ call: CAPPluginCall) {
        Tr3kARAccess.openSettings(call)
    }

    @objc func open(_ call: CAPPluginCall) {
        let rewardName = call.getString("rewardName") ?? "Collectible"
        let rarity = call.getString("rarity") ?? "rare"
        let kind = call.getString("kind") ?? "keychain"
        DispatchQueue.main.async {
            guard let presenter = self.bridge?.viewController else {
                call.reject("The app view is not ready.")
                return
            }
            Tr3kARAccess.check(subject: "fortune cookie", prompt: true) { decision in
                let proceed = decision["proceed"] as? Bool ?? false
                guard proceed else {
                    var payload = Tr3kARAccess.fields(decision)
                    payload["cracked"] = false
                    call.resolve(payload)
                    return
                }
                let view = Tr3kARViewController()
                view.modalPresentationStyle = .fullScreen
                view.rewardName = rewardName
                view.rarity = rarity
                view.kind = kind
                view.onFinish = { cracked, reason in
                    presenter.dismiss(animated: true) {
                        var payload = Tr3kARAccess.fields(decision)
                        payload["cracked"] = cracked
                        payload["reason"] = reason
                        call.resolve(payload)
                    }
                }
                presenter.present(view, animated: true)
            }
        }
    }
}
