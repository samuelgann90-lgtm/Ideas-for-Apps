import Foundation
import Vision
import UIKit

struct RecognizedCardText: Sendable {
  let candidateName: String
  let collectorNumber: String?
  let confidence: Float
}

enum CardRecognitionService {
  static func recognizeCard(from image: CGImage) async -> RecognizedCardText? {
    await withCheckedContinuation { continuation in
      let request = VNRecognizeTextRequest { request, _ in
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        let lines = observations.compactMap { observation -> (text: String, confidence: Float, midY: CGFloat)? in
          guard let candidate = observation.topCandidates(1).first else { return nil }
          let box = observation.boundingBox
          let midY = box.midY
          return (candidate.string, candidate.confidence, midY)
        }

        continuation.resume(returning: parseCardText(from: lines))
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["en-US"]

      let handler = VNImageRequestHandler(cgImage: image, options: [:])
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(returning: nil)
      }
    }
  }

  private static func parseCardText(
    from lines: [(text: String, confidence: Float, midY: CGFloat)]
  ) -> RecognizedCardText? {
    guard !lines.isEmpty else { return nil }

    // Vision origin is bottom-left; higher midY is closer to the top of the card (name area).
    let sortedByY = lines.sorted { $0.midY > $1.midY }

    let collectorPattern = #"\d{1,4}\s*/\s*\d{1,4}"#
    let collectorRegex = try? NSRegularExpression(pattern: collectorPattern)

    var collectorNumber: String?
    var nameCandidates: [(String, Float)] = []

    for (text, confidence, _) in sortedByY {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }

      if collectorNumber == nil,
        let regex = collectorRegex,
        regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
      {
        collectorNumber = trimmed.replacingOccurrences(of: " ", with: "")
        continue
      }

      if looksLikeCardName(trimmed) {
        nameCandidates.append((trimmed, confidence))
      }
    }

    guard let bestName = nameCandidates.max(by: { $0.1 < $1.1 }) else {
      return nil
    }

    return RecognizedCardText(
      candidateName: cleanCardName(bestName.0),
      collectorNumber: collectorNumber,
      confidence: bestName.1
    )
  }

  private static func looksLikeCardName(_ text: String) -> Bool {
    let lower = text.lowercased()
    let blocked = [
      "hp", "weakness", "resistance", "retreat", "trainer", "energy",
      "pokémon", "pokemon", "basic", "stage", "illus", "©",
    ]
    if blocked.contains(where: { lower.contains($0) }) { return false }
    if text.count < 3 || text.count > 40 { return false }
    if text.rangeOfCharacter(from: .decimalDigits) != nil && !text.contains(" ") {
      return false
    }
    return text.rangeOfCharacter(from: .letters) != nil
  }

  private static func cleanCardName(_ name: String) -> String {
    name
      .replacingOccurrences(of: #"^(Basic|Stage 1|Stage 2)\s+"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
