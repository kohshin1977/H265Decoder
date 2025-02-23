//
//  H265NalUnit.swift
//  H265Decoder
//
//  Created by Kohshin Tokunaga on 2025/02/15.
//

import Foundation
import CoreMedia

public enum NalUnitType {
    case other
    case vps
    case sps
    case pps
    case idr
    case pFrame
}

public protocol NalUnitProtocol: AnyObject {
    var type: NalUnitType { get }
    var buffer: UnsafePointer<UInt8> { get }
    var bufferSize: Int { get }
    var outHeadBuffer: UnsafePointer<UInt8> { get }
    var lengthHeadBuffer: UnsafePointer<UInt8>? { get }
}

open class H265NalUnit: NalUnitProtocol {
    open private(set) var bufferSize: Int
    open private(set) var buffer: UnsafePointer<UInt8>
    open private(set) var outHeadBuffer: UnsafePointer<UInt8>
    open private(set) var lengthHeadBuffer: UnsafePointer<UInt8>?
    open private(set) var type: NalUnitType
    
    public init(_ buffer: UnsafePointer<UInt8>, bufferSize: Int) {
        let newBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        newBuffer.initialize(from: buffer, count: bufferSize)
        self.buffer = UnsafePointer<UInt8>(newBuffer)
        self.bufferSize = bufferSize
        self.outHeadBuffer = self.buffer + 4
        
        // Set the NAL size in big-endian format in the first 4 bytes.
        var length = CFSwapInt32HostToBig(UInt32(bufferSize - 4))
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<UInt8>.alignment
        )
        rawPointer.initializeMemory(as: UInt8.self, from: self.buffer, count: bufferSize)
        memcpy(rawPointer, &length, 4)
        
        let rawBufferPointer = UnsafeRawBufferPointer(start: rawPointer, count: bufferSize)
        if let baseAddress = rawBufferPointer.baseAddress {
            let outRawPointer = UnsafeRawPointer(baseAddress)
            lengthHeadBuffer = outRawPointer.bindMemory(to: UInt8.self, capacity: bufferSize)
        }
        
        // Determine the type from the NAL header (HEVC NAL header: typeValue = (nal_unit_header[0] & 0x7E) >> 1)
        var type: NalUnitType = .other
        let typeValue = (outHeadBuffer.pointee & 0x7E) >> 1
        switch typeValue {
        case 0x01:
            type = .pFrame
        case 0x13, 0x14:
            type = .idr
        case 0x20:
            type = .vps
        case 0x21:
            type = .sps
        case 0x22:
            type = .pps
        default:
            break
        }
        self.type = type
    }
    
    deinit {
        buffer.deallocate()
        lengthHeadBuffer?.deallocate()
    }
}

open class NalUnitParser {
    private static let startCode3: [UInt8] = [0, 0, 1]
    private static let startCode4: [UInt8] = [0, 0, 0, 1]
    
    private class var startCode: UnsafeMutablePointer<UInt8> {
        let start: [UInt8] = [0,0,0,1]
        let startBuffer = start.withUnsafeBytes { return $0 }
        let rawPointer = UnsafeMutableRawPointer(mutating: startBuffer.baseAddress!)
        return rawPointer.bindMemory(to: UInt8.self, capacity: 4)
    }
    
    open class func unitParser(packet: VideoPacket) -> [NalUnitProtocol] {
        var nalUnits: [NalUnitProtocol] = []
        let length = packet.bufferSize

        // Check the size of the data.
        if length > 4 {
            packet.data.withUnsafeBytes { rawBuffer in
                guard let baseAddr = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                var unitBegin = baseAddr
                var unitEnd = baseAddr + 4

                while unitEnd < (baseAddr + length) {
                    let offset = unitEnd - baseAddr
                    // Check: 4 bytes → startCode4
                    if offset >= 4 {
                        if memcmp(unitEnd - 3, Self.startCode4, 4) == 0 {
                            let count = (unitEnd - 3) - unitBegin
                            if count > 0,
                               let unit = nalUnit(
                                type: packet.type,
                                buffer: unitBegin,
                                bufferSize: count
                               ) {
                                nalUnits.append(unit)
                            }
                            unitBegin = unitEnd - 3
                        }
                        // Next, check: 3 bytes → startCode3
                        else if offset >= 3 {
                            if memcmp(unitEnd - 2, Self.startCode3, 3) == 0 {
                                let count = (unitEnd - 2) - unitBegin
                                if count > 0,
                                   let unit = nalUnit(
                                    type: packet.type,
                                    buffer: unitBegin,
                                    bufferSize: count
                                   ) {
                                    nalUnits.append(unit)
                                }
                                unitBegin = unitEnd - 2
                            }
                        }
                    }
                    unitEnd += 1
                }

                // Process the remaining part.
                let count = unitEnd - unitBegin
                if let unit = nalUnit(
                    type: packet.type,
                    buffer: unitBegin,
                    bufferSize: count
                ) {
                    nalUnits.append(unit)
                }
            }
        }
        return nalUnits
    }
   
    private class func nalUnit(
        type: EncodeType,
        buffer: UnsafePointer<UInt8>,
        bufferSize: Int
    ) -> NalUnitProtocol? {
        guard bufferSize > 4 else {
            return nil
        }
        switch type {
        case .h264:
            // If an H264NalUnit implementation is needed, generate it here.
            return nil
        case .h265:
            return H265NalUnit(buffer, bufferSize: bufferSize)
        }
    }
}
