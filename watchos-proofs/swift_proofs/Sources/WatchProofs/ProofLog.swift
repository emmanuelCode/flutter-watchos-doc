import Foundation

/// Appends a line to /tmp/watch_proofs/results.log (the simulator shares the host filesystem).
/// The CI workflow prints this file in the job summary.
public func proofLog(_ line: String) {
    let dir = "/tmp/watch_proofs"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = dir + "/results.log"
    let data = Data((line + "\n").utf8)
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(data); try? h.close()
    } else {
        FileManager.default.createFile(atPath: path, contents: data)
    }
}
