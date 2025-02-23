//
//  ContentView.swift
//  H265Decoder
//
//  Created by Kohshin Tokunaga on 2025/02/15.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("H.265 Player (temp.h265)")
                .font(.headline)
            MetalVideoPlayerView()
            .frame(width: 360, height: 640) // Adjust or make it responsive for iOS
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
