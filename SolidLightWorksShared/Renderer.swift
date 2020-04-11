//
//  Renderer.swift
//  SolidLightWorksShared
//
//  Created by Administrator on 26/03/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

struct FlatVertex {
    let position: simd_float3
    let color: simd_float4
}

let screenGrey = Float(0xc0) / Float(0xff)
let screenColor = simd_float4(screenGrey, screenGrey, screenGrey, 0.2)

let screenVertices: [FlatVertex] = [
    FlatVertex(position: simd_float3(-8, 0, 0), color: screenColor),
    FlatVertex(position: simd_float3(8, 0, 0), color: screenColor),
    FlatVertex(position: simd_float3(-8, 6, 0), color: screenColor),
    FlatVertex(position: simd_float3(-8, 6, 0), color: screenColor),
    FlatVertex(position: simd_float3(8, 0, 0), color: screenColor),
    FlatVertex(position: simd_float3(8, 6, 0), color: screenColor)
]

let xAxisColor = simd_float4(1, 0, 0, 1)
let yAxisColor = simd_float4(0, 1, 0, 1)
let zAxisColor = simd_float4(0, 0, 1, 1)

let axesVertices: [FlatVertex] = [
    FlatVertex(position: simd_float3(0, 0, 0), color: xAxisColor),
    FlatVertex(position: simd_float3(8, 0, 0), color: xAxisColor),
    FlatVertex(position: simd_float3(0, 0, 0), color: yAxisColor),
    FlatVertex(position: simd_float3(0, 6, 0), color: yAxisColor),
    FlatVertex(position: simd_float3(0, 0, 0), color: zAxisColor),
    FlatVertex(position: simd_float3(0, 0, 8), color: zAxisColor)
]

let waveDivisions = 128
let waveWidth = Float(4)
let dx = waveWidth / Float(waveDivisions)
let da = 2 * Float.pi / Float(waveDivisions)
let wavePoints = (0..<waveDivisions).map { n -> simd_float2 in
    let x = Float(n) * dx - waveWidth / 2
    let a = Float(n) * da
    let y = 2 * sin(a) + 3
    return simd_float2(x, y)
}
let (lineVertices, lineIndices) = makeLine2DVertices(wavePoints, 0.1)

class Renderer: NSObject, MTKViewDelegate {
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var dynamicUniformBuffer: MTLBuffer
    
    var flatPipelineState: MTLRenderPipelineState
    var flatUniformBuffer: MTLBuffer
    var flatUniforms: UnsafeMutablePointer<FlatUniforms>
    
    var line2DPipelineState: MTLRenderPipelineState
    var line2DUniformBuffer: MTLBuffer
    var line2DUniforms: UnsafeMutablePointer<Line2DUniforms>
    var line2dIndexBuffer: MTLBuffer
    
    var uniformBufferOffset = 0
    var uniformBufferIndex = 0
    var uniforms: UnsafeMutablePointer<Uniforms>
    
    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    
    var rotation: Float = 0
    
    init?(metalKitView: MTKView, bundle: Bundle? = nil) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        
        guard let buffer = self.device.makeBuffer(length:uniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
        dynamicUniformBuffer = buffer
        
        self.dynamicUniformBuffer.label = "UniformBuffer"
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)
        
