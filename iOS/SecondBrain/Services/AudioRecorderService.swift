import Foundation
import AVFoundation
import SwiftUI

/// Records audio on iOS. Adapted from NotesAgent but standalone (no sync).
class AudioRecorderService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    let recordingsDirectory: URL

    override init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.recordingsDirectory = documentsPath.appendingPathComponent("Recordings")
        super.init()
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            audioRecorder?.pause()
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume), isRecording {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    audioRecorder?.record()
                } catch {
                    print("Failed to resume after interruption: \(error)")
                }
            }
        @unknown default:
            break
        }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start recording. Returns the URL where audio will be saved.
    func startRecording() -> URL? {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let filename = "thought-\(Date().timeIntervalSince1970).m4a"
            let audioURL = recordingsDirectory.appendingPathComponent(filename)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            isRecording = true
            recordingDuration = 0

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingDuration = self?.audioRecorder?.currentTime ?? 0
            }

            return audioURL

        } catch {
            print("Failed to start recording: \(error)")
            return nil
        }
    }

    /// Stop recording. Returns the duration.
    func stopRecording() -> TimeInterval {
        let duration = recordingDuration
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        return duration
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { print("Recording failed") }
    }
}
