import XCTest
@testable import Qingniao
import AppKit

final class AnnotationTests: XCTestCase {
    func testRegionCaptureSessionGuardOnlyAllowsMatchingSessionToFinish() {
        let activeID = UUID()

        XCTAssertTrue(RegionCaptureSessionGuard.shouldFinish(activeSessionID: activeID, requestedSessionID: activeID))
        XCTAssertFalse(RegionCaptureSessionGuard.shouldFinish(activeSessionID: activeID, requestedSessionID: UUID()))
        XCTAssertFalse(RegionCaptureSessionGuard.shouldFinish(activeSessionID: nil, requestedSessionID: activeID))
    }

    func testRegionCropRectUsesMainDisplayOrigin() throws {
        let crop = try XCTUnwrap(ScreenshotGeometry.cropRect(
            globalSelection: NSRect(x: 100, y: 200, width: 300, height: 150),
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            imageSize: CGSize(width: 1440, height: 900)
        ))

        XCTAssertEqual(crop, CGRect(x: 100, y: 550, width: 300, height: 150))
    }

    func testRegionCropRectUsesRightHandRetinaDisplayOriginAndScale() throws {
        let crop = try XCTUnwrap(ScreenshotGeometry.cropRect(
            globalSelection: NSRect(x: 1540, y: 100, width: 200, height: 100),
            screenFrame: NSRect(x: 1440, y: 0, width: 1920, height: 1080),
            imageSize: CGSize(width: 3840, height: 2160)
        ))

        XCTAssertEqual(crop, CGRect(x: 200, y: 1760, width: 400, height: 200))
    }

    func testRegionCropRectSupportsLeftAndLowerDisplayNegativeCoordinates() throws {
        let crop = try XCTUnwrap(ScreenshotGeometry.cropRect(
            globalSelection: NSRect(x: -1200, y: -900, width: 100, height: 50),
            screenFrame: NSRect(x: -1280, y: -1024, width: 1280, height: 1024),
            imageSize: CGSize(width: 1280, height: 1024)
        ))

        XCTAssertEqual(crop, CGRect(x: 80, y: 850, width: 100, height: 50))
    }

    func testRegionCropRectClampsSelectionToDisplayPixelBounds() throws {
        let crop = try XCTUnwrap(ScreenshotGeometry.cropRect(
            globalSelection: NSRect(x: 1910, y: 1070, width: 40, height: 30),
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            imageSize: CGSize(width: 3840, height: 2160)
        ))

        XCTAssertEqual(crop, CGRect(x: 3820, y: 0, width: 20, height: 20))
    }

    func testRegionToolbarAppearsCenteredBelowSelection() {
        let frame = ScreenshotGeometry.toolbarFrame(
            selection: NSRect(x: 400, y: 400, width: 300, height: 200),
            toolbarSize: NSSize(width: 320, height: 56),
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, NSRect(x: 390, y: 332, width: 320, height: 56))
    }

    func testRegionToolbarMovesAboveSelectionNearBottomEdge() {
        let frame = ScreenshotGeometry.toolbarFrame(
            selection: NSRect(x: 400, y: 20, width: 300, height: 100),
            toolbarSize: NSSize(width: 320, height: 56),
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, NSRect(x: 390, y: 132, width: 320, height: 56))
    }

    func testRegionToolbarClampsToBothHorizontalScreenEdges() {
        let screen = NSRect(x: -1280, y: 0, width: 1280, height: 900)

        XCTAssertEqual(
            ScreenshotGeometry.toolbarFrame(
                selection: NSRect(x: -1275, y: 400, width: 100, height: 100),
                toolbarSize: NSSize(width: 320, height: 56),
                screenFrame: screen
            ).minX,
            screen.minX
        )
        XCTAssertEqual(
            ScreenshotGeometry.toolbarFrame(
                selection: NSRect(x: -100, y: 400, width: 100, height: 100),
                toolbarSize: NSSize(width: 320, height: 56),
                screenFrame: screen
            ).maxX,
            screen.maxX
        )
    }

    func testStylePresetsMatchUS017Requirements() {
        XCTAssertEqual(AnnotationColor.allCases.map(\.rawValue), ["red", "yellow", "blue", "green", "white", "black"])
        XCTAssertEqual(AnnotationLineWidth.allCases.map(\.points), [2, 4, 8])
        XCTAssertEqual(AnnotationTextSize.allCases.map(\.points), [18, 28, 42])
    }

    func testAnnotationShapeCodableRoundTrip() throws {
        let shape = AnnotationShape(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            tool: .text,
            startPoint: CGPoint(x: 12, y: 34),
            endPoint: nil,
            text: "Hello",
            style: AnnotationStyle(color: .blue, lineWidth: .thick, textSize: .large)
        )

        let data = try JSONEncoder().encode(shape)
        let decoded = try JSONDecoder().decode(AnnotationShape.self, from: data)

        XCTAssertEqual(decoded, shape)
    }

    func testFlattenRendersAnnotatedPNGData() throws {
        let source = NSImage(size: NSSize(width: 80, height: 60))
        source.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 80, height: 60).fill()
        source.unlockFocus()

        let shapes = [
            AnnotationShape(tool: .rectangle, startPoint: CGPoint(x: 5, y: 5), endPoint: CGPoint(x: 60, y: 40), text: nil, style: AnnotationStyle(color: .red, lineWidth: .medium, textSize: .medium)),
            AnnotationShape(tool: .arrow, startPoint: CGPoint(x: 10, y: 10), endPoint: CGPoint(x: 70, y: 50), text: nil, style: AnnotationStyle(color: .green, lineWidth: .thin, textSize: .small)),
            AnnotationShape(tool: .text, startPoint: CGPoint(x: 8, y: 42), endPoint: nil, text: "A", style: AnnotationStyle(color: .black, lineWidth: .thin, textSize: .small)),
            AnnotationShape(tool: .mosaic, startPoint: CGPoint(x: 20, y: 15), endPoint: CGPoint(x: 45, y: 35), text: nil, style: AnnotationStyle(color: .red, lineWidth: .thin, textSize: .small))
        ]

        let flattened = AnnotationFlattener.flatten(image: source, shapes: shapes)
        let png = try XCTUnwrap(AnnotationFlattener.pngData(from: flattened))

        XCTAssertGreaterThan(png.count, 8)
        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }
}
