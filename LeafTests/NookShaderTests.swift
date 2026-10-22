#if canImport(Metal) && !canImport(LeafCore)
import Metal
import Testing
@testable import Leaf

/// The nook scenes' shaders are compiled from source at run time, so the build can't catch a mistake in them: this
/// compiles and links every program on the simulator's GPU.
struct NookShaderTests {
    @Test func everyProgramCompilesAndLinks() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let library = try device.makeLibrary(source: NookShaderSource.text, options: nil)
        let vertex = library.makeFunction(name: "nook_vertex")
        #expect(vertex != nil)
        for program in NookShaderProgram.allCases {
            let fragment = library.makeFunction(name: program.function)
            #expect(fragment != nil, "missing \(program.function)")
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            _ = try device.makeRenderPipelineState(descriptor: descriptor)
        }
    }

    @Test func uniformsMatchTheShaderLayout() {
        let stride: Int = MemoryLayout<NookShaderUniforms>.stride
        #expect(stride == 16)
    }
}
#endif
