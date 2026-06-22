import Foundation
import UIKit
import Vision

/// On-device visual card matching using Apple's Vision feature prints (Core ML under the hood).
enum VisualMatchingService {
  private static let distanceCeiling: Float = 12

  static func rank(candidates: [PokemonCard], scannedImage: CGImage) async -> [RankedCardMatch] {
    let cropped = cropToCardRegion(scannedImage)
    guard let scannedPrint = featurePrint(for: cropped) else {
      return candidates.map {
        RankedCardMatch(card: $0, similarity: 0, visualDistance: .infinity)
      }
    }

    var matches: [RankedCardMatch] = []
    await withTaskGroup(of: RankedCardMatch?.self) { group in
      for card in candidates {
        group.addTask {
          await matchCard(card, scannedPrint: scannedPrint)
        }
      }
      for await result in group {
        if let result { matches.append(result) }
      }
    }

    return matches.sorted { $0.similarity > $1.similarity }
  }

  static func shouldAutoSelect(_ matches: [RankedCardMatch]) -> Bool {
    guard let top = matches.first else { return false }
    guard top.similarity >= 75 else { return false }
    if matches.count == 1 { return true }
    let second = matches[1].similarity
    return top.similarity - second >= 12
  }

  private static func matchCard(
    _ card: PokemonCard,
    scannedPrint: VNFeaturePrintObservation
  ) async -> RankedCardMatch? {
    guard let url = URL(string: card.images.large),
      let referenceImage = await downloadImage(from: url),
      let referencePrint = featurePrint(for: referenceImage)
    else {
      return RankedCardMatch(card: card, similarity: 0, visualDistance: .infinity)
    }

    var distance: Float = 0
    do {
      try scannedPrint.computeDistance(&distance, to: referencePrint)
    } catch {
      return RankedCardMatch(card: card, similarity: 0, visualDistance: .infinity)
    }

    return RankedCardMatch(
      card: card,
      similarity: similarityPercent(from: distance),
      visualDistance: distance
    )
  }

  private static func featurePrint(for image: CGImage) -> VNFeaturePrintObservation? {
    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
      return request.results?.first as? VNFeaturePrintObservation
    } catch {
      return nil
    }
  }

  private static func cropToCardRegion(_ image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height
    let cropWidth = Int(Double(width) * 0.62)
    let cropHeight = Int(Double(height) * 0.52)
    let rect = CGRect(
      x: (width - cropWidth) / 2,
      y: (height - cropHeight) / 2,
      width: cropWidth,
      height: cropHeight
    )
    return image.cropping(to: rect) ?? image
  }

  private static func downloadImage(from url: URL) async -> CGImage? {
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else { return nil }
      return cgImage
    } catch {
      return nil
    }
  }

  private static func similarityPercent(from distance: Float) -> Float {
    let clamped = min(distance, distanceCeiling)
    return max(0, min(100, (1 - clamped / distanceCeiling) * 100))
  }
}
