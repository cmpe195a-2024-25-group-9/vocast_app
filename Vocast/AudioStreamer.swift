import SwiftUI
import AVFoundation
import Network

class AudioStreamer: ObservableObject {
    private let engine = AVAudioEngine()
    private var udpConnection: NWConnection?
    private let streamingQueue = DispatchQueue(label: "audio.streaming.queue") // for throttling

    private var espIP: String
    private let espPort: NWEndpoint.Port = 12345

    @Published var isStreaming = false

    init(espIP: String) {
        self.espIP = espIP
    }
    
    func updateIP(to newIP: String) {
        self.espIP = newIP
    }
    
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

        let chunkSize = 256
        let bytesPerPacket = chunkSize * 2 * 2  // 2 bytes * 2 channels

        var packetQueue: [Data] = []
        let queueLock = DispatchQueue(label: "packet.queue.lock")

        // Install tap on input node
        engine.inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(chunkSize), format: inputFormat) { buffer, _ in
            guard let floatChannelData = buffer.floatChannelData else { return }
            let mono = floatChannelData[0]
            let frameLength = Int(buffer.frameLength)

            let numChunks = frameLength / chunkSize
            queueLock.sync {
                for chunkIndex in 0..<numChunks {
                    var packet = Data(capacity: bytesPerPacket)
                    for i in 0..<chunkSize {
                        let sample = mono[chunkIndex * chunkSize + i]
                        let clamped = max(-1.0, min(1.0, sample))
                        let int16Sample = Int16(clamped * 32767)
                        // Stereo: duplicate sample
                        packet.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Data($0) })
                        packet.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Data($0) })
                    }
                    packetQueue.append(packet)
                }
            }
        }

        // Send one packet every ~5.33 ms (256 frames @ 48kHz)
        Timer.scheduledTimer(withTimeInterval: 0.00533, repeats: true) { _ in
            queueLock.sync {
                guard !packetQueue.isEmpty else { return }
                let packet = packetQueue.removeFirst()
                self.streamingQueue.async {
                    self.udpConnection?.send(content: packet, completion: .idempotent)
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
