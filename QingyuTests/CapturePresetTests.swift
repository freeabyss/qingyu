import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 015：预设的数据模型、落位计算与目录管理。
@MainActor
final class CapturePresetTests: XCTestCase {

    private let mainScreen = ScreenDescriptor(
        displayID: "1",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    private let secondaryScreen = ScreenDescriptor(
        displayID: "2",
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    )

    private func regionPreset(
        displayID: String? = "1",
        rect: CGRect? = CGRect(x: 100, y: 200, width: 300, height: 150)
    ) -> CapturePreset {
        CapturePreset(name: "区域", kind: .region, displayID: displayID, rect: rect)
    }

    private func sizePreset(width: CGFloat = 400, height: CGFloat = 300) -> CapturePreset {
        CapturePreset(name: "尺寸", kind: .size, size: CGSize(width: width, height: height))
    }

    // MARK: - 区域落位

    func testRegionResolvesRelativeToScreenOrigin() throws {
        // 次级屏原点 (1440, 0)：相对偏移 (100, 200) → 全局 (1540, 200)。
        let preset = regionPreset(displayID: "2")
        let rect = try PresetResolver.resolve(
            regionPreset: preset,
            availableScreens: [mainScreen, secondaryScreen]
        ).get()

        XCTAssertEqual(rect, CGRect(x: 1540, y: 200, width: 300, height: 150))
    }

    func testRegionOnMissingScreenReportsUnavailableWithoutFallingBack() {
        let preset = regionPreset(displayID: "99")

        XCTAssertEqual(
            PresetResolver.resolve(regionPreset: preset, availableScreens: [mainScreen]),
            .failure(.screenUnavailable(displayID: "99")),
            "目标屏幕断开时必须报错，不得静默改用其它屏幕"
        )
    }

    func testRegionWithoutDisplayIDIsUnavailable() {
        XCTAssertEqual(
            PresetResolver.resolve(regionPreset: regionPreset(displayID: nil), availableScreens: [mainScreen]),
            .failure(.screenUnavailable(displayID: ""))
        )
    }

    func testRegionOutOfBoundsWhenItNoLongerFits() {
        // 矩形越出主屏右缘（100 + 1400 > 1440）。
        let preset = regionPreset(rect: CGRect(x: 100, y: 200, width: 1400, height: 150))

        XCTAssertEqual(
            PresetResolver.resolve(regionPreset: preset, availableScreens: [mainScreen]),
            .failure(.outOfBounds)
        )
    }

    func testRegionWithDegenerateRectIsOutOfBounds() {
        XCTAssertEqual(
            PresetResolver.resolve(regionPreset: regionPreset(rect: nil), availableScreens: [mainScreen]),
            .failure(.outOfBounds)
        )
        XCTAssertEqual(
            PresetResolver.resolve(
                regionPreset: regionPreset(rect: CGRect(x: 0, y: 0, width: 0, height: 100)),
                availableScreens: [mainScreen]
            ),
            .failure(.outOfBounds)
        )
    }

    // MARK: - 尺寸落位

    func testSizeIsCenteredOnPointer() {
        let rect = PresetResolver.resolve(
            sizePreset: sizePreset(width: 400, height: 300),
            pointerLocation: CGPoint(x: 700, y: 500),
            screen: mainScreen
        )

        XCTAssertEqual(rect, CGRect(x: 500, y: 350, width: 400, height: 300))
    }

    func testSizeIsClampedToVisibleFrameEdges() {
        // 指针贴近左下角：选区不得越出可见区。
        let bottomLeft = PresetResolver.resolve(
            sizePreset: sizePreset(width: 400, height: 300),
            pointerLocation: CGPoint(x: 10, y: 10),
            screen: mainScreen
        )
        XCTAssertEqual(bottomLeft.origin, CGPoint(x: 0, y: 0))

        // 指针贴近右上角。
        let topRight = PresetResolver.resolve(
            sizePreset: sizePreset(width: 400, height: 300),
            pointerLocation: CGPoint(x: 1435, y: 895),
            screen: mainScreen
        )
        XCTAssertEqual(topRight.maxX, mainScreen.visibleFrame.maxX)
        XCTAssertEqual(topRight.maxY, mainScreen.visibleFrame.maxY)
    }

    func testOversizedPresetIsTruncatedToVisibleFrame() {
        let rect = PresetResolver.resolve(
            sizePreset: sizePreset(width: 4000, height: 3000),
            pointerLocation: CGPoint(x: 700, y: 500),
            screen: mainScreen
        )

        XCTAssertEqual(rect, mainScreen.visibleFrame, "尺寸大于可见区时截断而非报错")
    }

    func testSizeOnSecondaryScreenClampsToThatScreen() {
        let rect = PresetResolver.resolve(
            sizePreset: sizePreset(width: 400, height: 300),
            pointerLocation: CGPoint(x: 1450, y: 10),
            screen: secondaryScreen
        )

        XCTAssertEqual(rect.origin, CGPoint(x: 1440, y: 0))
    }

    // MARK: - 目录

    func testCatalogEnforcesMaximumCount() {
        var catalog = CapturePresetCatalog()
        for index in 0..<CapturePresetCatalog.maximumCount {
            XCTAssertTrue(catalog.add(CapturePreset(name: "p\(index)", kind: .size, size: CGSize(width: 10, height: 10))))
        }

        XCTAssertTrue(catalog.isFull)
        XCTAssertFalse(
            catalog.add(CapturePreset(name: "overflow", kind: .size, size: CGSize(width: 10, height: 10))),
            "满额后必须返回 false，由调用方提示，而不是静默丢弃"
        )
        XCTAssertEqual(catalog.count, CapturePresetCatalog.maximumCount)
    }

    func testCatalogRemoveRenumbersOrder() {
        var catalog = CapturePresetCatalog()
        for index in 0..<3 {
            catalog.add(CapturePreset(name: "p\(index)", kind: .size, size: CGSize(width: 10, height: 10)))
        }
        let middleID = catalog.ordered[1].id

        XCTAssertTrue(catalog.remove(id: middleID))
        XCTAssertEqual(catalog.ordered.map(\.order), [0, 1], "删除后 order 重新编号为连续")
        XCTAssertFalse(catalog.remove(id: middleID), "重复删除返回 false")
    }

    func testCatalogMoveReorders() {
        var catalog = CapturePresetCatalog()
        for index in 0..<3 {
            catalog.add(CapturePreset(name: "p\(index)", kind: .size, size: CGSize(width: 10, height: 10)))
        }

        XCTAssertTrue(catalog.move(from: 2, to: 0))
        XCTAssertEqual(catalog.ordered.map(\.name), ["p2", "p0", "p1"])

        XCTAssertFalse(catalog.move(from: 0, to: 0), "原地移动返回 false")
        XCTAssertFalse(catalog.move(from: 9, to: 0), "越界起点返回 false")
    }

    func testCatalogUpdateKeepsOrder() {
        var catalog = CapturePresetCatalog()
        catalog.add(CapturePreset(name: "a", kind: .size, size: CGSize(width: 10, height: 10)))
        catalog.add(CapturePreset(name: "b", kind: .size, size: CGSize(width: 10, height: 10)))

        var renamed = catalog.ordered[1]
        renamed.name = "b-renamed"
        XCTAssertTrue(catalog.update(renamed))
        XCTAssertEqual(catalog.ordered.map(\.name), ["a", "b-renamed"])

        XCTAssertFalse(catalog.update(CapturePreset(name: "ghost", kind: .size, size: CGSize(width: 1, height: 1))))
    }

    func testDisplayLabelsDisambiguateDuplicateNames() {
        let presets = [
            CapturePreset(name: "区域", kind: .size, size: CGSize(width: 10, height: 10)),
            CapturePreset(name: "区域", kind: .size, size: CGSize(width: 10, height: 10))
        ]

        XCTAssertEqual(CapturePresetCatalog.displayLabels(for: presets), ["1. 区域", "2. 区域"])
    }

    // MARK: - 持久化

    func testStorePersistsEveryMutationAndReloads() async {
        let persistence = InMemoryCapturePresetPersistence()
        let store = CapturePresetStore(persistence: persistence)

        await store.add(CapturePreset(name: "a", kind: .size, size: CGSize(width: 10, height: 10)))
        await store.add(CapturePreset(name: "b", kind: .size, size: CGSize(width: 20, height: 20)))
        await store.move(from: 1, to: 0)

        let reloaded = CapturePresetStore(persistence: persistence)
        await reloaded.reload()
        XCTAssertEqual(reloaded.catalog.ordered.map(\.name), ["b", "a"])

        var renamed = reloaded.catalog.ordered[0]
        renamed.name = "b2"
        await reloaded.update(renamed)
        await reloaded.remove(id: reloaded.catalog.ordered[1].id)

        let again = CapturePresetStore(persistence: persistence)
        await again.reload()
        XCTAssertEqual(again.catalog.ordered.map(\.name), ["b2"])
    }

    func testStoreSuggestedNameAvoidsCollisions() async {
        let store = CapturePresetStore(persistence: InMemoryCapturePresetPersistence())
        await store.add(CapturePreset(name: "区域 2", kind: .size, size: CGSize(width: 10, height: 10)))

        let suggested = store.suggestedName(prefix: "区域")
        XCTAssertFalse(store.catalog.presets.map(\.name).contains(suggested))
    }

    func testPresetCodableRoundTrip() throws {
        let presets = [
            CapturePreset(name: "区域", kind: .region, displayID: "1", rect: CGRect(x: 12, y: 34, width: 56, height: 78), order: 0),
            CapturePreset(name: "尺寸", kind: .size, size: CGSize(width: 640, height: 480), order: 1)
        ]

        let data = try JSONEncoder().encode(presets)
        let decoded = try JSONDecoder().decode([CapturePreset].self, from: data)

        XCTAssertEqual(decoded, presets, "序列化往返必须一致")
    }

    func testUsableFlagDetectsIncompletePresets() {
        XCTAssertTrue(regionPreset().isUsable)
        XCTAssertTrue(sizePreset().isUsable)
        XCTAssertFalse(CapturePreset(name: "x", kind: .region, displayID: "1").isUsable)
        XCTAssertFalse(CapturePreset(name: "x", kind: .size).isUsable)
        XCTAssertFalse(
            CapturePreset(name: "x", kind: .size, size: CGSize(width: 0, height: 10)).isUsable
        )
    }
}