        let flatUniformBufferSize = MemoryLayout<FlatUniforms>.size
        guard let buffer2 = self.device.makeBuffer(length:flatUniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
        flatUniformBuffer = buffer2
        flatUniforms = UnsafeMutableRawPointer(flatUniformBuffer.contents()).bindMemory(to: FlatUniforms.self, capacity: 1)
        
        do {
            flatPipelineState = try Renderer.buildRenderFlatPipelineWithDevice(device: device,
                                                                               metalKitView: metalKitView,
                                                                               bundle: bundle)
        } catch {
            print("Unable to compile render flat pipeline state.  Error info: \(error)")
            return nil
        }
        
        let line2DUniformBufferSize = MemoryLayout<Line2DUniforms>.size
        guard let buffer3 = self.device.makeBuffer(length:line2DUniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
        line2DUniformBuffer = buffer3
        line2DUniforms = UnsafeMutableRawPointer(line2DUniformBuffer.contents()).bindMemory(to: Line2DUniforms.self, capacity: 1)
        line2dIndexBuffer = device.makeBuffer(bytes: lineIndices,
                                              length: MemoryLayout<UInt16>.stride * lineIndices.count,
                                              options: [])!
        
        do {
            line2DPipelineState = try Renderer.buildRenderLine2DPipelineWithDevice(device: device,
                                                                                   metalKitView: metalKitView,
                                                                                   bundle: bundle)
        } catch {
            print("Unable to compile render line2D pipeline state.  Error info: \(error)")
            return nil
        }
        
        super.init()
    }
    
    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor,
                                             bundle: Bundle?) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = bundle != nil
            ? try device.makeDefaultLibrary(bundle: bundle!)
            : device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        
        let colorAttachments0 = pipelineDescriptor.colorAttachments[0]!
        colorAttachments0.pixelFormat = metalKitView.colorPixelFormat
        colorAttachments0.isBlendingEnabled = true
        colorAttachments0.rgbBlendOperation = .add
        colorAttachments0.alphaBlendOperation = .add
        colorAttachments0.sourceRGBBlendFactor = .sourceAlpha
        colorAttachments0.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachments0.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachments0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    class func buildRenderFlatPipelineWithDevice(device: MTLDevice,
                                                 metalKitView: MTKView,
                                                 bundle: Bundle?) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = bundle != nil
            ? try device.makeDefaultLibrary(bundle: bundle!)
            : device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "vertexFlatShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentFlatShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        let colorAttachments0 = pipelineDescriptor.colorAttachments[0]!
        colorAttachments0.pixelFormat = metalKitView.colorPixelFormat
        colorAttachments0.isBlendingEnabled = true
        colorAttachments0.rgbBlendOperation = .add
        colorAttachments0.alphaBlendOperation = .add
        colorAttachments0.sourceRGBBlendFactor = .sourceAlpha
        colorAttachments0.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachments0.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachments0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    class func buildRenderLine2DPipelineWithDevice(device: MTLDevice,
                                                   metalKitView: MTKView,
                                                   bundle: Bundle?) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = bundle != nil
            ? try device.makeDefaultLibrary(bundle: bundle!)
            : device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "vertexLine2DShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentLine2DShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        let colorAttachments0 = pipelineDescriptor.colorAttachments[0]!
        colorAttachments0.pixelFormat = metalKitView.colorPixelFormat
        colorAttachments0.isBlendingEnabled = true
        colorAttachments0.rgbBlendOperation = .add
        colorAttachments0.alphaBlendOperation = .add
        colorAttachments0.sourceRGBBlendFactor = .sourceAlpha
        colorAttachments0.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachments0.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachments0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1)
    }
    
    private func updateGameState() {
        /// Update any game state before rendering
        
        let viewMatrix = matrix4x4_translation(0, -3.0, -10.0)
        
        flatUniforms[0].projectionMatrix = projectionMatrix
        flatUniforms[0].modelViewMatrix = viewMatrix
        
        line2DUniforms[0].projectionMatrix = projectionMatrix
        line2DUniforms[0].modelViewMatrix = viewMatrix
        line2DUniforms[0].color = simd_float4(1, 1, 1, 1)
    }
    
    func draw(in view: MTKView) {
        /// Per frame updates hare
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer) -> Swift.Void in
                semaphore.signal()
            }
            
            self.updateDynamicBufferState()
            self.updateGameState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
//                renderEncoder.pushDebugGroup("Draw Screen")
//                renderEncoder.setRenderPipelineState(flatPipelineState)
//                renderEncoder.setVertexBytes(screenVertices,
//                                             length: MemoryLayout<FlatVertex>.stride * screenVertices.count,
//                                             index: 0)
//                renderEncoder.setVertexBuffer(flatUniformBuffer, offset:0, index: 1)
//                renderEncoder.setFragmentBuffer(flatUniformBuffer, offset:0, index: 1)
//                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: screenVertices.count)
//                renderEncoder.popDebugGroup()
                
//                renderEncoder.pushDebugGroup("Draw Axes")
//                renderEncoder.setVertexBytes(axesVertices, length: axesVertices.count * MemoryLayout<FlatVertex>.stride, index: 0)
//                renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: axesVertices.count)
//                renderEncoder.popDebugGroup()
                
                renderEncoder.pushDebugGroup("Draw Line")
                renderEncoder.setRenderPipelineState(line2DPipelineState)
                renderEncoder.setVertexBytes(lineVertices, length: lineVertices.count * MemoryLayout<simd_float3>.stride, index: 0)
                renderEncoder.setVertexBuffer(line2DUniformBuffer, offset:0, index: 1)
                renderEncoder.setFragmentBuffer(line2DUniformBuffer, offset:0, index: 1)
                renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                    indexCount: lineIndices.count,
                                                    indexType: .uint16,
                                                    indexBuffer: line2dIndexBuffer,
                                                    indexBufferOffset: 0)
                renderEncoder.popDebugGroup()
                
                renderEncoder.endEncoding()
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
            
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65),
                                                         aspectRatio:aspect,
                                                         nearZ: 0.1,
                                                         farZ: 100.0)
    }
}
