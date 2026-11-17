/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import Foundation

/// The display options that can be set on code blocks.
public struct CodeBlockOptions: Equatable {
    /// The programming language of the code in the block, if given.
    public var language: String?

    /// Whether to insert a button to copy the code block to the reader's clipboard.
    public var copyToClipboard: Bool

    /// Whether to show line numbers alongside the code block.
    public var showLineNumbers: Bool

    /// The character width that the code should wrap at.
    ///
    /// If this value is zero or negative, the code block will not wrap lines.
    public var wrap: Int

    /// The list of which code spans should have additional styling, like highlighting or strikethrough.
    public var lineAnnotations: [LineAnnotation]

    /// A text position used for annotations.
    public struct Position: Equatable, Comparable, Codable {
        public static func < (lhs: CodeBlockOptions.Position, rhs: CodeBlockOptions.Position) -> Bool {
            if lhs.line == rhs.line, let lhsCharacter = lhs.character, let rhsCharacter = rhs.character {
                return lhsCharacter < rhsCharacter
            }
            return lhs.line < rhs.line
        }

        public init(line: Int, character: Int? = nil) {
            self.line = line
            self.character = character
        }

        public var line: Int
        public var character: Int?
    }

    /// An annotated code block span.
    public struct LineAnnotation: Equatable, Codable {
        /// The style of annotation to give this range.
        ///
        /// DocC currently parses and emits the values `highlight` and `strikeout`.
        public var style: String

        /// The line and/or character range to apply this annotation to.
        public var range: Range<Position>

        public init(style: String, range: Range<Position>) {
            self.style = style
            self.range = range
        }
    }

    /// The option names that can be parsed from a code block language string.
    public enum OptionName: String, CaseIterable {
        case _nonFrozenEnum_useDefaultCase

        /// When present, suppress the default "copy to clipboard" button on this code block.
        case nocopy
        /// When paired with a number, indicates the character width at which this block should wrap.
        case wrap
        /// When paired with a list of line numbers or line/character ranges, indicates that the given ranges should be highlighted.
        case highlight
        /// When present, adds a line-number gutter to the code block.
        case showLineNumbers
        /// When paired with a list of line numbers or line/character ranges, indicates that the given ranges should be stricken out.
        case strikeout
        /// Indicates that an unknown option name was given in the original input string.
        case unknown

        init?(caseInsensitive raw: some StringProtocol) {
            self.init(rawValue: raw.lowercased())
        }
    }

    public static var knownOptions: Set<String> {
        Set(OptionName.allCases.map(\.rawValue))
    }

    /// Creates a new parsed code block options by parsing the given language string for option values.
    public init(parsingLanguageString language: String?) {
        let (lang, tokens) = Self.tokenizeLanguageString(language)

        self.language = lang
        self.copyToClipboard = !tokens.contains { $0.name == .nocopy }
        self.showLineNumbers = tokens.contains { $0.name == .showLineNumbers }

        if let wrapString = tokens.first(where: { $0.name == .wrap })?.value,
           let wrapValue = Int(wrapString) {
            self.wrap = wrapValue
        } else {
            self.wrap = 0
        }

        var annotations: [LineAnnotation] = []

        if let highlightString = tokens.first(where: { $0.name == .highlight })?.value {
            let highlightValue = Self.parseCodeBlockOptionsArray(highlightString)
            for line in highlightValue {
                let pos = Position(line: line, character: nil)
                let range = pos..<pos
                annotations.append(LineAnnotation(style: "highlight", range: range))
            }
        }

        if let strikeoutString = tokens.first(where: { $0.name == .strikeout })?.value {
            let strikeoutValue = Self.parseCodeBlockOptionsArray(strikeoutString)
            for line in strikeoutValue {
                let pos = Position(line: line, character: nil)
                let range = pos..<pos
                annotations.append(LineAnnotation(style: "strikeout", range: range))
            }
        }

        self.lineAnnotations = annotations
    }

