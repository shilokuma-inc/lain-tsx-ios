//
//  ContentView.swift
//  lain-tsx-ios
//
//  Created by 村石 拓海 on 2024/05/02.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            LainTSXWebView()
                .frame(width: 800, height: 600)
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
