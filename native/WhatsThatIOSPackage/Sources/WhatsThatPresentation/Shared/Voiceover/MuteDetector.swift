import Foundation
import AudioToolbox
import AVFoundation

public class MuteDetector {
    public static let shared = MuteDetector()
    
    private var soundId: SystemSoundID = 0
    private let soundDuration: TimeInterval = 0.5
    
    // We'll use a silent .aiff or .caf file. 
    // Since we don't have a file resource, we can try to create one or use a system sound workaround.
    // However, creating a silent audio file programmatically is cleaner.
    
    init() {
        createSilentSoundFile()
    }
    
    deinit {
        if soundId != 0 {
            AudioServicesDisposeSystemSoundID(soundId)
        }
        deleteSilentSoundFile()
    }
    
    public func check(completion: @escaping (Bool) -> Void) {
        // If we failed to create sound ID, assume not muted (safe default)
        guard soundId != 0 else {
            completion(false)
            return
        }
        
        let startTime = Date()
        
        AudioServicesPlaySystemSoundWithCompletion(soundId) {
            let elapsed = Date().timeIntervalSince(startTime)
            // If playback happened too fast (e.g. < 0.1s), it's likely muted
            // The sound file is 0.5s long.
            let isMuted = elapsed < 0.1
            
            DispatchQueue.main.async {
                completion(isMuted)
            }
        }
    }
    
    private func createSilentSoundFile() {
        let fileName = "mute-check.caf"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        // Define audio format
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        // Create file
        var audioFile: ExtAudioFileRef?
        let status = ExtAudioFileCreateWithURL(
            fileURL as CFURL,
            kAudioFileCAFType,
            &asbd,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &audioFile
        )
        
        guard status == noErr, let file = audioFile else {
            return
        }
        
        // Write 0.5 seconds of silence
        let framesToWrite = UInt32(0.5 * 44100.0)
        let bufferSize = framesToWrite * 2 // 2 bytes per frame
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(bufferSize), alignment: 1)
        memset(buffer, 0, Int(bufferSize)) // Silence
        
        let audioBuffer = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: bufferSize,
            mData: buffer
        )
        
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: (audioBuffer)
        )
        
        ExtAudioFileWrite(file, framesToWrite, &bufferList)
        ExtAudioFileDispose(file)
        buffer.deallocate()
        
        // Create System Sound ID
        AudioServicesCreateSystemSoundID(fileURL as CFURL, &soundId)
    }
    
    private func deleteSilentSoundFile() {
        let fileName = "mute-check.caf"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
