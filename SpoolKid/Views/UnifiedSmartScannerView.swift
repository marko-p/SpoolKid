import SwiftUI
import AVFoundation

private enum UnifiedSmartScannerPermissionGuidance {
    static func message(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .denied, .restricted:
            return "Camera access is disabled. Enable it in the iOS Settings app to use Smart Scan."
        case .notDetermined:
            return "Camera access is required for Smart Scan."
        default:
            return "Point the camera at a QR code or filament label text."
        }
    }
}

enum UnifiedSmartScanOutput: Sendable {
    case qr(String)
    case ocr(OCRParsedCandidate)
}

struct UnifiedSmartScannerView: View {
    let onOutput: (UnifiedSmartScanOutput, Data?) -> Void
    let onCancel: () -> Void
    let onStatus: (String) -> Void

    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined

    var body: some View {
        Group {
            if cameraStatus == .authorized {
                UnifiedSmartScannerCameraPreview(
                    onOutput: onOutput,
                    onCancel: onCancel,
                    onStatus: onStatus
                )
                .ignoresSafeArea()
            } else {
                CameraPermissionView(
                    status: cameraStatus,
                    message: UnifiedSmartScannerPermissionGuidance.message(for: cameraStatus),
                    onRequest: requestCameraPermission,
                    onCancel: onCancel
                )
            }
        }
        .onAppear {
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            onStatus(UnifiedSmartScannerPermissionGuidance.message(for: cameraStatus))
        }
    }

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async {
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                onStatus(UnifiedSmartScannerPermissionGuidance.message(for: cameraStatus))
            }
        }
    }
}

private struct UnifiedSmartScannerCameraPreview: UIViewControllerRepresentable {
    let onOutput: (UnifiedSmartScanOutput, Data?) -> Void
    let onCancel: () -> Void
    let onStatus: (String) -> Void

    func makeUIViewController(context: Context) -> UnifiedSmartScannerViewController {
        let controller = UnifiedSmartScannerViewController()
        controller.onOutput = onOutput
        controller.onCancel = onCancel
        controller.onStatus = onStatus
        return controller
    }

    func updateUIViewController(_ uiViewController: UnifiedSmartScannerViewController, context: Context) {
        uiViewController.onOutput = onOutput
        uiViewController.onCancel = onCancel
        uiViewController.onStatus = onStatus
    }
}
