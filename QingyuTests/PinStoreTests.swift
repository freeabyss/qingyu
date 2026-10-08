import XCTest
@testable import Qingyu

@MainActor
final class PinStoreTests: XCTestCase {

    // MARK: - Lifecycle

    func testAddCloseRestoreAndDestroy() {
        let store = PinStore()
        let pin = store.add(payload: .text("example"))
        XCTAssertEqual(store.activeCount, 1)

        store.close(pin.id)
        XCTAssertEqual(store.activeCount, 0)
        XCTAssertEqual(store.closedCount, 1)

        XCTAssertEqual(store.restoreLatestClosed()?.id, pin.id)
        XCTAssertEqual(store.activeCount, 1)
        XCTAssertEqual(store.closedCount, 0)

        store.destroy(pin.id)
        XCTAssertNil(store.restoreLatestClosed(), "销毁后不可恢复")
        XCTAssertNil(store.item(id: pin.id))
    }

    func testRestoreQueueRespectsCapacityAndDropsOldest() {
        let store = PinStore(restoreCapacity: 2)
        let first = store.add(payload: .text("1"))
        let second = store.add(payload: .text("2"))
        let third = store.add(payload: .text("3"))

        store.close(first.id)
        store.close(second.id)
        store.close(third.id)

        XCTAssertEqual(store.closedCount, 2, "恢复队列按容量丢弃最旧")
        XCTAssertEqual(store.restoreLatestClosed()?.id, third.id)
        XCTAssertEqual(store.restoreLatestClosed()?.id, second.id)
        XCTAssertNil(store.restoreLatestClosed(), "first 已被容量挤出")
    }

    func testRestoreCapacityClampedToZeroThroughTwenty() {
        XCTAssertEqual(PinStore(restoreCapacity: -3).restoreCapacity, 0)
        XCTAssertEqual(PinStore(restoreCapacity: 0).restoreCapacity, 0)
        XCTAssertEqual(PinStore(restoreCapacity: 99).restoreCapacity, 20)
        XCTAssertEqual(PinStore(restoreCapacity: 7).restoreCapacity, 7)

        let store = PinStore(restoreCapacity: 0)
        let pin = store.add(payload: .text("x"))
        store.close(pin.id)
        XCTAssertNil(store.restoreLatestClosed(), "容量为 0 时不可恢复")

        store.setRestoreCapacity(1)
        XCTAssertNil(store.restoreLatestClosed(), "容量为 0 期间关闭的内容已按「超出部分立即丢弃」语义丢弃")

        let second = store.add(payload: .text("y"))
        store.close(second.id)
        XCTAssertEqual(store.restoreLatestClosed()?.id, second.id, "扩容后新关闭的内容可恢复")
    }

    // MARK: - Hide / show / destroy all

    func testHideAllAndShowAll() {
        let store = PinStore()
        let a = store.add(payload: .text("a"))
        let b = store.add(payload: .text("b"))

        store.hideAll()
        XCTAssertTrue(store.item(id: a.id)?.isHidden ?? false)
        XCTAssertTrue(store.item(id: b.id)?.isHidden ?? false)

        store.showAll()
        XCTAssertFalse(store.item(id: a.id)?.isHidden ?? true)
        XCTAssertFalse(store.item(id: b.id)?.isHidden ?? true)
    }

    func testDestroyAllClearsActiveAndRestoreQueue() {
        let store = PinStore()
        let a = store.add(payload: .text("a"))
        let b = store.add(payload: .text("b"))
        store.close(b.id)

        store.destroyAll()

        XCTAssertEqual(store.activeCount, 0)
        XCTAssertEqual(store.closedCount, 0)
        XCTAssertNil(store.item(id: a.id))
        XCTAssertNil(store.restoreLatestClosed())
    }

    // MARK: - Transform / payload / passthrough updates

    func testUpdateTransformClampsScaleAndOpacity() {
        let store = PinStore()
        let pin = store.add(payload: .text("t"))

        store.updateTransform(PinTransform(scale: 20, opacity: 0.02), for: pin.id)
        let updated = store.item(id: pin.id)
        XCTAssertEqual(updated?.transform.scale, PinTransform.maximumScale, "缩放钳制 800%")
        XCTAssertEqual(updated?.transform.opacity, PinTransform.minimumOpacity, "不透明度钳制 10%")

        store.updateTransform(PinTransform(scale: 0.01, opacity: 5), for: pin.id)
        XCTAssertEqual(store.item(id: pin.id)?.transform.scale, PinTransform.minimumScale, "缩放钳制 10%")
        XCTAssertEqual(store.item(id: pin.id)?.transform.opacity, PinTransform.maximumOpacity, "不透明度钳制 100%")
    }

    func testReplacePayloadKeepsIDAndTransform() {
        let store = PinStore()
        let pin = store.add(payload: .text("old"))
        store.updateTransform(PinTransform(scale: 2), for: pin.id)

        store.replacePayload(.image(Data([0x89, 0x50])), for: pin.id)

        let updated = store.item(id: pin.id)
        XCTAssertEqual(updated?.payload.kind, .image)
        XCTAssertEqual(updated?.transform.scale, 2, "替换载荷保留 id 与变换")
    }

    func testIgnoresMouseEventsPassthrough() {
        let store = PinStore()
        let pin = store.add(payload: .text("t"))

        store.setIgnoresMouseEvents(true, for: pin.id)
        XCTAssertTrue(store.item(id: pin.id)?.ignoresMouseEvents ?? false)

        store.setIgnoresMouseEvents(false, for: pin.id)
        XCTAssertFalse(store.item(id: pin.id)?.ignoresMouseEvents ?? true)
    }
}
