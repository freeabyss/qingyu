import AppKit
import XCTest
@testable import Qingyu

final class CalculatorSourceTests: XCTestCase {
    func testEvaluatesArithmeticExpressionWithPrecedenceAndDecimals() async throws {
        let source = CalculatorSource()

        let results = await source.search(query: "888*0.8")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].sourceID, .calculator)
        XCTAssertEqual(results[0].title, "= 710.4")
        XCTAssertEqual(results[0].typeLabel, "Calculator")
        if case .copyText(let value) = results[0].primaryAction {
            XCTAssertEqual(value, "710.4")
        } else {
            XCTFail("Calculator result should copy the formatted result")
        }
    }

    func testEvaluatesParenthesesAndUnaryOperators() async throws {
        let source = CalculatorSource()

        let results = await source.search(query: "(1.5 + 2.5) * -3")

        XCTAssertEqual(results.first?.title, "= -12")
    }

    func testRejectsPlainTextAndSignedNumberWithoutOperator() async throws {
        let source = CalculatorSource()

        let textResults = await source.search(query: "chrome")
        let signedNumberResults = await source.search(query: "-5")

        XCTAssertTrue(textResults.isEmpty)
        XCTAssertTrue(signedNumberResults.isEmpty)
    }

    func testRejectsInvalidExpressionsAndDivisionByZero() async throws {
        let source = CalculatorSource()

        let directDivisionByZero = await source.search(query: "1/0")
        let nestedDivisionByZero = await source.search(query: "1/(2-2)")
        let invalidOperator = await source.search(query: "1++")
        let unbalancedParentheses = await source.search(query: "(1+2")

        XCTAssertTrue(directDivisionByZero.isEmpty)
        XCTAssertTrue(nestedDivisionByZero.isEmpty)
        XCTAssertTrue(invalidOperator.isEmpty)
        XCTAssertTrue(unbalancedParentheses.isEmpty)
    }

    func testRejectsFunctionsVariablesCurrencyAndHistoryLikeInput() async throws {
        let source = CalculatorSource()

        let functionResults = await source.search(query: "sin(1)")
        let variableResults = await source.search(query: "a + 1")
        let currencyResults = await source.search(query: "100 usd to cny")
        let historyResults = await source.search(query: "history")

        XCTAssertTrue(functionResults.isEmpty)
        XCTAssertTrue(variableResults.isEmpty)
        XCTAssertTrue(currencyResults.isEmpty)
        XCTAssertTrue(historyResults.isEmpty)
    }

    func testLooksLikeExpressionGate() {
        XCTAssertTrue(CalculatorSource.looksLikeExpression("1 + 2"))
        XCTAssertTrue(CalculatorSource.looksLikeExpression("(2.5 + 1) / 7"))
        XCTAssertFalse(CalculatorSource.looksLikeExpression("2^10"))
        XCTAssertFalse(CalculatorSource.looksLikeExpression("100 usd"))
        XCTAssertFalse(CalculatorSource.looksLikeExpression("+3"))
    }

    // MARK: - Unit conversion (migrated from UnitConverterSourceTests, T-005)

    func testConvertsCentimetersToInches() async throws {
        let source = CalculatorSource()

        let results = await source.search(query: "10 cm to inch")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].typeLabel, "Convert")
        XCTAssertEqual(results[0].title, "3.937008 in")
        if case .copyText(let value) = results[0].primaryAction {
            XCTAssertEqual(value, "3.937008 in")
        } else {
            XCTFail("Unit conversion should copy the converted value")
        }
    }

    func testConvertsKilogramsToPounds() async throws {
        let source = CalculatorSource()

        let results = await source.search(query: "100 kg to lb")

        XCTAssertEqual(results.first?.title, "220.462262 lb")
    }

    func testConvertsDataSizeUnits() async throws {
        let source = CalculatorSource()

        let decimal = await source.search(query: "1 GB to MB")
        let binary = await source.search(query: "1 GiB to MiB")

        XCTAssertEqual(decimal.first?.title, "1000 MB")
        XCTAssertEqual(binary.first?.title, "1024 MiB")
    }

    func testConvertsCelsiusToFahrenheitAndKelvin() async throws {
        let source = CalculatorSource()

        let fahrenheit = await source.search(query: "100 c to f")
        let kelvin = await source.search(query: "100 °C to K")

        XCTAssertEqual(fahrenheit.first?.title, "212 °F")
        XCTAssertEqual(kelvin.first?.title, "373.15 K")
    }

    func testRejectsCurrencyVolumeDurationUnknownAndMissingTargetUnit() async throws {
        let source = CalculatorSource()

        let currencyResults = await source.search(query: "100 usd to cny")
        let volumeResults = await source.search(query: "1 l to ml")
        let durationResults = await source.search(query: "1 h to min")
        let unknownUnitResults = await source.search(query: "100 widgets to kg")
        let missingTargetResults = await source.search(query: "100 cm")

        XCTAssertTrue(currencyResults.isEmpty)
        XCTAssertTrue(volumeResults.isEmpty)
        XCTAssertTrue(durationResults.isEmpty)
        XCTAssertTrue(unknownUnitResults.isEmpty)
        XCTAssertTrue(missingTargetResults.isEmpty)
    }

    @MainActor
    func testSearchServiceExecuteCopiesTextForEnterAction() async throws {
        let service = SearchService(sources: [CalculatorSource()])
        let response = await service.search(query: "40 + 2")
        guard let action = response.results.first?.primaryAction else {
            return XCTFail("Expected calculator result")
        }

        let executeResponse = try await service.execute(action)

        XCTAssertTrue(executeResponse.shouldCloseSearchPanel)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "42")
    }
}
