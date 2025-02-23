//
//  NV12Renderer.swift
//  H265Decoder
//
//  Created by 徳永功伸 on 2025/02/24.
//


import UIKit
import Metal
import MetalKit
import CoreVideo

class NV12Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var textureCache: CVMetalTextureCache?
    
    // The current NV12 image frame to render (set by H265Player).
    var currentPixelBuffer: CVPixelBuffer?
    
    init(mtkView: MTKView) {
        self.device = mtkView.device!
        self.commandQueue = device.makeCommandQueue()!
        super.init()
        
        // Create a Metal texture cache for converting CVPixelBuffer planes to textures.
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        // Load the default library and compile shaders.
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "vertexPassThrough")
        let fragmentFunction = library.makeFunction(name: "nv12Fragment")
        
        // Set up the render pipeline.
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "NV12 Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    func draw(in view: MTKView) {
        guard let pixelBuffer = currentPixelBuffer,
              let textureCache = textureCache,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        // Create texture for Y plane.
        var yTextureRef: CVMetalTexture?
        let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  textureCache,
                                                  pixelBuffer,
                                                  nil,
                                                  .r8Unorm,
                                                  yWidth,
                                                  yHeight,
                                                  0,
                                                  &yTextureRef)
        
        // Create texture for UV plane.
        var uvTextureRef: CVMetalTexture?
        let uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  textureCache,
                                                  pixelBuffer,
                                                  nil,
                                                  .rg8Unorm,
                                                  uvWidth,
                                                  uvHeight,
                                                  1,
                                                  &uvTextureRef)
        
        guard let yTexture = CVMetalTextureGetTexture(yTextureRef!),
              let uvTexture = CVMetalTextureGetTexture(uvTextureRef!) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return
        }
        
        // Begin a new command buffer and render pass.
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Pass the Y and UV textures to the fragment shader.
        renderEncoder.setFragmentTexture(yTexture, index: 0)
        renderEncoder.setFragmentTexture(uvTexture, index: 1)
        
        // Create and set a sampler.
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        let samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // Draw a full-screen quad.
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // サイズ変更時の処理（必要に応じて実装）
    }
}
