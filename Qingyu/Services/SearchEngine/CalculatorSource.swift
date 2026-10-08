import AppKit
import Foundation
import os.log

/// Assistant MVP calculator and unit-conversion provider.
///
/// Scope is intentionally narrow and safe:
/// - Supports basic arithmetic with +, -, *, /, parentheses, and decimals.
/// - Supports unit conversions for length, weight, data size, and temperature.
/// - Does not support currency, variables, functions, history, or arbitrary expression execution.
/// - Uses a handwritten parser rather than NSExpression or any executable expression engine.
final class CalculatorSource: SearchSource {
    let id: SearchSourceID = .calculator
    let displayName = "Calculator"
    let isEnabledInSearch = true

    private let logger = Logger.search

    private static let resultFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 10
        return formatter
    }()

    // MARK: - New Assistant MVP SearchSource

    func canSearch(query: String) -> Bool {
        parse(query) != nil
    }

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let request = parse(trimmed), let result = try? evaluate(request), result.value.isFinite else {
            return []
        }

        return [SearchResult(
            id: SearchResultID(rawValue: "calculator:\(stableIDComponent(for: trimmed))"),
            sourceID: .calculator,
            title: result.displayText,
            subtitle: result.subtitle,
            icon: .systemSymbol(result.iconSystemName),
            typeLabel: result.typeLabel,
            baseScore: SourcePriority.calculator,
            matchScore: 30,
            usageScore: 0,
            primaryAction: .copyText(result.copyText),
            secondaryActions: []
        )]
    }

    // MARK: - Public parser/evaluator API from architecture_api.md

    func parse(_ query: String) -> CalculationRequest? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let conversion = UnitConverter.parse(trimmed) {
            return .unitConversion(conversion)
        }

        guard Self.looksLikeExpression(trimmed) else { return nil }
        return .expression(trimmed)
    }

    func evaluate(_ request: CalculationRequest) throws -> CalculationResult {
        switch request {
        case .expression(let expression):
            let value = try ArithmeticExpressionParser(expression: expression).parse()
            guard value.isFinite else { throw CalculationError.nonFiniteResult }
            let formatted = Self.format(value, maximumFractionDigits: 10)
            return CalculationResult(
                displayText: "= \(formatted)",
                copyText: formatted,
                subtitle: expression,
                value: value,
                typeLabel: "Calculator",
                iconSystemName: "function"
            )
        case .unitConversion(let conversion):
            let value = try UnitConverter.convert(conversion)
            guard value.isFinite else { throw CalculationError.nonFiniteResult }
            let formatted = Self.format(value, maximumFractionDigits: conversion.outputMaximumFractionDigits)
            let copy = "\(formatted) \(conversion.target.displaySymbol)"
            return CalculationResult(
                displayText: copy,
                copyText: copy,
                subtitle: "\(Self.format(conversion.value, maximumFractionDigits: 10)) \(conversion.source.displaySymbol) → \(conversion.target.displaySymbol)",
                value: value,
                typeLabel: "Convert",
                iconSystemName: "arrow.left.arrow.right"
            )
        }
    }

    // MARK: - Helpers

    static func looksLikeExpression(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return false }

        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() \t\n\r")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

        let operatorSet = CharacterSet(charactersIn: "+-*/")
        guard let firstOperator = trimmed.rangeOfCharacter(from: operatorSet) else { return false }

        if firstOperator.lowerBound == trimmed.startIndex {
            let afterFirst = trimmed.index(after: trimmed.startIndex)
            guard afterFirst < trimmed.endIndex else { return false }
            return trimmed[afterFirst...].rangeOfCharacter(from: operatorSet) != nil
        }
        return true
    }

    static func format(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func stableIDComponent(for query: String) -> String {
        query.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }
}

// MARK: - Calculator domain models

enum CalculationRequest: Hashable {
    case expression(String)
    case unitConversion(UnitConversionRequest)
}

struct CalculationResult: Hashable {
    let displayText: String
    let copyText: String
    let subtitle: String?
    let value: Double
    let typeLabel: String
    let iconSystemName: String
}

enum CalculationError: Error, Equatable {
    case invalidExpression
    case divisionByZero
    case nonFiniteResult
    case unsupportedUnit
    case incompatibleUnits
}

// MARK: - Safe recursive-descent arithmetic parser

private final class ArithmeticExpressionParser {
    private let characters: [Character]
    private var index = 0

    init(expression: String) {
        self.characters = Array(expression)
    }

    func parse() throws -> Double {
        let value = try parseExpression()
        skipWhitespace()
        guard index == characters.count else { throw CalculationError.invalidExpression }
        guard value.isFinite else { throw CalculationError.nonFiniteResult }
        return value
    }