    /// Creates a new parsed code block options with the given values.
    ///
    /// This initializer can be used to convert from lists of line numbers for the line annotations
    /// into complete ``LineAnnotation`` instances for the final ``CodeBlockOptions`` instance.
    public init(copyToClipboard: Bool, showLineNumbers: Bool = false, wrap: Int, highlight: [Int], strikeout: [Int]) {
        self.copyToClipboard = copyToClipboard
        self.showLineNumbers = showLineNumbers
        self.wrap = wrap

        var annotations: [LineAnnotation] = []
        for line in highlight {
                let pos = Position(line: line, character: nil)
                let range = pos..<pos
                annotations.append(LineAnnotation(style: "highlight", range: range))
        }
        for line in strikeout {
                let pos = Position(line: line, character: nil)
                let range = pos..<pos
                annotations.append(LineAnnotation(style: "strikeout", range: range))
        }
        self.lineAnnotations = annotations
    }

    public init(copyToClipboard: Bool, showLineNumbers: Bool, wrap: Int, lineAnnotations: [LineAnnotation]) {
        self.copyToClipboard = copyToClipboard
        self.showLineNumbers = showLineNumbers
        self.wrap = wrap
        self.lineAnnotations = lineAnnotations
    }

    /// A function that parses array values on code block options from the language line string
    static package func parseCodeBlockOptionsArray(_ value: String?) -> [Int] {
        guard var s = value?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return [] }

        if s.hasPrefix("[") && s.hasSuffix("]") {
            s.removeFirst()
            s.removeLast()
        }

        return s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// A function that parses the language line options on code blocks, returning the language and tokens, an array of OptionName and option values
    static package func tokenizeLanguageString(_ input: String?) -> (lang: String?, tokens: [(name: OptionName, value: String?)]) {
        guard let input else { return (lang: nil, tokens: []) }

        let parts = parseLanguageString(input)
        var tokens: [(OptionName, String?)] = []
        var lang: String? = nil

        for (index, part) in parts.enumerated() {
            if let eq = part.firstIndex(of: "=") {
                let key = part[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                let value = part[part.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if key == "wrap" {
                    tokens.append((.wrap, value))
                } else if key == "highlight" {
                    tokens.append((.highlight, value))
                } else if key == "strikeout" {
                    tokens.append((.strikeout, value))
                } else {
                    tokens.append((.unknown, key))
                }
            } else {
                let key = part.trimmingCharacters(in: .whitespaces).lowercased()
                if key == "nocopy" {
                    tokens.append((.nocopy, nil as String?))
                } else if key == "showlinenumbers" {
                    tokens.append((.showLineNumbers, nil as String?))
                } else if key == "wrap" {
                    tokens.append((.wrap, nil as String?))
                } else if key == "highlight" {
                    tokens.append((.highlight, nil as String?))
                } else if key == "strikeout" {
                    tokens.append((.strikeout, nil as String?))
                } else if index == 0 && !key.contains("[") && !key.contains("]") {
                    lang = key
                } else {
                    tokens.append((.unknown, key))
                }
            }
        }
        return (lang, tokens)
    }

    // helper function for tokenizeLanguageString to parse the language line
    static package func parseLanguageString(_ input: String?) -> [Substring] {

        guard let input else { return [] }
        var parts: [Substring] = []
        var start = input.startIndex
        var i = input.startIndex

        var bracketDepth = 0

        while i < input.endIndex {
            let c = input[i]

            if c == "[" { bracketDepth += 1 }
            else if c == "]" { bracketDepth = max(0, bracketDepth - 1) }
            else if c == "," && bracketDepth == 0 {
                let seq = input[start..<i]
                if !seq.isEmpty {
                    parts.append(seq)
                }
                input.formIndex(after: &i)
                start = i
                continue
            }
            input.formIndex(after: &i)
        }
        let tail = input[start..<input.endIndex]
        if !tail.isEmpty {
            parts.append(tail)
        }

        return parts
    }
}
