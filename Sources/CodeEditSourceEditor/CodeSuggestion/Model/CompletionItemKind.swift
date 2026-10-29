//
//  CompletionItemKind.swift
//  CodeEditSourceEditor
//

import AppKit
import SwiftUI

/// The kind of a completion item, used for presentation and for provider-agnostic mapping.
public enum CompletionItemKind: String, Sendable, Hashable, CaseIterable {
    case keyword
    case type
    case classType
    case structType
    case interface
    case enumType
    case enumCase
    case method
    case property
    case variable
    case constant
    case function
    case initializer
    case module
    case snippet
    case widget
    case event
    case operatorSymbol
    case unknown

    public var systemImageName: String {
        switch self {
        case .keyword: return "k.square"
        case .type: return "t.square"
        case .classType: return "c.square"
        case .structType: return "s.square"
        case .interface: return "i.square"
        case .enumType: return "e.square"
        case .enumCase: return "e.square"
        case .method: return "m.square"
        case .property: return "p.square"
        case .variable: return "v.square"
        case .constant: return "number.square"
        case .function: return "f.square"
        case .initializer: return "i.square"
        case .module: return "shippingbox"
        case .snippet: return "curlybraces.square"
        case .widget: return "square.on.square"
        case .event: return "bolt.square"
        case .operatorSymbol: return "plus.square"
        case .unknown: return "text.alignleft"
        }
    }

    public var defaultColor: NSColor {
        switch self {
        case .keyword: return .systemPink
        case .type, .classType, .structType, .interface, .enumType, .enumCase: return .systemTeal
        case .method, .function, .initializer: return .systemPurple
        case .property, .variable, .constant: return .systemBlue
        case .snippet: return .systemOrange
        case .widget: return .systemIndigo
        case .module: return .systemBrown
        case .event: return .systemYellow
        case .operatorSymbol: return .systemGreen
        case .unknown: return .systemGray
        }
    }
}

public enum CompletionItemIcon {
    public static func image(for kind: CompletionItemKind) -> Image {
        Image(systemName: kind.systemImageName)
    }

    public static func color(for kind: CompletionItemKind) -> Color {
        Color(kind.defaultColor)
    }
}