    private func parseExpression() throws -> Double {
        var value = try parseTerm()
        while true {
            skipWhitespace()
            if consume("+") {
                value += try parseTerm()
            } else if consume("-") {
                value -= try parseTerm()
            } else {
                return value
            }
            guard value.isFinite else { throw CalculationError.nonFiniteResult }
        }
    }

    private func parseTerm() throws -> Double {
        var value = try parseFactor()
        while true {
            skipWhitespace()
            if consume("*") {
                value *= try parseFactor()
            } else if consume("/") {
                let divisor = try parseFactor()
                guard divisor != 0 else { throw CalculationError.divisionByZero }
                value /= divisor
            } else {
                return value
            }
            guard value.isFinite else { throw CalculationError.nonFiniteResult }
        }
    }

    private func parseFactor() throws -> Double {
        skipWhitespace()
        if consume("+") { return try parseFactor() }
        if consume("-") { return -(try parseFactor()) }

        if consume("(") {
            let value = try parseExpression()
            skipWhitespace()
            guard consume(")") else { throw CalculationError.invalidExpression }
            return value
        }

        return try parseNumber()
    }

    private func parseNumber() throws -> Double {
        skipWhitespace()
        let start = index
        var hasDigit = false
        var hasDecimalPoint = false

        while index < characters.count {
            let character = characters[index]
            if character >= "0" && character <= "9" {
                hasDigit = true
                index += 1
            } else if character == "." && !hasDecimalPoint {
                hasDecimalPoint = true
                index += 1
            } else {
                break
            }
        }

        guard hasDigit else { throw CalculationError.invalidExpression }
        let token = String(characters[start..<index])
        guard let value = Double(token), value.isFinite else { throw CalculationError.invalidExpression }
        return value
    }

    private func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }

    private func consume(_ character: Character) -> Bool {
        guard index < characters.count, characters[index] == character else { return false }
        index += 1
        return true
    }
}

// MARK: - Unit conversion

struct UnitConversionRequest: Hashable {
    let value: Double
    let source: CalculatorUnit
    let target: CalculatorUnit

    var outputMaximumFractionDigits: Int {
        switch target.category {
        case .dataSize: return 4
        case .temperature: return 4
        case .length, .weight: return 6
        }
    }
}

enum CalculatorUnitCategory: Hashable {
    case length
    case weight
    case dataSize
    case temperature
}

struct CalculatorUnit: Hashable {
    let key: String
    let displaySymbol: String
    let category: CalculatorUnitCategory
    let toBase: (Double) -> Double
    let fromBase: (Double) -> Double

