import XCTest
import ProbeCore

final class ProbeTests: XCTestCase {

    func testPathSemantics() {
        XCTAssertTrue(PathProbe.pathSemantics().ok)
    }

    func testCaseBehavior() {
        XCTAssertTrue(PathProbe.caseBehavior().ok)
    }

    func testUnicodeNames() {
        XCTAssertTrue(PathProbe.unicodeNames().ok)
    }

    func testLineEndings() {
        XCTAssertTrue(PathProbe.lineEndings().ok)
    }

    func testAtomicWrite() {
        XCTAssertTrue(PathProbe.atomicWrite().ok)
    }

    func testAtomicWriteWhileOpen() {
        XCTAssertTrue(PathProbe.atomicWriteWhileOpen().ok)
    }

    func testMoveAndCopy() {
        XCTAssertTrue(PathProbe.moveAndCopysemantics().ok)
    }

    func testCrossVolumeMove() {
        XCTAssertTrue(PathProbe.crossVolumeMove().ok)
    }

    func testLongPath() {
        XCTAssertTrue(PathProbe.longPathBehavior().ok)
    }

    func testRegexChinese() {
        XCTAssertTrue(TextProbe.regexChinese().ok)
    }

    func testRegexUnicodeProperty() {
        XCTAssertTrue(TextProbe.regexUnicodeProperty().ok)
    }

    func testNormalisation() {
        XCTAssertTrue(TextProbe.normalisation().ok)
    }

    func testCharacterSets() {
        XCTAssertTrue(TextProbe.characterSets().ok)
    }

    func testDateFormatting() {
        XCTAssertTrue(TextProbe.dateFormatting().ok)
    }

    func testJSONRoundTrip() {
        XCTAssertTrue(TextProbe.jsonRoundTrip().ok)
    }

    func testStringSearch() {
        XCTAssertTrue(TextProbe.stringSearch().ok)
    }

    func testDispatch() {
        XCTAssertTrue(SystemProbe.concurrentQueue().ok)
    }

    func testFileHandle() {
        XCTAssertTrue(SystemProbe.fileHandle().ok)
    }

    func testChildProcess() {
        XCTAssertTrue(SystemProbe.childProcess().ok)
    }

    func testNotifications() {
        XCTAssertTrue(SystemProbe.notifications().ok)
    }

    func testAsyncTaskGroup() async {
        let result = await SystemProbe.asyncTaskGroup()
        XCTAssertTrue(result.ok)
    }

    /// Aggregated run: prints a single summary line that is easy to grep in CI.
    func testAggregateSummary() async {
        var results = SystemProbe.runAllSynchronously()
        results.append(await SystemProbe.asyncTaskGroup())

        let passed = results.filter { $0.ok }.count
        let failed = results.count - passed
        print("SUMMARY|total=\(results.count)|passed=\(passed)|failed=\(failed)")
        for result in results where !result.ok {
            print("SUMMARY|failed=\(result.name)|\(result.details)")
        }
        XCTAssertEqual(failed, 0)
    }
}
