// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Attributed {
struct TextAttributes {
    var font: PlatformFont?
    var foregroundColor: PlatformColor?
    var backgroundColor: PlatformColor?
    var kern: CGFloat?
    var baselineOffset: CGFloat?
    var underlineStyle: NSUnderlineStyle?
    var underlineColor: PlatformColor?

    public init() {}

    static var rootDefaults: Self {
        var result = Self()
        #if canImport(UIKit)
        result.foregroundColor = .label
        #elseif canImport(AppKit)
        result.foregroundColor = .labelColor
        #endif
        return result
    }

    func merging(_ child: Self) -> Self {
        var result = self
        result.font = child.font ?? font
        result.foregroundColor = child.foregroundColor ?? foregroundColor
        result.backgroundColor = child.backgroundColor ?? backgroundColor
        result.kern = child.kern ?? kern
        result.baselineOffset = child.baselineOffset ?? baselineOffset
        result.underlineStyle = child.underlineStyle ?? underlineStyle
        result.underlineColor = child.underlineColor ?? underlineColor
        return result
    }

    var nsAttributes: [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [:]

        if let font {
            result[.font] = font
        }

        if let foregroundColor {
            result[.foregroundColor] = foregroundColor
        }

        if let backgroundColor {
            result[.backgroundColor] = backgroundColor
        }

        if let kern {
            result[.kern] = kern
        }

        if let baselineOffset {
            result[.baselineOffset] = baselineOffset
        }

        if let underlineStyle {
            result[.underlineStyle] = underlineStyle.rawValue
        }

        if let underlineColor {
            result[.underlineColor] = underlineColor
        }

        return result
    }
}

struct ParagraphAttributes {
    var alignment: NSTextAlignment?
    var baseWritingDirection: NSWritingDirection?
    var lineSpacing: CGFloat?
    var paragraphSpacing: CGFloat?

    public init() {}

    func merging(_ child: Self) -> Self {
        var result = self
        result.alignment = child.alignment ?? alignment
        result.baseWritingDirection = child.baseWritingDirection ?? baseWritingDirection
        result.lineSpacing = child.lineSpacing ?? lineSpacing
        result.paragraphSpacing = child.paragraphSpacing ?? paragraphSpacing
        return result
    }

    func makeNSParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()

        if let alignment {
            style.alignment = alignment
        }

        if let baseWritingDirection {
            style.baseWritingDirection = baseWritingDirection
        }

        if let lineSpacing {
            style.lineSpacing = lineSpacing
        }

        if let paragraphSpacing {
            style.paragraphSpacing = paragraphSpacing
        }

        return style
    }
}
}
