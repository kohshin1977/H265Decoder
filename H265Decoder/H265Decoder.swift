//
//  H265Decoder.swift
//  H265Decoder
//
//  Created by Kohshin Tokunaga on 2025/02/15.
//
import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia
import CoreVideo

public enum EncodeType {
    case h264
    case h265
}

public struct VideoPacket {
    public let data: Data
    public let type: EncodeType
    public let fps: Int
    public let videoSize: CGSize
    
    public var bufferSize: Int {
        data.count
    }
    
    public init(data: Data, type: EncodeType, fps: Int, videoSize: CGSize) {
        self.data = data
        self.type = type
        self.fps = fps
        self.videoSize = videoSize
    }
}

public enum DecodeError : Error, CustomStringConvertible {
    
    case notFoundVpsOrSpsOrPps
    case pixelBufferCreate(CVReturn)
    case blockBufferCreateWithMemoryBlock(OSStatus)
    case sampleBufferCreateReady(OSStatus)
    case decompressionSessionDecodeFrame(OSStatus)
    case decompressionOutputCallback(OSStatus)
    case videoFormatDescriptionCreateFromH264ParameterSets(OSStatus)
    case videoFormatDescriptionCreateFromHEVCParameterSets(OSStatus)
    case decompressionSessionCreate(OSStatus)
    case videoFormatDescriptionCreateForImageBuffer(OSStatus)
    case sampleBufferCreateForImageBuffer(OSStatus)
    
    public var description : String {
        switch self {
        case .notFoundVpsOrSpsOrPps:
            return "DecodeError.notFoundVpsOrSpsOrPps"
        case .pixelBufferCreate(let ret):
            return "DecodeError.pixelBufferCreate(\(ret))"
        case .blockBufferCreateWithMemoryBlock(let status):
            return "DecodeError.blockBufferCreateWithMemoryBlock(\(status))"
        case .sampleBufferCreateReady(let status):
            return "DecodeError.sampleBufferCreateReady(\(status))"
        case .decompressionSessionDecodeFrame(let status):
            return "DecodeError.decompressionSessionDecodeFrame(\(status))"
        case .decompressionOutputCallback(let status):
            return "DecodeError.decompressionOutputCallback(\(status))"
        case .videoFormatDescriptionCreateFromH264ParameterSets(let status):
            return "DecodeError.videoFormatDescriptionCreateFromH264ParameterSets(\(status))"
        case .videoFormatDescriptionCreateFromHEVCParameterSets(let status):
            return "DecodeError.videoFormatDescriptionCreateFromHEVCParameterSets(\(status))"
        case .decompressionSessionCreate(let status):
            return "DecodeError.decompressionSessionCreate(\(status))"
        case .videoFormatDescriptionCreateForImageBuffer(let status):
            return "DecodeError.videoFormatDescriptionCreateForImageBuffer(\(status))"
        case .sampleBufferCreateForImageBuffer(let status):
            return "DecodeError.sampleBufferCreateForImageBuffer(\(status))"
        }
    }
}

public protocol VideoDecoderDelegate: AnyObject {
    func decodeOutput(video: CMSampleBuffer)
    func decodeOutput(error: DecodeError)
}

public protocol VideoDecoder: AnyObject {
    var isBaseline: Bool { get set }
    var delegate: VideoDecoderDelegate { get set }
    
    func initDecoder(vpsUnit: NalUnitProtocol?, spsUnit: NalUnitProtocol?, ppsUnit: NalUnitProtocol?, isReset: Bool)
    func deinitDecoder()
    func decodeOnePacket(_ packet: VideoPacket)
    func decodeVideoUnit(_ unit: NalUnitProtocol)
}

open class H265Decoder: VideoDecoder {
    
    public static var defaultDecodeFlags: VTDecodeFrameFlags = [
        ._EnableAsynchronousDecompression,
        ._EnableTemporalProcessing
    ]
    
    public static var defaultAttributes: [NSString: AnyObject] = [
        // kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_32BGRA),
        kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        kCVPixelBufferIOSurfacePropertiesKey: [:] as AnyObject
    ]
    
    public static var defaultMinimumGroupOfPictures: Int = 12
    
    open var isBaseline: Bool = true
    open var delegate: VideoDecoderDelegate
    
