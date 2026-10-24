import AuthenticationServices
import UIKit

/// On-device Sign in with Apple session. Name and email are kept only when
/// Apple sends them (the first grant). Later grants return the user id alone.
enum Tr3kAppleSession {
    private static let storageKey = "tr3k.apple.session.v1"

    static func payload() -> [String: Any] {
        guard let stored = load(), let user = nonempty(stored["user"]) else {
            return ["signedIn": false]
        }
        var payload: [String: Any] = ["signedIn": true, "user": user]
        for key in ["email", "fullName", "givenName", "familyName"] {
            if let value = nonempty(stored[key]) {
                payload[key] = value
            }
        }
        return payload
    }

    static func store(user: String, email: String?, givenName: String?, familyName: String?) -> [String: Any] {
        let previous = load()
        let sameUser = nonempty(previous?["user"]) == user
        let given = nonempty(givenName) ?? (sameUser ? nonempty(previous?["givenName"]) : nil)
        let family = nonempty(familyName) ?? (sameUser ? nonempty(previous?["familyName"]) : nil)
        let mail = nonempty(email) ?? (sameUser ? nonempty(previous?["email"]) : nil)
        let parts = [given, family].compactMap { $0 }
        var record: [String: String] = ["user": user]
        if let mail { record["email"] = mail }
        if let given { record["givenName"] = given }
        if let family { record["familyName"] = family }
        if !parts.isEmpty { record["fullName"] = parts.joined(separator: " ") }
        UserDefaults.standard.set(record, forKey: storageKey)
        return payload()
    }

    static func clear() -> [String: Any] {
        UserDefaults.standard.removeObject(forKey: storageKey)
        return ["signedIn": false]
    }

    private static func load() -> [String: String]? {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String]
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class Tr3kAppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let presenter: UIViewController
    private let completion: ([String: Any]) -> Void
    private var controller: ASAuthorizationController?
    private var didFinish = false

    init(presenter: UIViewController, completion: @escaping ([String: Any]) -> Void) {
        self.presenter = presenter
        self.completion = completion
    }

    func start() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = presenter.view.window { return window }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        if let window = scenes.first?.windows.first { return window }
        return ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(failed: true)
            return
        }
        let user = credential.user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else {
            finish(failed: true)
            return
        }
        let payload = Tr3kAppleSession.store(
            user: user,
            email: credential.email,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName
        )
        finish(payload)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        finish(failed: !canceled, canceled: canceled)
    }

    private func finish(failed: Bool, canceled: Bool = false) {
        var payload = Tr3kAppleSession.payload()
        if canceled {
            payload["reason"] = "canceled"
        } else if failed {
            payload["reason"] = "failed"
            payload["message"] = "Sign in with Apple did not finish."
        }
        finish(payload)
    }

    private func finish(_ payload: [String: Any]) {
        guard !didFinish else { return }
        didFinish = true
        controller = nil
        DispatchQueue.main.async {
            self.completion(payload)
        }
    }
}
