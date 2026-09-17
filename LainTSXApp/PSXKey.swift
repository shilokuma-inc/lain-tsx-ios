//
//  PSXKey.swift
//  LainTSXApp
//

import Foundation

/// lainTSX のデフォルトキーバインドに対応する PSX コントローラのキー。
///
/// `rawValue` は lainTSX 側が参照する `KeyboardEvent.key` の値そのもの。
/// lainTSX は `event.key.toLowerCase()` でマッピングを引くため、英字は小文字で持つ。
enum PSXKey: String, CaseIterable {
    case up = "ArrowUp"
    case down = "ArrowDown"
    case left = "ArrowLeft"
    case right = "ArrowRight"
    case circle = "x"
    case cross = "z"
    case triangle = "d"
    case square = "s"
    case l1 = "w"
    case l2 = "e"
    case r1 = "r"
    case r2 = "q"
    case start = "v"
    case select = "c"

    /// `KeyboardEvent.code` の値。lainTSX は参照しないが、実キーボードの入力に近づけておく。
    var code: String {
        switch self {
        case .up, .down, .left, .right:
            return rawValue
        default:
            return "Key\(rawValue.uppercased())"
        }
    }

    /// ボタンに表示するラベル。
    var label: String {
        switch self {
        case .up: return "▲"
        case .down: return "▼"
        case .left: return "◀"
        case .right: return "▶"
        case .circle: return "○"
        case .cross: return "✕"
        case .triangle: return "△"
        case .square: return "□"
        case .l1: return "L1"
        case .l2: return "L2"
        case .r1: return "R1"
        case .r2: return "R2"
        case .start: return "START"
        case .select: return "SELECT"
        }
    }

    /// VoiceOver 用の読み上げ名。
    var accessibilityLabel: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        case .circle: return "まる"
        case .cross: return "ばつ"
        case .triangle: return "さんかく"
        case .square: return "しかく"
        default: return label
        }
    }
}
