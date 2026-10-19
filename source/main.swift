import AppKit
import AVFoundation
import Speech
import Carbon.HIToolbox

// Toggle dictation with Ctrl+Option+Space. Transcribes on-device with Apple's SpeechTranscriber, pastes at cursor.

final class Dictator: @unchecked Sendable {
    var engine = AVAudioEngine()
    var analyzer: SpeechAnalyzer?
    var transcriber: SpeechTranscriber?
    var builder: AsyncStream<AnalyzerInput>.Continuation?
    var resultsTask: Task<String, Never>?
    var recording = false
    var setStatus: (String) -> Void = { _ in }

    func prepare() async {
        let t = SpeechTranscriber(locale: Locale(identifier: "en-US"), transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                setStatus("⏬")
                try await req.downloadAndInstall()
            }
            setStatus("🎙")
        } catch { setStatus("⚠️"); NSLog("asset error: \(error)") }
    }

    func start() async {
        guard !recording else { return }
        let t = SpeechTranscriber(locale: Locale(identifier: "en-US"), transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        transcriber = t
        let a = SpeechAnalyzer(modules: [t])
        analyzer = a
        let (seq, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
        builder = cont
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else { setStatus("⚠️"); return }
        resultsTask = Task {
            var text = ""
            do { for try await r in t.results where r.isFinal { text += String(r.text.characters) + " " } } catch { NSLog("results: \(error)") }
            return text.trimmingCharacters(in: .whitespaces)
        }
        do { try await a.start(inputSequence: seq) } catch { setStatus("⚠️"); NSLog("start: \(error)"); return }
        engine = AVAudioEngine()
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        guard let conv = AVAudioConverter(from: inFmt, to: fmt) else { setStatus("⚠️"); return }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { buf, _ in
            let ratio = fmt.sampleRate / inFmt.sampleRate
            guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(buf.frameLength) * ratio) + 64) else { return }
            var fed = false
            conv.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buf
            }
            cont.yield(AnalyzerInput(buffer: out))
        }
        do { try engine.start() } catch { setStatus("⚠️"); NSLog("engine: \(error)"); return }
        recording = true
        setStatus("🔴")
    }

    func stop() async {
        guard recording else { return }
        recording = false
        setStatus("⏳")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        builder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        let text = await resultsTask?.value ?? ""
        setStatus("🎙")
        dlog("transcript=[\(text)] trusted=\(AXIsProcessTrusted())")
        if !text.isEmpty { await MainActor.run { paste(text) } }
    }
}

func dlog(_ m: String) {
    let l = "\(Date()) \(m)\n"
    let u = URL(fileURLWithPath: NSHomeDirectory() + "/dictate.log")
    if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(l.data(using: .utf8)!); try? h.close() } else { try? l.write(to: u, atomically: true, encoding: .utf8) }
}

func paste(_ s: String) {
    let pb = NSPasteboard.general
    let old = pb.string(forType: .string)
    pb.clearContents(); pb.setString(s, forType: .string)
    let src = CGEventSource(stateID: .combinedSessionState)
    let d = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
    let u = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    d?.flags = .maskCommand; u?.flags = .maskCommand
    d?.post(tap: .cghidEventTap); u?.post(tap: .cghidEventTap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        _ = old
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let d = Dictator()
    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.title = "🎙"
        let m = NSMenu(); m.addItem(withTitle: "Hold Fn to talk (or toggle ⌃⌥Space)", action: nil, keyEquivalent: "")
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
        d.setStatus = { [weak self] s in DispatchQueue.main.async { self?.item.button?.title = s } }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        Task { await d.prepare() }
        // Hold Fn (keycode 63) to talk, release to paste - same as Wispr push-to-talk.
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            guard let self, e.keyCode == 63 else { return }
            let down = e.modifierFlags.contains(.function)
            Task { if down { await self.d.start() } else { await self.d.stop() } }
        }
        var ref: EventHotKeyRef?
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ud in
            let me = Unmanaged<AppDelegate>.fromOpaque(ud!).takeUnretainedValue()
            Task { if me.d.recording { await me.d.stop() } else { await me.d.start() } }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x44494354), id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}
let app = NSApplication.shared
let del = AppDelegate()
app.delegate = del
app.setActivationPolicy(.accessory)
app.run()
