import AVFoundation
import Foundation
import UIKit

/// Spoken turn-by-turn prompts for Tr3k.
///
/// `AVSpeechSynthesizer` keeps talking when the screen locks as long as the
/// audio session category is `.playback` and Info.plist `UIBackgroundModes`
/// contains `audio`. `.voicePrompt` is the navigation mode on paper, but iOS
/// treats it as a short foreground interruption and cuts it off in the
/// background. `.spokenAudio` with ducking is the mode that continues, and
/// other audio stays mixed in underneath at a lower volume.
///
/// The session stays active from the first armed prompt until `disarmSession`
/// (mute or end navigation). Deactivating between sentences lets iOS drop the
/// session, and the next `setActive` from the background then fails.
final class Tr3kSpeech: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Tr3kSpeech()

    /// Fired on the main queue with `speechStart` or `speechFinish`.
    var onEvent: ((String, [String: Any]) -> Void)?

    /// True while the playback session is held for spoken directions.
    private(set) var sessionArmed = false

    var isSpeaking: Bool {
        synth?.isSpeaking == true || pendingSpeaks > 0
    }

    struct Prompt {
        var id: String
        var text: String
        var rate: Float
        var pitch: Float
        var volume: Float
        var language: String
        var voice: String?
        var interrupt: Bool
        var muted: Bool
    }

    private var synth: AVSpeechSynthesizer?
    private var utterances: [ObjectIdentifier: String] = [:]
    private var speakToken = 0
    private var pendingSpeaks = 0
    private var speechTask: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        super.init()
    }

    /// Hold the playback session. Safe to call again. Call while Tr3k is still
    /// in the foreground (navigation start, or just before the screen locks).
    @discardableResult
    func armSession() -> Bool {
        do {
            try activateSession()
            sessionArmed = true
            return true
        } catch {
            return false
        }
    }

    /// Stop anything currently talking and release the audio session so other
    /// audio returns to full volume.
    func disarmSession() {
        speakToken += 1
        sessionArmed = false
        if let synth, synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        deactivateSession()
        endSpeechTask()
    }

    func speak(_ prompt: Prompt) -> [String: Any] {
        let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.muted {
            disarmSession()
            return ["spoken": false, "reason": "muted", "id": prompt.id, "stopped": true]
        }
        if text.isEmpty {
            return ["spoken": false, "reason": "empty", "id": prompt.id]
        }
        let limited = String(text.prefix(600))
        do {
            try activateSession()
        } catch {
            return [
                "spoken": false,
                "reason": "session",
                "id": prompt.id,
                "message": error.localizedDescription
            ]
        }
        sessionArmed = true

        let utter = AVSpeechUtterance(string: limited)
        utter.rate = clampRate(prompt.rate)
        utter.pitchMultiplier = min(max(prompt.pitch, 0.5), 2)
        utter.volume = min(max(prompt.volume, 0), 1)
        if let voice = voice(language: prompt.language, preferred: prompt.voice) {
            utter.voice = voice
        }
        utterances[ObjectIdentifier(utter)] = prompt.id

        let synth = synthesizer()
        if prompt.interrupt {
            speakToken += 1
        }
        let token = speakToken
        if prompt.interrupt && (synth.isSpeaking || pendingSpeaks > 0) {
            pendingSpeaks += 1
            if synth.isSpeaking {
                synth.stopSpeaking(at: .immediate)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.pendingSpeaks = max(0, self.pendingSpeaks - 1)
                guard token == self.speakToken else {
                    self.utterances.removeValue(forKey: ObjectIdentifier(utter))
                    return
                }
                self.synthesizer().speak(utter)
                self.beginSpeechTask()
            }
        } else {
            synth.speak(utter)
            beginSpeechTask()
        }
        return ["spoken": true, "id": prompt.id, "queued": true, "guidance": true]
    }

    func stop(immediate: Bool) -> [String: Any] {
        let was = synth?.isSpeaking == true || pendingSpeaks > 0
        if !immediate, let synth, synth.isSpeaking {
            // Leave the session up until the word actually ends. Deactivating
            // here would cut the word off.
            speakToken += 1
            synth.stopSpeaking(at: .word)
        } else {
            disarmSession()
        }
        return ["stopped": true, "speaking": was]
    }

    // MARK: AVSpeechSynthesizerDelegate

    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = utterances[ObjectIdentifier(utterance)] ?? ""
        emit("speechStart", ["id": id])
    }

    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = utterances.removeValue(forKey: ObjectIdentifier(utterance)) ?? ""
        emit("speechFinish", ["id": id, "reason": "finished"])
        if !synthesizer.isSpeaking {
            endSpeechTask()
        }
    }

    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = utterances.removeValue(forKey: ObjectIdentifier(utterance)) ?? ""
        emit("speechFinish", ["id": id, "reason": "cancelled"])
        if !synthesizer.isSpeaking && pendingSpeaks == 0 {
            endSpeechTask()
        }
    }

    // MARK: Private

    private func synthesizer() -> AVSpeechSynthesizer {
        if let synth { return synth }
        let created = AVSpeechSynthesizer()
        created.delegate = self
        synth = created
        return created
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        try session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func clampRate(_ rate: Float) -> Float {
        min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    private func voice(language: String, preferred: String?) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let preferred, !preferred.isEmpty {
            if let exact = voices.first(where: {
                $0.identifier == preferred || $0.name.caseInsensitiveCompare(preferred) == .orderedSame
            }) {
                return exact
            }
        }
        let lang = language.isEmpty ? "en-US" : language
        let prefix = lang.split(separator: "-").first.map(String.init) ?? lang
        let matching = voices.filter { $0.language == lang || $0.language.hasPrefix(prefix) }
        let ranked = matching.sorted { qualityRank($0) > qualityRank($1) }
        return ranked.first ?? AVSpeechSynthesisVoice(language: lang)
    }

    private func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        if #available(iOS 16.0, *) {
            if voice.quality == .premium { return 3 }
        }
        if voice.quality == .enhanced { return 2 }
        return 1
    }

    private func emit(_ name: String, _ data: [String: Any]) {
        let send: () -> Void = {
            self.onEvent?(name, data)
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.async(execute: send)
        }
    }

    private func beginSpeechTask() {
        guard speechTask == .invalid else { return }
        speechTask = UIApplication.shared.beginBackgroundTask(withName: "tr3k-speech") { [weak self] in
            guard let self else { return }
            let task = self.speechTask
            self.speechTask = .invalid
            if task != .invalid {
                UIApplication.shared.endBackgroundTask(task)
            }
        }
    }

    private func endSpeechTask() {
        guard speechTask != .invalid else { return }
        let task = speechTask
        speechTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}
