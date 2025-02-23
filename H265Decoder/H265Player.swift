//
//  H265Player.swift
//  H265Decoder
//
//  Created by Kohshin Tokunaga on 2025/02/15.
//

import Foundation
import AVFoundation
import CoreMedia
import MetalKit

class H265Player: NSObject, VideoDecoderDelegate {
    
    // Instead of a display layer, use the Metal renderer.
    var renderer: NV12Renderer?
    var mtkView: MTKView?
    private var decoder: H265Decoder?
    
    override init() {
        super.init()
        
        // Initialize the H.265 decoder with self as delegate.
        decoder = H265Decoder(delegate: self)
        
        // For simple (baseline) playback.
        decoder?.isBaseline = true
    }
    
    func startPlayback() {
        // Load the file "temp2.h265"
        guard let url = Bundle.main.url(forResource: "temp2", withExtension: "h265") else {
            print("File not found")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // Set FPS and video size as needed.
            let packet = VideoPacket(data: data,
                                     type: .h265,
                                     fps: 30,
                                     videoSize: CGSize(width: 1080, height: 1920))
            
            // Decode the entire packet.
            decoder?.decodeOnePacket(packet)
            
        } catch {
            print("Failed to load file: \(error)")
        }
    }
    
    // MARK: - VideoDecoderDelegate
    func decodeOutput(video: CMSampleBuffer) {
        // Extract the CVPixelBuffer from the sample buffer.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(video) else { return }
        
        // Pass the pixel buffer to the Metal renderer.
        renderer?.currentPixelBuffer = pixelBuffer
    }
    
    func decodeOutput(error: DecodeError) {
        print("Decoding error: \(error)")
    }
}
