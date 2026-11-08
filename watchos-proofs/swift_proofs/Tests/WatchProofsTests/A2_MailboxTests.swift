import XCTest
import WatchProofs

/// A2 — [Appendix A] Triple-buffer mailbox: the writer never blocks, the reader gets the newest frame.
final class A2_MailboxTests: XCTestCase {

    func test_writer_never_blocks_when_all_slabs_are_busy() {
        let m = Mailbox()
        XCTAssertEqual([m.acquireWrite(), m.acquireWrite(), m.acquireWrite()], [0, 1, 2])
        XCTAssertEqual(m.acquireWrite(), -1, "4th acquire must return -1 (drop frame), not wait")
    }

    func test_newest_submitted_frame_wins_and_the_older_one_is_freed() {
        let m = Mailbox()
        let a = m.acquireWrite(); m.submit(a, byteCount: 10)
        let b = m.acquireWrite(); m.submit(b, byteCount: 20)

        let read = m.acquireRead()
        XCTAssertEqual(read?.slab, b)
        XCTAssertEqual(read?.byteCount, 20)
        XCTAssertEqual(m.states()[a], .free)
    }

    func test_reader_keeps_the_same_slab_until_a_newer_one_arrives() {
        let m = Mailbox()
        let a = m.acquireWrite(); m.submit(a, byteCount: 10)
        XCTAssertEqual(m.acquireRead()?.slab, a)
        XCTAssertEqual(m.acquireRead()?.slab, a) // redraw with no new frame -> same slab

        let b = m.acquireWrite(); m.submit(b, byteCount: 30)
        XCTAssertEqual(m.acquireRead()?.slab, b)
    }

    func test_abandoned_slab_is_never_shown() {
        let m = Mailbox()
        let a = m.acquireWrite()
        m.abandon(a) // overflowed frame
        XCTAssertNil(m.acquireRead())
        XCTAssertEqual(m.states()[a], .free)
    }
}
