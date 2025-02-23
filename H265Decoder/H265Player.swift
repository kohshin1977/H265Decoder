//
//  H265Player.swift
//  H265Decoder
//
//  Created by Kohshin Tokunaga on 2025/02/15.
//

import Foundation
import AVFoundation
import CoreMedia

class H265Player: NSObject, VideoDecoderDelegate {
    
    let displayLayer = AVSampleBufferDisplayLayer()
    private var decoder: H265Decoder?
    
    override init() {
        super.init()
        
        // Initial configuration for the display layer
        displayLayer.videoGravity = .resizeAspect
        
        // Initialize the decoder (delegate = self)
        decoder = H265Decoder(delegate: self)
        
        // For simple playback, set isBaseline to true
        decoder?.isBaseline = true
    }
    
    func startPlayback() {
        // Load the file "cars_320x240.h265"
        guard let url = Bundle.main.url(forResource: "temp2", withExtension: "h265") else {
            print("File not found")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // Set FPS and video size as needed
            let packet = VideoPacket(data: data,
                                     type: .h265,
                                     fps: 30,
                                     videoSize: CGSize(width: 1080, height: 1920))
            
            // Decode as a single packet
            decoder?.decodeOnePacket(packet)
            
        } catch {
            print("Failed to load file: \(error)")
        }
    }
    
    // MARK: - VideoDecoderDelegate
    func decodeOutput(video: CMSampleBuffer) {
        // When decoding is complete, send the output to AVSampleBufferDisplayLayer
        displayLayer.enqueue(video)
    }
    
    func decodeOutput(error: DecodeError) {
        print("Decoding error: \(error)")
    }
}
