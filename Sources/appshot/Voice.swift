import AVFoundation
import Foundation

/// Spoken feedback. Uses ElevenLabs TTS when ELEVENLABS_API_KEY is set, otherwise macOS `say`.
/// The API key is read only from the environment and is never logged or written anywhere.
enum Voice {
    static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"   // ElevenLabs "Rachel"
    static let defaultModel = "eleven_multilingual_v2"

    private static var player: AVAudioPlayer?

    static var hasElevenLabsKey: Bool {
        guard let k = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] else { return false }
        return !k.isEmpty
    }

    static func speak(_ text: String, lang: String) async {
        if let data = await elevenLabs(text) {
            await play(data)
        } else {
            await say(text, lang: lang)
        }
    }

    static func announcement(app: String, chars: Int, text: String, lang: String, includeSummary: Bool) -> String {
        let zh = lang.hasPrefix("zh")
        var s = zh ? "已捕获 \(app)，共 \(chars) 个字。" : "Captured \(app), \(chars) characters."
        if includeSummary, let summary = summarize(text) {
            s += zh ? " 内容摘要：\(summary)" : " Summary: \(summary)"
        }
        return s
    }

    /// Cheap, local "summary": the first few non-trivial lines, whitespace-collapsed and length-capped.
    static func summarize(_ text: String, limit: Int = 280) -> String? {
        var out = ""
        for line in text.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.count < 4 { continue }
            out += (out.isEmpty ? "" : ". ") + l
            if out.count >= limit { break }
        }
        if out.isEmpty { return nil }
        return out.count > limit ? String(out.prefix(limit)) + "…" : out
    }

    // MARK: - ElevenLabs

    private static func elevenLabs(_ text: String) async -> Data? {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["ELEVENLABS_API_KEY"], !key.isEmpty else { return nil }
        var voice = env["ELEVENLABS_VOICE_ID"] ?? defaultVoiceID
        voice = String(voice.filter { $0.isLetter || $0.isNumber })   // path-safe
        if voice.isEmpty { voice = defaultVoiceID }
        let model = env["ELEVENLABS_MODEL_ID"] ?? defaultModel
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=mp3_44100_128") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "model_id": model])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else {
                log("ElevenLabs TTS failed (HTTP \(status)); falling back to `say`.")
                return nil
            }
            return data
        } catch {
            log("ElevenLabs TTS request failed; falling back to `say`.")
            return nil
        }
    }

    private static func play(_ data: Data) async {
        guard let p = try? AVAudioPlayer(data: data) else { return }
        player = p
        p.play()
        while p.isPlaying { try? await Task.sleep(nanoseconds: 100_000_000) }
    }

    // MARK: - Fallback

    private static func say(_ text: String, lang: String) async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        proc.arguments = lang.hasPrefix("zh") ? ["-v", "Tingting", text] : [text]
        do {
            try proc.run()
            while proc.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
        } catch {
            log("`say` failed.")
        }
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("[appshot] \(message)\n".utf8))
}
