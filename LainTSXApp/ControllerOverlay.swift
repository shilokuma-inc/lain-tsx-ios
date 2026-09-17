//
//  ControllerOverlay.swift
//  LainTSXApp
//

import SwiftUI
import UIKit

/// ゲーム画面に重ねる仮想コントローラ。
struct ControllerOverlay: View {
    @ObservedObject var controller: WebGameController

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        shoulderButton(.l2)
                        shoulderButton(.l1)
                    }
                    DirectionPad(size: Metrics.padSize) { keys in
                        controller.setDirections(keys)
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    systemButton(.select)
                    systemButton(.start)
                }
                .padding(.bottom, Metrics.padSize * 0.2)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 14) {
                    HStack(spacing: 8) {
                        shoulderButton(.r1)
                        shoulderButton(.r2)
                    }
                    FaceButtonCluster(size: Metrics.padSize) { key, isPressed in
                        isPressed ? controller.press(key) : controller.release(key)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onDisappear { controller.releaseAll() }
    }

    private func shoulderButton(_ key: PSXKey) -> some View {
        PressableButton(key: key) { isPressed in
            isPressed ? controller.press(key) : controller.release(key)
        } content: { isPressed in
            Text(key.label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 52, height: 30)
                .background(ControllerStyle.background(isPressed: isPressed, in: RoundedRectangle(cornerRadius: 6)))
        }
    }

    private func systemButton(_ key: PSXKey) -> some View {
        PressableButton(key: key) { isPressed in
            isPressed ? controller.press(key) : controller.release(key)
        } content: { isPressed in
            Text(key.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 78, height: 26)
                .background(ControllerStyle.background(isPressed: isPressed, in: Capsule()))
        }
    }
}

// MARK: - 十字キー

/// タッチ位置から方向を決める十字キー。指を滑らせたまま方向を変えられる。
private struct DirectionPad: View {
    let size: CGFloat
    let onChange: (Set<PSXKey>) -> Void

    @State private var active: Set<PSXKey> = []

    var body: some View {
        ZStack {
            CrossShape()
                .fill(ControllerStyle.fill)
            CrossShape()
                .stroke(ControllerStyle.line, lineWidth: 1.5)

            ForEach(PSXKey.directions, id: \.self) { key in
                Text(key.label)
                    .font(.system(size: size * 0.11, weight: .bold))
                    .foregroundStyle(active.contains(key) ? ControllerStyle.accent : ControllerStyle.line)
                    .offset(offset(for: key))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { update(with: $0.location) }
                .onEnded { _ in update(with: nil) }
        )
        .accessibilityElement()
        .accessibilityLabel("十字キー")
    }

    private func offset(for key: PSXKey) -> CGSize {
        let distance = size * 0.34
        switch key {
        case .up: return CGSize(width: 0, height: -distance)
        case .down: return CGSize(width: 0, height: distance)
        case .left: return CGSize(width: -distance, height: 0)
        default: return CGSize(width: distance, height: 0)
        }
    }

    private func update(with location: CGPoint?) {
        let keys = resolveKeys(at: location)
        guard keys != active else { return }
        active = keys
        onChange(keys)
        if !keys.isEmpty {
            Haptics.tap()
        }
    }

    private func resolveKeys(at location: CGPoint?) -> Set<PSXKey> {
        guard let location else { return [] }
        let dx = location.x - size / 2
        let dy = location.y - size / 2
        guard hypot(dx, dy) > size * 0.15 else { return [] }

        // 斜め入力は lainTSX 側で使わないため、優勢な軸だけを拾う
        if abs(dx) > abs(dy) {
            return [dx > 0 ? .right : .left]
        } else {
            return [dy > 0 ? .down : .up]
        }
    }
}

/// 十字キーの輪郭。
private struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let a = rect.width / 3
        let b = rect.width / 3 * 2
        let h = rect.height
        let ha = h / 3
        let hb = h / 3 * 2

        var path = Path()
        path.addLines([
            CGPoint(x: a, y: 0),
            CGPoint(x: b, y: 0),
            CGPoint(x: b, y: ha),
            CGPoint(x: rect.width, y: ha),
            CGPoint(x: rect.width, y: hb),
            CGPoint(x: b, y: hb),
            CGPoint(x: b, y: h),
            CGPoint(x: a, y: h),
            CGPoint(x: a, y: hb),
            CGPoint(x: 0, y: hb),
            CGPoint(x: 0, y: ha),
            CGPoint(x: a, y: ha)
        ])
        path.closeSubpath()
        return path
    }
}

// MARK: - ○ ✕ △ □

private struct FaceButtonCluster: View {
    let size: CGFloat
    let onChange: (PSXKey, Bool) -> Void

    var body: some View {
        ZStack {
            button(.triangle, offset: CGSize(width: 0, height: -size * 0.32))
            button(.square, offset: CGSize(width: -size * 0.32, height: 0))
            button(.circle, offset: CGSize(width: size * 0.32, height: 0))
            button(.cross, offset: CGSize(width: 0, height: size * 0.32))
        }
        .frame(width: size, height: size)
    }

    private func button(_ key: PSXKey, offset: CGSize) -> some View {
        PressableButton(key: key) { isPressed in
            onChange(key, isPressed)
        } content: { isPressed in
            Text(key.label)
                .font(.system(size: size * 0.2, weight: .medium))
                .frame(width: size * 0.36, height: size * 0.36)
                .background(ControllerStyle.background(isPressed: isPressed, in: Circle()))
        }
        .offset(offset)
    }
}

// MARK: - 共通部品

/// 押した瞬間に keydown、離した瞬間に keyup を送るボタン。
/// `DragGesture` を使うことで、複数のボタンを同時に押せるようにしている。
private struct PressableButton<Content: View>: View {
    let key: PSXKey
    let onChange: (Bool) -> Void
    @ViewBuilder let content: (Bool) -> Content

    @State private var isPressed = false

    var body: some View {
        content(isPressed)
            .foregroundStyle(isPressed ? ControllerStyle.accent : ControllerStyle.line)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onChange(true)
                        Haptics.tap()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onChange(false)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(key.accessibilityLabel)
    }
}

enum ControllerStyle {
    static let fill = Color.black.opacity(0.35)
    static let line = Color(red: 0.62, green: 0.78, blue: 0.82).opacity(0.85)
    static let accent = Color(red: 0.55, green: 0.95, blue: 1.0)

    static func background<S: Shape>(isPressed: Bool, in shape: S) -> some View {
        shape
            .fill(isPressed ? accent.opacity(0.22) : fill)
            .overlay(shape.stroke(isPressed ? accent : line, lineWidth: 1.5))
    }
}

private enum Metrics {
    /// 十字キーとボタン群の一辺。iPad では少し大きくする。
    static var padSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 180 : 132
    }
}

private enum Haptics {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func tap() {
        generator.impactOccurred(intensity: 0.6)
    }
}

private extension PSXKey {
    static let directions: [PSXKey] = [.up, .down, .left, .right]
}
