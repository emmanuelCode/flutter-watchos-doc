import os

public enum SlabState: Sendable { case free, writing, ready, reading }

/// Appendix A triple-buffer mailbox — state machine only (no memory, no SwiftUI).
public final class Mailbox {
    struct Slab: Sendable { var state: SlabState = .free; var byteCount = 0 }
    private let lock = OSAllocatedUnfairLock(initialState: [Slab](repeating: Slab(), count: 3))

    public init() {}

    /// Free slab index, or -1 (writer drops the frame instead of blocking).
    public func acquireWrite() -> Int {
        lock.withLock { (s: inout [Slab]) -> Int in
            guard let i = s.firstIndex(where: { $0.state == .free }) else { return -1 }
            s[i].state = .writing
            return i
        }
    }

    public func submit(_ i: Int, byteCount: Int) {
        lock.withLock { (s: inout [Slab]) in
            for j in s.indices where s[j].state == .ready { s[j].state = .free } // superseded
            s[i].state = .ready
            s[i].byteCount = byteCount
        }
    }

    public func abandon(_ i: Int) {
        lock.withLock { (s: inout [Slab]) in s[i].state = .free }
    }

    /// Newest frame; keeps returning the current slab until a newer one is ready.
    public func acquireRead() -> (slab: Int, byteCount: Int)? {
        lock.withLock { (s: inout [Slab]) -> (slab: Int, byteCount: Int)? in
            if let r = s.firstIndex(where: { $0.state == .ready }) {
                for j in s.indices where s[j].state == .reading { s[j].state = .free }
                s[r].state = .reading
            }
            guard let cur = s.firstIndex(where: { $0.state == .reading }) else { return nil }
            return (cur, s[cur].byteCount)
        }
    }

    public func states() -> [SlabState] {
        lock.withLock { (s: inout [Slab]) -> [SlabState] in s.map { $0.state } }
    }
}
