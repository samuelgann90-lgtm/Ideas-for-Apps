import Foundation
import Vision
import UIKit
import CoreImage

struct RecognizedCardText: Sendable {
  let candidateName: String
  let collectorNumber: String?
  let confidence: Float
}

enum CardRecognitionService {
  /// Returns multiple name guesses, best first.
  static func recognizeCardCandidates(from image: CGImage) async -> [RecognizedCardText] {
    let cardCrop = cropToCardRegion(image)
    let nameBand = cropNameBand(cardCrop)

    async let fullResults = recognizeText(in: enhanceForOCR(cardCrop))
    async let nameResults = recognizeText(in: enhanceForOCR(nameBand))

    let lines = await fullResults + await nameResults
    let parsed = parseCardText(from: lines)
    return parsed
  }

  static func recognizeCard(from image: CGImage) async -> RecognizedCardText? {
    let candidates = await recognizeCardCandidates(from: image)
    return candidates.first
  }

  private static func recognizeText(in image: CGImage) async -> [(text: String, confidence: Float, midY: CGFloat)] {
    await withCheckedContinuation { continuation in
      let request = VNRecognizeTextRequest { request, _ in
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        var lines: [(text: String, confidence: Float, midY: CGFloat)] = []

        for observation in observations {
          let box = observation.boundingBox
          let midY = box.midY
          for candidate in observation.topCandidates(3) {
            lines.append((candidate.string, candidate.confidence, midY))
          }
        }

        continuation.resume(returning: lines)
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["en-US"]
      request.minimumTextHeight = 0.012

      let handler = VNImageRequestHandler(cgImage: image, options: [:])
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(returning: [])
      }
    }
  }

  private static func parseCardText(
    from lines: [(text: String, confidence: Float, midY: CGFloat)]
  ) -> [RecognizedCardText] {
    guard !lines.isEmpty else { return [] }

    let deduped = dedupeLines(lines)
    let sortedByY = deduped.sorted { $0.midY > $1.midY }
    let collectorNumber = findCollectorNumber(in: sortedByY)
    let mergedNames = mergeNameLines(sortedByY)

    var results: [RecognizedCardText] = []
    var seen = Set<String>()

    for (name, confidence) in mergedNames {
      let cleaned = cleanCardName(name)
      guard !cleaned.isEmpty else { continue }
      let key = cleaned.lowercased()
      guard !seen.contains(key) else { continue }
      seen.insert(key)

      results.append(
        RecognizedCardText(
          candidateName: cleaned,
          collectorNumber: collectorNumber,
          confidence: confidence
        )
      )
    }

    // Fallback: any plausible single line in the upper half of the card.
    if results.isEmpty {
      for (text, confidence, midY) in sortedByY where midY > 0.45 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeCardName(trimmed) {
          let cleaned = cleanCardName(trimmed)
          if !cleaned.isEmpty {
            results.append(
              RecognizedCardText(
                candidateName: cleaned,
                collectorNumber: collectorNumber,
                confidence: confidence * 0.8
              )
            )
          }
        }
      }
    }

