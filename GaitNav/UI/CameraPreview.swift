import SwiftUI
import ARKit
import RealityKit

struct CameraPreview: UIViewRepresentable {
    
    let session: ARSession
    
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session = session
        return view
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}