    private var vpsUnit: H265NalUnit?
    private var spsUnit: H265NalUnit?
    private var ppsUnit: H265NalUnit?
    private var fps: Int = 0
    private var videoSize: CGSize = .zero
    private var invalidateSession: Bool = false
    private var buffers: [CMSampleBuffer] = []
    private var formatDesc: CMVideoFormatDescription?
    
    private var callback: VTDecompressionOutputCallback = {
        (decompressionOutputRefCon: UnsafeMutableRawPointer?,
         _: UnsafeMutableRawPointer?,
         status: OSStatus,
         infoFlags: VTDecodeInfoFlags,
         imageBuffer: CVBuffer?,
         presentationTimeStamp: CMTime,
         duration: CMTime) in
        
        let decoder: H265Decoder = Unmanaged<H265Decoder>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
        decoder.didOutputForSession(
            status,
            infoFlags: infoFlags,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration
        )
    }
    
    private var attributes: [NSString: AnyObject] {
        H265Decoder.defaultAttributes
    }
    
    private var session: VTDecompressionSession?
    
    private var flagIn: VTDecodeFrameFlags {
        H265Decoder.defaultDecodeFlags
    }
    
    private var minimumGroupOfPictures: Int {
        H265Decoder.defaultMinimumGroupOfPictures
    }
    
    public init(delegate: VideoDecoderDelegate) {
        self.delegate = delegate
    }
    
    open func initDecoder(vpsUnit: NalUnitProtocol?, spsUnit: NalUnitProtocol?, ppsUnit: NalUnitProtocol?, isReset: Bool) {
        if isReset || invalidateSession {
            deinitDecoder()
        }
        
        guard let vpsUnit = vpsUnit,
              let spsUnit = spsUnit,
              let ppsUnit = ppsUnit else {
            delegate.decodeOutput(error: .notFoundVpsOrSpsOrPps)
            return
        }
        
        let parameterSetPointers: [UnsafePointer<UInt8>] = [
            vpsUnit.outHeadBuffer,
            ppsUnit.outHeadBuffer,
            spsUnit.outHeadBuffer
        ]
        let parameterSetSizes: [Int] = [
            vpsUnit.bufferSize - 4,
            ppsUnit.bufferSize - 4,
            spsUnit.bufferSize - 4
        ]
        
        var status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 3,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        
        if status != noErr {
            delegate.decodeOutput(error: .videoFormatDescriptionCreateFromHEVCParameterSets(status))
            return
        }
        
        guard let format = formatDesc else {
            return
        }
        
        if let session = session {
            let needResetSession = !VTDecompressionSessionCanAcceptFormatDescription(session,
                                                                                     formatDescription: format)
            if needResetSession {
                deinitDecoder()
            } else {
                return
            }
        }
        
        var record = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: callback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &record,
            decompressionSessionOut: &session
        )
        
