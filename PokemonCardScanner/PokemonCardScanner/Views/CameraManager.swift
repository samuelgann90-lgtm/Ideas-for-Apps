import AVFoundation
import UIKit

@MainActor
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
        Task { @MainActor in
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
      Task { @MainActor in
        self?.isRunning = false
      }
    }
  }

  private func startSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if !self.isConfigured {
        self.configureSession()
      }
      if !self.session.isRunning {
        self.session.startRunning()
        Task { @MainActor in
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

  func captureCurrentFrame() -> CGImage? {
    latestFrame
  }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

    Task { @MainActor in
      self.latestFrame = cgImage
    }
  }
}
