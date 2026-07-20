import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isFrontCamera: Bool
    let onFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocus = onFocus
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onFocus = onFocus
        uiView.updateOrientation()
        if let connection = uiView.previewLayer.connection,
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isFrontCamera
        }
    }
}

final class PreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("PreviewView must use AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    var onFocus: ((CGPoint) -> Void)?
    private let focusRing = CAShapeLayer()

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        focusRing.bounds = CGRect(x: 0, y: 0, width: 72, height: 72)
        focusRing.path = UIBezierPath(roundedRect: focusRing.bounds, cornerRadius: 12).cgPath
        focusRing.fillColor = UIColor.clear.cgColor
        focusRing.strokeColor = UIColor(red: 0.95, green: 0.82, blue: 0.52, alpha: 1).cgColor
        focusRing.lineWidth = 1.5
        focusRing.opacity = 0
        layer.addSublayer(focusRing)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported,
              let orientation = window?.windowScene?.interfaceOrientation else { return }

        switch orientation {
        case .portrait: connection.videoOrientation = .portrait
        case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
        case .landscapeLeft: connection.videoOrientation = .landscapeLeft
        case .landscapeRight: connection.videoOrientation = .landscapeRight
        default: break
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let layerPoint = recognizer.location(in: self)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        onFocus?(devicePoint)
        showFocusRing(at: layerPoint)
    }

    private func showFocusRing(at point: CGPoint) {
        focusRing.removeAllAnimations()
        focusRing.position = point
        focusRing.transform = CATransform3DMakeScale(1.25, 1.25, 1)
        focusRing.opacity = 1

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.25
        scale.toValue = 1
        scale.duration = 0.18

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = 0.8
        fade.duration = 0.35
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false

        focusRing.add(scale, forKey: "focusScale")
        focusRing.add(fade, forKey: "focusFade")
    }
}
