//
//  LainTSXWebView.swift
//  lain-tsx-ios
//
//  Created by 村石 拓海 on 2024/05/02.
//

import SwiftUI
import WebKit

struct LainTSXWebView: UIViewRepresentable {
    
    let loardUrl: URL = URL(string: "https://3d.laingame.net/#/game")!
    
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: loardUrl)
        uiView.load(request)
    }
}
