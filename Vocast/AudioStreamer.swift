import SwiftUI
import AVFoundation
import Network

class AudioStreamer: ObservableObject {
    private let engine = AVAudioEngine()
    private var udpConnection: NWConnection?
    private let streamingQueue = DispatchQueue(label: "AudioStreamingQueue") // for throttling

    private let espIP = "10.0.0.12"
    private let espPort: NWEndpoint.Port = 12345

    @Published var isStreaming = false

    func startStreaming() {
        checkMicrophoneAccess { granted in
            if granted {
                print("Mic access granted")
                self.configureAndStart()
            } else {
                print("Mic access denied. Please enable in Settings.")
            }
        }
    }

    func stopStreaming() {
        guard isStreaming else { return }
        isStreaming = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        udpConnection?.cancel()
        udpConnection = nil
        print("Audio streaming stopped.")
    }

    // /*
    private func configureAndStart() {
        guard !isStreaming else { return }
        isStreaming = true

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setActive(true)
        } catch {
            print("AudioSession error: \(error)")
            return
        }

        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        print("Input format: \(inputFormat)")

        setupUDP()

        let bufferSize: AVAudioFrameCount = 256
        engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { buffer, _ in
            guard let udpConnection = self.udpConnection else { return }

            // Max frame limit
            let maxFrames = 256
            let actualFrameLength = Int(buffer.frameLength)
            let frameLength = min(actualFrameLength, maxFrames)
            print("Tapped buffer frameLength: \(actualFrameLength), using: \(frameLength)")

            // Get float32 channels
            let floatLeft = buffer.floatChannelData?[0]
            let floatRight = buffer.format.channelCount > 1 ? buffer.floatChannelData?[1] : nil

            // Prepare interleaved Int16 buffer
            var interleavedData = Data(capacity: frameLength * 4) // 2 channels * 2 bytes

            for i in 0..<frameLength {
                let l = floatLeft?[i] ?? 0
                let r = floatRight?[i] ?? l // fallback to mono

                let leftSample = Int16(max(-1.0, min(1.0, l)) * Float(Int16.max))
                let rightSample = Int16(max(-1.0, min(1.0, r)) * Float(Int16.max))

                interleavedData.append(contentsOf: withUnsafeBytes(of: leftSample.littleEndian) { Data($0) })
                interleavedData.append(contentsOf: withUnsafeBytes(of: rightSample.littleEndian) { Data($0) })
            }

            // Clamp to max 1024 bytes
            let maxPacketSize = 1024
            if interleavedData.count > maxPacketSize {
                print("Clamping packet from \(interleavedData.count) to \(maxPacketSize) bytes")
                interleavedData = interleavedData.prefix(maxPacketSize)
            }

            print("Sending \(interleavedData.count) bytes. First samples: \(interleavedData.prefix(8).map { String(format: "%02x", $0) })")

            self.streamingQueue.asyncAfter(deadline: .now()) {
                udpConnection.send(content: interleavedData, completion: .contentProcessed({ error in
                    if let error = error {
                        print("UDP send error: \(error)")
                    } else {
                        print("Audio packet sent to ESP.")
                    }
                }))
            }
        }

        do {
            try engine.start()
            print("Audio engine started.")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    // */

    private func setupUDP() {
        let host = NWEndpoint.Host(espIP)
        let port = espPort
        udpConnection = NWConnection(host: host, port: port, using: .udp)

        udpConnection?.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("UDP connection ready to \(host):\(port)")
            case .failed(let error):
                print("UDP connection failed: \(error)")
            default:
                break
            }
        }

        udpConnection?.start(queue: .global())
    }

    private func checkMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
}
