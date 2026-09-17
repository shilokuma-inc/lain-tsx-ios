//
//  ContentView.swift
//  LainTSXApp
//
//  Created by 村石 拓海 on 2024/05/02.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var controller = WebGameController()
    @State private var isControllerVisible = true

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GameWebView(controller: controller)
                .ignoresSafeArea()

            if controller.isLoading {
                loadingView
            }

            if let loadError = controller.loadError {
                errorView(message: loadError)
            }

            if isControllerVisible {
                ControllerOverlay(controller: controller)
            }

            toggleButton
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, newPhase in
            // バックグラウンドに回ると keyup を送れないため、押しっぱなしの状態を解除する
            if newPhase != .active {
                controller.releaseAll()
            }
        }
    }

    /// ページ自体が読み込まれるまでの表示。以降はゲーム側の Loading 表示に引き継ぐ。
    private var loadingView: some View {
        ProgressView()
            .tint(ControllerStyle.accent)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Text("読み込みに失敗しました")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(ControllerStyle.line)
            Button("再読み込み") {
                controller.reload()
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .tint(ControllerStyle.accent)
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .padding(32)
    }

    private var toggleButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    if isControllerVisible {
                        controller.releaseAll()
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isControllerVisible.toggle()
                    }
                } label: {
                    Image(systemName: isControllerVisible ? "gamecontroller.fill" : "gamecontroller")
                        .font(.system(size: 15))
                        .foregroundStyle(ControllerStyle.line)
                        .frame(width: 38, height: 38)
                        .background(ControllerStyle.background(isPressed: false, in: Circle()))
                }
                .accessibilityLabel(isControllerVisible ? "コントローラを隠す" : "コントローラを表示")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

#Preview {
    ContentView()
}