    return results.sorted { $0.confidence > $1.confidence }
  }

  private static func dedupeLines(
    _ lines: [(text: String, confidence: Float, midY: CGFloat)]
  ) -> [(text: String, confidence: Float, midY: CGFloat)] {
    var best: [String: (text: String, confidence: Float, midY: CGFloat)] = [:]
    for line in lines {
      let key = line.text.lowercased()
      if let existing = best[key] {
        if line.confidence > existing.confidence {
          best[key] = line
        }
      } else {
        best[key] = line
      }
    }
    return Array(best.values)
  }

  private static func findCollectorNumber(
    in lines: [(text: String, confidence: Float, midY: CGFloat)]
  ) -> String? {
    let collectorPattern = #"\d{1,4}\s*/\s*\d{1,4}"#
    let collectorRegex = try? NSRegularExpression(pattern: collectorPattern)

    // Collector numbers usually appear in the lower portion of the card.
    for (text, _, midY) in lines.sorted(by: { $0.midY < $1.midY }) where midY < 0.55 {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if let regex = collectorRegex,
        regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
      {
        return trimmed.replacingOccurrences(of: " ", with: "")
      }
    }
    return nil
  }

  private static func mergeNameLines(
    _ lines: [(text: String, confidence: Float, midY: CGFloat)]
  ) -> [(String, Float)] {
    // Name area: upper ~40% of the card in Vision coordinates.
    let nameLines = lines.filter { $0.midY > 0.58 && looksLikeCardName($0.text) }
    guard !nameLines.isEmpty else { return [] }

    var bands: [[(text: String, confidence: Float, midY: CGFloat)]] = []
    for line in nameLines {
      if let index = bands.firstIndex(where: { abs($0[0].midY - line.midY) < 0.04 }) {
        bands[index].append(line)
      } else {
        bands.append([line])
      }
    }

    var merged: [(String, Float)] = []
    for band in bands {
      let sorted = band.sorted { $0.confidence > $1.confidence }
      if let best = sorted.first {
        merged.append((best.text, best.confidence))
      }

      // Combine short lines on the same row (e.g. "Charizard" + "ex").
      let texts = band.map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      if texts.count > 1 {
        let combined = texts.joined(separator: " ")
        let avgConfidence = band.map(\.confidence).reduce(0, +) / Float(band.count)
        if looksLikeCardName(combined) {
          merged.append((combined, avgConfidence))
        }
      }
    }

    return merged.sorted { $0.1 > $1.1 }
  }

  private static func looksLikeCardName(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()

    let blockedExact = [
      "hp", "weakness", "resistance", "retreat", "trainer", "energy",
      "pokémon", "pokemon", "illus", "©", "ability", "attack",
    ]
    if blockedExact.contains(lower) { return false }
    if lower.hasPrefix("stage ") && !lower.contains(" ") { return false }
    if trimmed.count < 2 || trimmed.count > 45 { return false }

    // Allow "ex", "V", "GX", "VMAX" style names.
    let letterCount = trimmed.filter(\.isLetter).count
    guard letterCount >= 2 else { return false }

    // Pure numbers or set codes only.
    if trimmed.rangeOfCharacter(from: .letters) == nil { return false }
    if trimmed.allSatisfy({ $0.isNumber || $0 == "/" }) { return false }

    return true
  }

  private static func cleanCardName(_ name: String) -> String {
    name
      .replacingOccurrences(of: #"^(Basic|Stage 1|Stage 2)\s+"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func cropToCardRegion(_ image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height
    let cropWidth = Int(Double(width) * 0.72)
    let cropHeight = Int(Double(height) * 0.58)
    let rect = CGRect(
      x: (width - cropWidth) / 2,
      y: (height - cropHeight) / 2,
      width: cropWidth,
      height: cropHeight
    )
    return image.cropping(to: rect) ?? image
  }

  private static func cropNameBand(_ cardImage: CGImage) -> CGImage {
    let width = cardImage.width
    let height = cardImage.height
    let bandHeight = Int(Double(height) * 0.28)
    let rect = CGRect(x: 0, y: height - bandHeight, width: width, height: bandHeight)
    return cardImage.cropping(to: rect) ?? cardImage
  }

  private static func enhanceForOCR(_ image: CGImage) -> CGImage {
    let ciImage = CIImage(cgImage: image)
    let context = CIContext()

    let contrast = ciImage.applyingFilter("CIColorControls", parameters: [
      kCIInputContrastKey: 1.25,
      kCIInputBrightnessKey: 0.02,
      kCIInputSaturationKey: 1.0,
    ])
    let sharpened = contrast.applyingFilter("CISharpenLuminance", parameters: [
      kCIInputSharpnessKey: 0.6,
    ])

    guard let output = context.createCGImage(sharpened, from: sharpened.extent) else {
      return image
    }
    return output
  }
}