        if status != noErr {
            delegate.decodeOutput(error: .decompressionSessionCreate(status))
        } else {
            invalidateSession = false
        }
    }
    
    open func deinitDecoder() {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
    }
    
    open func decodeOnePacket(_ packet: VideoPacket) {
        // Check for changes in FPS and video size.
        if fps != packet.fps || videoSize != packet.videoSize {
            invalidateSession = true
            fps = packet.fps
            videoSize = packet.videoSize
        }
        
        let nalUnits = NalUnitParser.unitParser(packet: packet)
        var currentUnit: H265NalUnit?
        
        for nalUnit in nalUnits {
            if let unit = nalUnit as? H265NalUnit {
                switch unit.type {
                case .vps:
                    print("vps")
                    vpsUnit = unit
                case .sps:
                    print("sps")
                    spsUnit = unit
                case .pps:
                    print("pps")
                    ppsUnit = unit
                case .idr:
                    print("idr")
                    // I-frame (IDR)
                    initDecoder(vpsUnit: vpsUnit, spsUnit: spsUnit, ppsUnit: ppsUnit, isReset: false)
                    currentUnit = unit
                case .pFrame:
                    print("pFrame")
                    currentUnit = unit
                default:
                    break
                }
            }
            guard let unit = currentUnit else {
                continue
            }
            decodeVideoUnit(unit)
        }
    }
    
    open func decodeVideoUnit(_ unit: NalUnitProtocol) {
        guard let formatDesc = formatDesc else { return }

        // 1) Create CMBlockBuffer.
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateEmpty(
            allocator: kCFAllocatorDefault,
            capacity: 0,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        if status != noErr {
            delegate.decodeOutput(error: .blockBufferCreateWithMemoryBlock(status))
            return
        }
        guard let blockBuff = blockBuffer else { return }

        // 2) Allocate memory (passing nil allows it to allocate internally).
        status = CMBlockBufferAppendMemoryBlock(
            blockBuff,
            memoryBlock: nil,
            length : unit.bufferSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: unit.bufferSize,
            flags: 0
        )

        if status != noErr {
            delegate.decodeOutput(error: .blockBufferCreateWithMemoryBlock(status))
            return
        }

        // 3) Copy NAL data.
        status = CMBlockBufferReplaceDataBytes(
            with: unit.lengthHeadBuffer!,
            blockBuffer: blockBuff,
            offsetIntoDestination: 0,
            dataLength: unit.bufferSize
        )
        if status != noErr {
            delegate.decodeOutput(error: .blockBufferCreateWithMemoryBlock(status))
            return
        }

        // 4) Calculate the PTS.
        let pts = CMTime(value: CMTimeValue(CACurrentMediaTime() * 1000000), timescale: 1000000) // In microseconds.
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps)) // Duration based on FPS.

        var timingInfo = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: CMTime.invalid
        )

        // 5) Create CMSampleBuffer.
        var sampleBuffer: CMSampleBuffer?
        let sampleSizeArray: [Int] = [unit.bufferSize]
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuff,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )
        if status != noErr {
            delegate.decodeOutput(error: .sampleBufferCreateReady(status))
            return
        }

        guard let sampleBuff = sampleBuffer, let session = session else { return }

        // 6) Execute decoding.
        var flagOut: VTDecodeInfoFlags = []
        status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuff,
            flags: flagIn,
            frameRefcon: nil,
            infoFlagsOut: &flagOut
        )
        if status != noErr {
            delegate.decodeOutput(error: .decompressionSessionDecodeFrame(status))
        }
    }
    
    private func didOutputForSession(_ status: OSStatus,
                                     infoFlags: VTDecodeInfoFlags,
                                     imageBuffer: CVImageBuffer?,
                                     presentationTimeStamp: CMTime,
                                     duration: CMTime) {
        print("didOutputForSession called, status = \(status), imageBuffer = \(String(describing: imageBuffer))")
        guard let imageBuffer = imageBuffer, status == noErr else {
            delegate.decodeOutput(error: .decompressionOutputCallback(status))
            return
        }
        
        var timingInfo = CMSampleTimingInfo(
            duration: duration.isValid ? duration : CMTime(value: 1, timescale: CMTimeScale(fps)),
            presentationTimeStamp: presentationTimeStamp.isValid ? presentationTimeStamp : CMTime(value: CMTimeValue(CACurrentMediaTime() * 1000000), timescale: 1000000),
            decodeTimeStamp: CMTime.invalid
        )
        
        var videoFormatDescription: CMVideoFormatDescription?
        let status2 = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &videoFormatDescription
        )
        
        if status2 != noErr {
            delegate.decodeOutput(error: .videoFormatDescriptionCreateForImageBuffer(status2))
            return
        }
        
        guard let vfd = videoFormatDescription else {
            return
        }
        
        var sampleBuffer: CMSampleBuffer?
        let status3 = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: vfd,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        if status3 != noErr {
            delegate.decodeOutput(error: .sampleBufferCreateForImageBuffer(status3))
            return
        }
        
        guard let buffer = sampleBuffer else {
            return
        }
        
        // Baseline (real-time playback) or GOP-based playback.
        if isBaseline {
            delegate.decodeOutput(video: buffer)
        } else {
            buffers.append(buffer)
            buffers.sort {
                $0.presentationTimeStamp < $1.presentationTimeStamp
            }
            if buffers.count >= minimumGroupOfPictures {
                let first = buffers.removeFirst()
                delegate.decodeOutput(video: first)
            }
        }
    }
}
