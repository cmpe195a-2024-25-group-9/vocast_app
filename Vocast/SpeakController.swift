import UIKit
import AVFoundation

class SpeakController: UIViewController {

    var audioEngine: AVAudioEngine!
    var inputNode: AVAudioInputNode!
    var isStreaming = false
    var websocket: URLSessionWebSocketTask?

    let toggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Unmute", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        toggleButton.addTarget(self, action: #selector(toggleMic), for: .touchUpInside)
        toggleButton.center = view.center
        toggleButton.frame = CGRect(x: 100, y: 300, width: 200, height: 60)
        view.addSubview(toggleButton)

        // requestMicPermission()
    }

    /* func requestMicPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                print("Microphone access denied")
            }
        }
    } */

    @objc func toggleMic() {
        if isStreaming {
            stopStreaming()
            toggleButton.setTitle("Unmute", for: .normal)
        } else {
            startStreaming()
            toggleButton.setTitle("Mute", for: .normal)
        }
    }

    func startStreaming() {
        isStreaming = true

        // Set up audio session first
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(44100) // Optional
            try session.setActive(true)
        } catch {
            print("Error setting up audio session: \(error)")
            return
        }

        // Then create engine
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode

        let inputFormat = inputNode.inputFormat(forBus: 0)
        print("Mic input format: \(inputFormat)")  // Should be stereo if available

        // We'll ask for stereo output, 48kHz
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: 48000,
                                          channels: 2,
                                          interleaved: false)! // Planar

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: buffer.frameCapacity) else { return }
            floatBuffer.frameLength = buffer.frameLength

            let converter = AVAudioConverter(from: inputFormat, to: desiredFormat)!
            var error: NSError?
            converter.convert(to: floatBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard let left = floatBuffer.floatChannelData?[0] else { return }
            let right = floatBuffer.format.channelCount > 1 ? floatBuffer.floatChannelData?[1] : left

            let frameCount = Int(floatBuffer.frameLength)
            var int16Data = [Int16](repeating: 0, count: frameCount * 2) // Stereo

            for i in 0..<frameCount {
                let leftSample = max(-1.0, min(1.0, left[i]))
                let rightSample = max(-1.0, min(1.0, right![i]))

                int16Data[i * 2] = Int16(leftSample * 32767)      // Left
                int16Data[i * 2 + 1] = Int16(rightSample * 32767) // Right
            }

            let rawData = Data(buffer: UnsafeBufferPointer(start: &int16Data, count: int16Data.count))
            self.sendData(rawData)
        }

        do {
            try audioEngine.start()
            connectWebSocket()
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }

    func stopStreaming() {
        isStreaming = false
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        websocket?.cancel()
    }

    func connectWebSocket() {
        guard let url = URL(string: "ws://10.0.0.13:81") else { return }
        let session = URLSession(configuration: .default)
        websocket = session.webSocketTask(with: url)
        websocket?.resume()

        // receiveMessages() // Optional, for keeping connection alive
    }

    func sendData(_ data: Data) {
        guard let ws = websocket else { return }
        ws.send(.data(data)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    /* func receiveMessages() {
        websocket?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
            case .success:
                break
            }
            self?.receiveMessages()
        }
    } */
}
