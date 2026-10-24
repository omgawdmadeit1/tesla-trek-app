import ARKit
import AVFoundation
import Capacitor
import UIKit

/// Camera and ARWorldTracking gate used before any AR modal is presented.
enum Tr3kARAccess {
    static func check(subject: String, prompt: Bool, completion: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            guard ARWorldTrackingConfiguration.isSupported else {
                completion(result(
                    proceed: false,
                    reason: "unsupported",
                    camera: "unavailable",
                    supported: false,
                    canOpenSettings: false,
                    message: "This iPhone can't show Tr3k AR collectibles, including the fortune cookie and the glowing pumpkin."
                ))
                return
            }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                completion(ready())
            case .notDetermined:
                guard prompt else {
                    completion(result(
                        proceed: false,
                        reason: "camera_prompt",
                        camera: "notDetermined",
                        supported: true,
                        canOpenSettings: false,
                        message: "Tr3k will ask to use the camera for the \(subject)."
                    ))
                    return
                }
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        completion(granted ? ready() : denied(subject: subject, status: .denied))
                    }
                }
            case .denied:
                completion(denied(subject: subject, status: .denied))
            case .restricted:
                completion(denied(subject: subject, status: .restricted))
            @unknown default:
                completion(denied(subject: subject, status: .denied))
            }
        }
    }

    static func fields(_ payload: [String: Any]) -> [String: Any] {
        var copy = payload
        copy.removeValue(forKey: "proceed")
        return copy
    }

    static func openSettings(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                call.resolve(["opened": false])
                return
            }
            UIApplication.shared.open(url, options: [:]) { opened in
                call.resolve(["opened": opened])
            }
        }
    }

    private static func ready() -> [String: Any] {
        [
            "proceed": true,
            "supported": true,
            "camera": "authorized",
            "canOpenSettings": false
        ]
    }

    private static func denied(subject: String, status: AVAuthorizationStatus) -> [String: Any] {
        if status == .restricted {
            return result(
                proceed: false,
                reason: "camera_restricted",
                camera: "restricted",
                supported: true,
                canOpenSettings: true,
                message: "Camera access is restricted on this iPhone, so Tr3k can't place the \(subject). You can check Settings."
            )
        }
        return result(
            proceed: false,
            reason: "camera_denied",
            camera: "denied",
            supported: true,
            canOpenSettings: true,
            message: "Tr3k needs the camera to place the \(subject) in front of you. Camera access is off. You can turn it on in Settings."
        )
    }

    private static func result(
        proceed: Bool,
        reason: String,
        camera: String,
        supported: Bool,
        canOpenSettings: Bool,
        message: String
    ) -> [String: Any] {
        [
            "proceed": proceed,
            "reason": reason,
            "camera": camera,
            "supported": supported,
            "canOpenSettings": canOpenSettings,
            "message": message
        ]
    }
}
