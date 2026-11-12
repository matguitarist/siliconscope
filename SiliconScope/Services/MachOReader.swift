import Foundation

/// Reads the CPU type(s) a Mach-O binary was built for, directly from its
/// file header. Works for both thin (single-architecture) and fat
/// (universal) binaries without shelling out to `file` or `lipo`.
enum MachOReader {
    private static let FAT_MAGIC: UInt32 = 0xcafebabe
    private static let FAT_CIGAM: UInt32 = 0xbebafeca
    private static let FAT_MAGIC_64: UInt32 = 0xcafebabf
    private static let FAT_CIGAM_64: UInt32 = 0xbfbafeca
    private static let MH_MAGIC: UInt32 = 0xfeedface
    private static let MH_CIGAM: UInt32 = 0xcefaedfe
    private static let MH_MAGIC_64: UInt32 = 0xfeedfacf
    private static let MH_CIGAM_64: UInt32 = 0xcffaedfe

    static let cpuTypeX86_64: Int32 = 0x0100_0007
    static let cpuTypeARM64: Int32 = 0x0100_000c

    /// Returns the set of `cputype` values (mach/machine.h constants) found in the binary at `path`.
    ///
    /// Fat (universal) headers are always stored big-endian on disk; thin Mach-O
    /// headers are stored in the file's native (little-endian, on every Mac we
    /// care about) order. We don't know which one we have until the magic is
    /// decoded, so both interpretations of the same 4 bytes are computed up front.
    static func cpuTypes(atPath path: String) -> Set<Int32> {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        guard let magicBytes = try? handle.read(upToCount: 4), magicBytes.count == 4 else { return [] }
        let magicBE = readUInt32(magicBytes, bigEndian: true)
        let magicLE = readUInt32(magicBytes, bigEndian: false)

        if magicBE == FAT_MAGIC || magicBE == FAT_CIGAM {
            return readFatArchs(handle: handle, is64: false)
        }
        if magicBE == FAT_MAGIC_64 || magicBE == FAT_CIGAM_64 {
            return readFatArchs(handle: handle, is64: true)
        }
        if magicLE == MH_MAGIC || magicLE == MH_MAGIC_64 {
            guard let cpuTypeBytes = try? handle.read(upToCount: 4), cpuTypeBytes.count == 4 else { return [] }
            return [Int32(bitPattern: readUInt32(cpuTypeBytes, bigEndian: false))]
        }
        if magicLE == MH_CIGAM || magicLE == MH_CIGAM_64 {
            guard let cpuTypeBytes = try? handle.read(upToCount: 4), cpuTypeBytes.count == 4 else { return [] }
            return [Int32(bitPattern: readUInt32(cpuTypeBytes, bigEndian: true))]
        }
        return []
    }

    /// Classifies a set of cputypes into a single reportable architecture.
    static func architecture(forCPUTypes types: Set<Int32>) -> Architecture {
        guard !types.isEmpty else { return .unknown }
        let hasARM64 = types.contains(cpuTypeARM64)
        let hasX86_64 = types.contains(cpuTypeX86_64)
        switch (hasARM64, hasX86_64) {
        case (true, true): return .universal
        case (true, false): return .appleSilicon
        case (false, true): return .intel
        case (false, false): return .unknown
        }
    }

    // MARK: - Private helpers

    private static func readFatArchs(handle: FileHandle, is64: Bool) -> Set<Int32> {
        guard let countBytes = try? handle.read(upToCount: 4), countBytes.count == 4 else { return [] }
        let nfatArch = Int(readUInt32(countBytes, bigEndian: true))
        guard nfatArch > 0, nfatArch < 32 else { return [] } // sanity bound

        let entrySize = is64 ? 32 : 20
        guard let entriesData = try? handle.read(upToCount: nfatArch * entrySize) else { return [] }

        var result = Set<Int32>()
        for i in 0..<nfatArch {
            let offset = i * entrySize
            guard offset + 4 <= entriesData.count else { break }
            let cputypeBytes = entriesData.subdata(in: offset..<(offset + 4))
            result.insert(Int32(bitPattern: readUInt32(cputypeBytes, bigEndian: true)))
        }
        return result
    }

    /// Decodes 4 bytes of `data` as a UInt32, avoiding unaligned-load traps.
    private static func readUInt32(_ data: Data, bigEndian: Bool) -> UInt32 {
        let bytes = [UInt8](data.prefix(4))
        guard bytes.count == 4 else { return 0 }
        if bigEndian {
            return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        } else {
            return (UInt32(bytes[3]) << 24) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[1]) << 8) | UInt32(bytes[0])
        }
    }
}
