//
//  MetalVideoPlayerView.swift
//  H265Decoder
//
//  Created by 徳永功伸 on 2025/02/24.
//

import SwiftUI
import MetalKit

struct MetalVideoPlayerView: UIViewRepresentable {
    
    // コーディネータとして H265Player を返す。H265Player 内でデコードとレンダリングの連携を行う。
    func makeCoordinator() -> H265Player {
        H265Player()
    }
    
    func makeUIView(context: Context) -> MTKView {
        // デフォルトの Metal デバイスで MTKView を作成
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal 対応デバイスがありません")
        }
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0) // 背景を透明に
        
        // NV12 レンダラーを生成し、MTKView の delegate にセット
        let renderer = NV12Renderer(mtkView: mtkView)
        mtkView.delegate = renderer
        
        // H265Player にレンダラーと MTKView への参照を渡す
        let coordinator = context.coordinator
        coordinator.renderer = renderer
        coordinator.mtkView = mtkView
        
        // 再生開始（H.265 のデコードと映像フレームの供給を開始）
        coordinator.startPlayback()
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        // 必要に応じたビュー更新処理（今回は特に処理は不要）
    }
}
