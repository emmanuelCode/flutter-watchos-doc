import XCTest
import WatchProofs

/// A4 — [Appendix A] Dart's DynamicLibrary.process() looks symbols up with dlsym.
/// A @_cdecl Swift function must be findable by its plain C name, and callable.
/// We search the process, the test bundle, and the library's own image, and log which one had it.
final class A4_CdeclSymbolTests: XCTestCase {

    func test_cdecl_symbol_is_found_by_dlsym_and_callable() throws {
        _ = watchProofPing() // referencing it keeps the object linked (see README: dead-strip caveat)

        let candidates: [(String, UnsafeMutableRawPointer?)] = [
            ("process", dlopen(nil, RTLD_NOW)),
            ("test bundle", Bundle(for: Self.self).executablePath.flatMap { dlopen($0, RTLD_NOW) }),
            ("library image", Bundle(for: WatchProofsMarker.self).executablePath.flatMap { dlopen($0, RTLD_NOW) }),
        ]
        var found: (String, UnsafeMutableRawPointer)?
        for (name, handle) in candidates {
            if let h = handle, let sym = dlsym(h, "watch_proof_ping") { found = (name, sym); break }
        }
        let (where_, sym) = try XCTUnwrap(found, "watch_proof_ping not visible to dlsym in any image")
        proofLog("A4: symbol found via \(where_)")

        typealias Fn = @convention(c) () -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        XCTAssertEqual(fn(), 42)
    }
}
