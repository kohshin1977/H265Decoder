//
//  VideoPlayerView.swift
//  H265Decoder
//
//  Created by Kohshin Tokunaga on 2025/02/15.
//

import SwiftUI
import AVFoundation

struct VideoPlayerView: UIViewRepresentable {
    
    // Return an H265Player as the coordinator, and start playback there.
    func makeCoordinator() -> H265Player {
        H265Player()
    }
    
    func makeUIView(context: Context) -> UIView {
        let uiView = UIView(frame: .zero)
        
        // Base layer for attaching sublayers
        uiView.backgroundColor = .black // Screen background color (for iOS)
        
        // Create the display layer and add it to uiView.layer
        let displayLayer = context.coordinator.displayLayer
        displayLayer.frame = uiView.bounds
        displayLayer.backgroundColor = UIColor.clear.cgColor
        
        uiView.layer.addSublayer(displayLayer)
        
        // Start playback
        context.coordinator.startPlayback()
        
        return uiView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Reset the frame of the AVSampleBufferDisplayLayer when the view's size changes.
        let displayLayer = context.coordinator.displayLayer
        displayLayer.frame = uiView.layer.bounds
        
        // Optionally update the layer's background color, etc.
        uiView.backgroundColor = .black
        displayLayer.backgroundColor = UIColor.clear.cgColor
        
        // Flush transactions if necessary
        CATransaction.flush()
    }
}
