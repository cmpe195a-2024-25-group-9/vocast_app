import SwiftUI
import AVFoundation
import Network

class AudioStreamer: ObservableObject {
    private let engine = AVAudioEngine()
    private var udpConnection: NWConnection?
    private let streamingQueue = DispatchQueue(label: "AudioStreamingQueue") // for throttling

    private let espIP = "10.0.1.2"
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
            try audioSession.setActive(true)
        } catch {
            print("AudioSession error: \(error)")
            return
        }
        
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        print("Input format: \(inputFormat)")
        setupUDP()
        
        // Use smaller buffer for more frequent updates
        let bufferSize: AVAudioFrameCount = 256
        
        // var packetCount = 0
        
        engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { buffer, _ in
            guard let udpConnection = self.udpConnection else { return }

            let frameLength = Int(buffer.frameLength)

            guard let floatChannelData = buffer.floatChannelData else { return }
            let monoChannel = floatChannelData[0]

            // We need to collect enough samples to make exactly 1024 bytes per packet
            var interleavedData = Data(capacity: 1024)

            for i in 0..<frameLength {
                let sample = monoChannel[i]
                let clampedSample = max(-1.0, min(1.0, sample))
                let int16Sample = Int16(clampedSample * 32767)

                interleavedData.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Data($0) })
                interleavedData.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Data($0) })

                // Once we have enough, send it
                if interleavedData.count >= 1024 {
                    let packet = interleavedData.prefix(1024)
                    interleavedData.removeFirst(1024)

                    self.streamingQueue.async {
                        udpConnection.send(content: packet, completion: .contentProcessed({ error in
                            if let error = error {
                                print("UDP send error: \(error)")
                            }
                        }))
                    }
                }
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
