import AVFoundation
import UIKit

final class CameraManager: NSObject, ObservableObject {
  @Published var permissionDenied = false
  @Published var isRunning = false
  @Published var latestFrame: CGImage?

  let session = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "camera.session.queue")
  private var isConfigured = false

  func requestPermissionAndStart() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      startSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.startSession()
          } else {
            self?.permissionDenied = true
          }
        }
      }
    default:
      permissionDenied = true
    }
  }

  func stopSession() {
    sessionQueue.async { [weak self] in
      self?.session.stopRunning()
      DispatchQueue.main.async {
        self?.isRunning = false
      }
    }
  }

  /// Uses the latest camera preview frame (stable and avoids photo-capture crashes).
  func capturePhoto() async -> CGImage? {
    for _ in 0..<30 {
      if let frame = await MainActor.run(body: { latestFrame }) {
        return frame
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return await MainActor.run { latestFrame }
  }

  private func startSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if !self.isConfigured {
        self.configureSession()
      }
      if !self.session.isRunning {
        self.session.startRunning()
        DispatchQueue.main.async {
          self.isRunning = true
        }
      }
    }
  }

  private func configureSession() {
    session.beginConfiguration()
    session.sessionPreset = .high

    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      session.commitConfiguration()
      return
    }

    session.addInput(input)

    try? device.lockForConfiguration()
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }
    device.unlockForConfiguration()

    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true

    if session.canAddOutput(videoOutput) {
      session.addOutput(videoOutput)
      if let connection = videoOutput.connection(with: .video) {
        connection.videoRotationAngle = 90
      }
    }

    session.commitConfiguration()
    isConfigured = true
  }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

    DispatchQueue.main.async {
      self.latestFrame = cgImage
    }
  }
}
