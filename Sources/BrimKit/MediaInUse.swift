import CoreAudio
import CoreMediaIO

/// 摄像头、麦克风有没有谁在用（通话中）。只问系统“设备在不在跑”，不碰画面和声音，不需要权限。
/// 收纳用它在通话时暂停：开着“菜单栏显示限制”时，系统会把通话、摄像头的胶囊一起拿掉。
enum MediaInUse {
    static var any: Bool { cameraOn || micOn }

    static var cameraOn: Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == 0 else { return false }
        return devices.contains { device in
            var a = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var got: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0 && running != 0
        }
    }

    static var micOn: Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &devices) == noErr else { return false }
        return devices.contains { device in
            // 只看能录音的设备
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var n: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &n) == noErr, n > 0 else { return false }
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &a, 0, nil, &s, &running) == noErr && running != 0
        }
    }
}
