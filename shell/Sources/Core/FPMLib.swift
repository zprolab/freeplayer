import Foundation

@_silgen_name("compress2") private func fp_compress2(_ dest: UnsafeMutablePointer<UInt8>, _ destLen: UnsafeMutablePointer<UInt64>, _ source: UnsafePointer<UInt8>, _ sourceLen: UInt64, _ level: Int32) -> Int32
@_silgen_name("uncompress") private func fp_uncompress(_ dest: UnsafeMutablePointer<UInt8>, _ destLen: UnsafeMutablePointer<UInt64>, _ source: UnsafePointer<UInt8>, _ sourceLen: UInt64) -> Int32

/// Single-file, append-only FreePlayer library container.
/// Audio bytes are never transcoded: compression is byte-for-byte reversible.
enum FPMLib {
    private static let magic = Data("FPMLIB01".utf8)
    private static let lock = NSLock()

    struct Entry { let id: String; let offset: UInt64; let originalSize: UInt64; let storedSize: UInt64; let compressed: Bool }

    static func containerPath(library: String) -> String {
        (library as NSString).appendingPathComponent("FreePlayer.fpmlib")
    }

    static func add(sourcePath: String, containerPath: String) throws -> String {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: sourcePath), options: [.mappedIfSafe])
        return try add(data: bytes, containerPath: containerPath)
    }

    static func add(data bytes: Data, containerPath: String) throws -> String {
        let compressed = compress(bytes)
        let useCompression = compressed.count < bytes.count
        let payload = useCompression ? compressed : bytes
        let id = UUID().uuidString.lowercased()
        let idData = Data(id.utf8)
        guard idData.count <= UInt32.max else { throw NSError(domain: "FPMLib", code: 1) }
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try fm.createDirectory(at: URL(fileURLWithPath: containerPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: containerPath) { fm.createFile(atPath: containerPath, contents: magic) }
        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: containerPath)); defer { try? h.close() }
        _ = h.seekToEndOfFile()
        var header = Data(); appendU32(&header, UInt32(idData.count)); appendU64(&header, UInt64(bytes.count)); appendU64(&header, UInt64(payload.count)); header.append(useCompression ? 1 : 0); header.append(idData)
        h.write(header); h.write(payload)
        return id
    }

    static func read(id: String, containerPath: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let data = try Data(contentsOf: URL(fileURLWithPath: containerPath), options: [.mappedIfSafe])
        guard data.count >= magic.count, data.prefix(magic.count) == magic else { throw NSError(domain: "FPMLib", code: 2) }
        var p = magic.count
        while p + 25 <= data.count {
            let idLen = Int(readU32(data, p)); p += 4
            let original = readU64(data, p); p += 8
            let stored = readU64(data, p); p += 8
            let compressed = data[p] != 0; p += 1
            guard idLen <= 1024, p + idLen <= data.count else { break }
            let entryId = String(data: data[p..<p + idLen], encoding: .utf8) ?? ""; p += idLen
            guard stored <= UInt64(data.count - p) else { break }
            let payload = Data(data[p..<p + Int(stored)]); p += Int(stored)
            if entryId == id {
                let result = compressed ? decompress(payload, size: Int(original)) : payload
                guard UInt64(result.count) == original else { throw NSError(domain: "FPMLib", code: 3) }
                return result
            }
        }
        throw NSError(domain: "FPMLib", code: 4, userInfo: [NSLocalizedDescriptionKey: "fpmlib entry not found: \(id)"])
    }

    private static func compress(_ input: Data) -> Data {
        guard !input.isEmpty else { return input }
        let bound = max(input.count + 64, input.count * 2)
        var out = Data(count: bound)
        var outputSize = UInt64(bound)
        let result = input.withUnsafeBytes { src in out.withUnsafeMutableBytes { dst in
            fp_compress2(dst.bindMemory(to: UInt8.self).baseAddress!, &outputSize,
                src.bindMemory(to: UInt8.self).baseAddress!, UInt64(input.count), 9)
        }}
        return result == 0 ? out.prefix(Int(outputSize)) : input
    }

    private static func decompress(_ input: Data, size: Int) -> Data {
        var out = Data(count: size)
        var outputSize = UInt64(size)
        let result = input.withUnsafeBytes { src in out.withUnsafeMutableBytes { dst in
            fp_uncompress(dst.bindMemory(to: UInt8.self).baseAddress!, &outputSize,
                src.bindMemory(to: UInt8.self).baseAddress!, UInt64(input.count))
        }}
        return result == 0 && outputSize == UInt64(size) ? out : Data()
    }

    private static func appendU32(_ d: inout Data, _ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    private static func appendU64(_ d: inout Data, _ v: UInt64) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    private static func readU32(_ d: Data, _ p: Int) -> UInt32 { d[p..<p+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } }
    private static func readU64(_ d: Data, _ p: Int) -> UInt64 { d[p..<p+8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian } }
}
