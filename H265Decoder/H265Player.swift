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
    
    // Metal 用レンダラーと MTKView への参照
    var renderer: NV12Renderer?
    var mtkView: MTKView?
    private var decoder: H265Decoder?
    
    // デコードされたフレームを順次再生するためのキュー
    private var frameQueue: [CVPixelBuffer] = []
    
    // CADisplayLink を使って30fpsでフレームを表示する
    private var displayLink: CADisplayLink?
    
    override init() {
        super.init()
        
        // H.265 デコーダーの初期化（delegate = self）
        decoder = H265Decoder(delegate: self)
        // Baseline 再生（即時表示）モードを無効にして、キュー管理に任せる
        decoder?.isBaseline = false
        
        // CADisplayLink の設定（30fps）
        displayLink = CADisplayLink(target: self, selector: #selector(displayNextFrame))
        displayLink?.preferredFramesPerSecond = 30
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func startPlayback() {
        // ファイル "temp2.h265" を読み込む
        guard let url = Bundle.main.url(forResource: "temp2", withExtension: "h265") else {
            print("File not found")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // FPS や映像サイズは適宜指定
            let packet = VideoPacket(data: data,
                                     type: .h265,
                                     fps: 30,
                                     videoSize: CGSize(width: 1080, height: 1920))
            
            // パケットを1つとしてデコード
            decoder?.decodeOnePacket(packet)
            
        } catch {
            print("Failed to load file: \(error)")
        }
    }
    
    // MARK: - VideoDecoderDelegate
    func decodeOutput(video: CMSampleBuffer) {
        // デコード後の CMSampleBuffer から CVPixelBuffer を取得
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(video) else { return }
        // フレームをキューに追加（順次再生のため）
        frameQueue.append(pixelBuffer)
    }
    
    func decodeOutput(error: DecodeError) {
        print("Decoding error: \(error)")
    }
    
    // CADisplayLink のコールバック：30fpsで呼ばれる
    @objc private func displayNextFrame() {
        guard !frameQueue.isEmpty else { return }
        // キューから先頭のフレームを取り出す
        let nextFrame = frameQueue.removeFirst()
        // レンダラーにフレームをセットする
        renderer?.currentPixelBuffer = nextFrame
        // MTKView を再描画（draw() が呼ばれる）
        mtkView?.draw()
    }
    
    deinit {
        displayLink?.invalidate()
    }
}