    static func == (lhs: CalculatorUnit, rhs: CalculatorUnit) -> Bool {
        lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

private enum UnitConverter {
    private static let conversionRegex: NSRegularExpression? = {
        // Supports "10 cm to inch", "10 cm in inch", and "10 cm -> inch".
        // A target unit is required so CalculatorSource returns one precise result.
        // The pattern is a compile-time constant; on the impossible compile failure
        // we log and disable unit conversion rather than force-try (v1.2 robustness pass).
        do {
            return try NSRegularExpression(pattern: #"^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*([a-zA-Z°]+)\s*(?:to|in|->)\s*([a-zA-Z°]+)\s*$"#, options: [.caseInsensitive])
        } catch {
            Logger.app.error("Failed to compile unit conversion regex: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    static func parse(_ input: String) -> UnitConversionRequest? {
        guard let conversionRegex else { return nil }
        let range = NSRange(input.startIndex..., in: input)
        guard let match = conversionRegex.firstMatch(in: input, options: [], range: range), match.numberOfRanges == 4,
              let valueRange = Range(match.range(at: 1), in: input),
              let sourceRange = Range(match.range(at: 2), in: input),
              let targetRange = Range(match.range(at: 3), in: input),
              let value = Double(input[valueRange]), value.isFinite else {
            return nil
        }

        let sourceToken = normalizeUnitToken(String(input[sourceRange]))
        let targetToken = normalizeUnitToken(String(input[targetRange]))
        guard let source = unit(for: sourceToken), let target = unit(for: targetToken), source.category == target.category else {
            return nil
        }
        return UnitConversionRequest(value: value, source: source, target: target)
    }

    static func convert(_ request: UnitConversionRequest) throws -> Double {
        guard request.source.category == request.target.category else { throw CalculationError.incompatibleUnits }
        let baseValue = request.source.toBase(request.value)
        let converted = request.target.fromBase(baseValue)
        guard converted.isFinite else { throw CalculationError.nonFiniteResult }
        return converted
    }

    private static func normalizeUnitToken(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func unit(for token: String) -> CalculatorUnit? {
        unitTable[token]
    }

    private static let unitTable: [String: CalculatorUnit] = {
        var table: [String: CalculatorUnit] = [:]
        func add(_ aliases: [String], symbol: String, category: CalculatorUnitCategory, toBase: @escaping (Double) -> Double, fromBase: @escaping (Double) -> Double) {
            let unit = CalculatorUnit(key: aliases[0], displaySymbol: symbol, category: category, toBase: toBase, fromBase: fromBase)
            for alias in aliases {
                table[alias] = unit
            }
        }

        // Length base: meter.
        add(["mm", "millimeter", "millimeters"], symbol: "mm", category: .length, toBase: { $0 / 1000 }, fromBase: { $0 * 1000 })
        add(["cm", "centimeter", "centimeters"], symbol: "cm", category: .length, toBase: { $0 / 100 }, fromBase: { $0 * 100 })
        add(["m", "meter", "meters", "metre", "metres"], symbol: "m", category: .length, toBase: { $0 }, fromBase: { $0 })
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], symbol: "km", category: .length, toBase: { $0 * 1000 }, fromBase: { $0 / 1000 })
        add(["in", "inch", "inches"], symbol: "in", category: .length, toBase: { $0 * 0.0254 }, fromBase: { $0 / 0.0254 })
        add(["ft", "foot", "feet"], symbol: "ft", category: .length, toBase: { $0 * 0.3048 }, fromBase: { $0 / 0.3048 })
        add(["yd", "yard", "yards"], symbol: "yd", category: .length, toBase: { $0 * 0.9144 }, fromBase: { $0 / 0.9144 })
        add(["mi", "mile", "miles"], symbol: "mi", category: .length, toBase: { $0 * 1609.344 }, fromBase: { $0 / 1609.344 })

        // Weight base: kilogram.
        add(["mg", "milligram", "milligrams"], symbol: "mg", category: .weight, toBase: { $0 / 1_000_000 }, fromBase: { $0 * 1_000_000 })
        add(["g", "gram", "grams"], symbol: "g", category: .weight, toBase: { $0 / 1000 }, fromBase: { $0 * 1000 })
        add(["kg", "kilogram", "kilograms"], symbol: "kg", category: .weight, toBase: { $0 }, fromBase: { $0 })
        add(["lb", "lbs", "pound", "pounds"], symbol: "lb", category: .weight, toBase: { $0 * 0.45359237 }, fromBase: { $0 / 0.45359237 })
        add(["oz", "ounce", "ounces"], symbol: "oz", category: .weight, toBase: { $0 * 0.028349523125 }, fromBase: { $0 / 0.028349523125 })
        add(["t", "ton", "tons", "tonne", "tonnes"], symbol: "t", category: .weight, toBase: { $0 * 1000 }, fromBase: { $0 / 1000 })

        // Data size base: byte. Binary units follow common computer-use semantics.
        add(["b", "byte", "bytes"], symbol: "B", category: .dataSize, toBase: { $0 }, fromBase: { $0 })
        add(["kb", "kilobyte", "kilobytes"], symbol: "KB", category: .dataSize, toBase: { $0 * 1000 }, fromBase: { $0 / 1000 })
        add(["mb", "megabyte", "megabytes"], symbol: "MB", category: .dataSize, toBase: { $0 * 1000 * 1000 }, fromBase: { $0 / (1000 * 1000) })
        add(["gb", "gigabyte", "gigabytes"], symbol: "GB", category: .dataSize, toBase: { $0 * 1000 * 1000 * 1000 }, fromBase: { $0 / (1000 * 1000 * 1000) })
        add(["tb", "terabyte", "terabytes"], symbol: "TB", category: .dataSize, toBase: { $0 * 1000 * 1000 * 1000 * 1000 }, fromBase: { $0 / (1000 * 1000 * 1000 * 1000) })
        add(["kib", "kibibyte", "kibibytes"], symbol: "KiB", category: .dataSize, toBase: { $0 * 1024 }, fromBase: { $0 / 1024 })
        add(["mib", "mebibyte", "mebibytes"], symbol: "MiB", category: .dataSize, toBase: { $0 * 1024 * 1024 }, fromBase: { $0 / (1024 * 1024) })
        add(["gib", "gibibyte", "gibibytes"], symbol: "GiB", category: .dataSize, toBase: { $0 * 1024 * 1024 * 1024 }, fromBase: { $0 / (1024 * 1024 * 1024) })
        add(["tib", "tebibyte", "tebibytes"], symbol: "TiB", category: .dataSize, toBase: { $0 * 1024 * 1024 * 1024 * 1024 }, fromBase: { $0 / (1024 * 1024 * 1024 * 1024) })

        // Temperature base: Celsius.
        add(["c", "°c", "celsius"], symbol: "°C", category: .temperature, toBase: { $0 }, fromBase: { $0 })
        add(["f", "°f", "fahrenheit"], symbol: "°F", category: .temperature, toBase: { ($0 - 32) * 5 / 9 }, fromBase: { $0 * 9 / 5 + 32 })
        add(["k", "kelvin"], symbol: "K", category: .temperature, toBase: { $0 - 273.15 }, fromBase: { $0 + 273.15 })

        return table
    }()
}

