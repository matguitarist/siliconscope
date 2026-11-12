import Darwin
import Foundation

/// Enumerates running processes and determines whether each is executing
/// natively on Apple Silicon or is being translated by Rosetta 2.
///
/// Translation status comes from the kernel's live `P_TRANSLATED` process
/// flag (read via `sysctl(KERN_PROC_PID)`), not from inspecting the binary on
/// disk. That distinction matters: a universal binary launched with
/// `arch -x86_64` (or an app that pins itself to Intel) still shows up here
/// as translated even though a native slice exists.
enum ProcessScanner {
    private static let P_TRANSLATED: Int32 = 0x0002_0000
    /// PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN) from <sys/proc_info.h>.
    /// Hardcoded because the macro doesn't import into Swift.
    private static let maxPathInfoSize = 4 * 1024

    static func listProcesses() -> [ProcessItem] {
        var results: [ProcessItem] = []
        results.reserveCapacity(512)

        for pid in allPIDs() where pid > 0 {
            guard let path = executablePath(for: pid) else { continue }
            let translated = isTranslated(pid: pid)
            let architecture: Architecture
            if translated {
                architecture = .intel
            } else {
                let cpuTypes = MachOReader.cpuTypes(atPath: path)
                let staticArchitecture = MachOReader.architecture(forCPUTypes: cpuTypes)
                // A universal binary running natively (untranslated) is using its arm64 slice.
                architecture = staticArchitecture == .universal ? .appleSilicon : staticArchitecture
            }
            let name = (path as NSString).lastPathComponent
            results.append(ProcessItem(id: pid, name: name, path: path, isTranslated: translated, architecture: architecture))
        }
        return results
    }

    private static func allPIDs() -> [Int32] {
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(bufferSize))
        let byteCount = Int32(pids.count * MemoryLayout<Int32>.size)
        let actualBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, byteCount)
        }
        guard actualBytes > 0 else { return [] }
        let actualCount = min(pids.count, Int(actualBytes) / MemoryLayout<Int32>.size)
        return Array(pids.prefix(actualCount))
    }

    private static func executablePath(for pid: Int32) -> String? {
        var buffer = [Int8](repeating: 0, count: maxPathInfoSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func isTranslated(pid: Int32) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRANSLATED) != 0
    }

    /// Sends SIGTERM to `pid`. Throws with the system's error string (e.g.
    /// "Operation not permitted") if the signal couldn't be delivered.
    static func terminate(pid: Int32) throws {
        guard kill(pid, SIGTERM) == 0 else {
            throw ProcessTerminationError(message: String(cString: strerror(errno)))
        }
    }
}

struct ProcessTerminationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
