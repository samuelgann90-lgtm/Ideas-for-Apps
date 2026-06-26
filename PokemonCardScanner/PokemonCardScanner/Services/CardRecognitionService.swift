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
  /// Returns validated name guesses, best first. Empty if OCR read gibberish.
  static func recognizeCardCandidates(from image: CGImage) async -> [RecognizedCardText] {
    let cardCrop = cropToCardRegion(image)
    let nameBand = cropNameBand(cardCrop)
    let numberBand = cropNumberBand(cardCrop)

    async let nameLines = recognizeText(in: enhanceForOCR(nameBand))
    async let numberLines = recognizeText(in: enhanceForOCR(numberBand))

    let collectorNumber = findCollectorNumber(in: await numberLines)
    let nameCandidates = parseNameBandLines(await nameLines)
    return await validateWithDatabase(nameCandidates, collectorNumber: collectorNumber)
  }

  static func recognizeCard(from image: CGImage) async -> RecognizedCardText? {
    let candidates = await recognizeCardCandidates(from: image)
    return candidates.first
  }

  // MARK: - OCR

  private static func recognizeText(in image: CGImage) async -> [(text: String, confidence: Float)] {
    await withCheckedContinuation { continuation in
      let request = VNRecognizeTextRequest { request, _ in
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        var lines: [(text: String, confidence: Float)] = []

        for observation in observations {
          for candidate in observation.topCandidates(5) {
            lines.append((candidate.string, candidate.confidence))
          }
        }

        continuation.resume(returning: lines)
      }

      request.recognitionLevel = .accurate
      // Pokémon names are not dictionary words — autocorrect turns garble into "Doo Da" etc.
      request.usesLanguageCorrection = false
      request.recognitionLanguages = ["en-US"]
      request.minimumTextHeight = 0.02

      let handler = VNImageRequestHandler(cgImage: image, options: [:])
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(returning: [])
      }
    }
  }

  // MARK: - Parsing

  private static func parseNameBandLines(
    _ lines: [(text: String, confidence: Float)]
  ) -> [(name: String, confidence: Float)] {
    var results: [(String, Float)] = []
    var seen = Set<String>()

    let sorted = lines.sorted { $0.confidence > $1.confidence }

    for (text, confidence) in sorted {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard looksLikeCardName(trimmed) else { continue }

      let cleaned = cleanCardName(trimmed)
      guard !cleaned.isEmpty else { continue }

      let key = cleaned.lowercased()
      guard !seen.contains(key) else { continue }
      seen.insert(key)

      results.append((cleaned, confidence))
    }

    // Try joining adjacent short fragments (e.g. "Pikachu" + "ex" read separately).
    let words = sorted.map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    for i in 0..<words.count {
      for j in (i + 1)...min(i + 2, words.count - 1) {
        let combined = words[i...j].joined(separator: " ")
        if looksLikeCardName(combined) {
          let cleaned = cleanCardName(combined)
          let key = cleaned.lowercased()
          if !seen.contains(key) {
            seen.insert(key)
            results.append((cleaned, sorted[i].confidence * 0.95))
          }
        }
      }
    }

    return results.sorted { $0.1 > $1.1 }
  }

  private static func findCollectorNumber(
    in lines: [(text: String, confidence: Float)]
  ) -> String? {
    let collectorPattern = #"\d{1,4}\s*/\s*\d{1,4}"#
    let collectorRegex = try? NSRegularExpression(pattern: collectorPattern)

    for (text, _) in lines {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if let regex = collectorRegex,
        regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
      {
        return trimmed.replacingOccurrences(of: " ", with: "")
      }
    }
    return nil
  }

  // MARK: - Database validation

  /// Only return names that actually exist in the Pokémon TCG database.
  private static func validateWithDatabase(
    _ candidates: [(name: String, confidence: Float)],
    collectorNumber: String?
  ) async -> [RecognizedCardText] {
    guard !candidates.isEmpty else { return [] }

    var scored: [(name: String, confidence: Float, apiScore: Int)] = []

    for (name, confidence) in candidates {
      let score = await databaseMatchScore(for: name)
      if score > 0 {
        scored.append((name, confidence, score))
      }
    }

    // Also try API suggestions from short prefixes of high-confidence OCR garbage.
    if scored.isEmpty {
      for (name, confidence) in candidates.prefix(3) {
        let prefix = String(name.prefix(4))
        guard prefix.count >= 3 else { continue }
        let suggestions = await PokemonTCGService.shared.suggestNames(matching: prefix)
        for suggestion in suggestions.prefix(3) {
          scored.append((suggestion, confidence * 0.7, 80))
        }
      }
    }

    guard !scored.isEmpty else { return [] }

    let sorted = scored.sorted {
      if $0.apiScore != $1.apiScore { return $0.apiScore > $1.apiScore }
      return $0.confidence > $1.confidence
    }

    var seen = Set<String>()
    var results: [RecognizedCardText] = []

    for item in sorted {
      let key = item.name.lowercased()
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      results.append(
        RecognizedCardText(
          candidateName: item.name,
          collectorNumber: collectorNumber,
          confidence: item.confidence
        )
      )
      if results.count >= 5 { break }
    }

    return results
  }

  private static func databaseMatchScore(for name: String) async -> Int {
    let cleaned = cleanCardName(name)
    guard cleaned.count >= 3 else { return 0 }

    // Direct search hit = strong match.
    if let cards = try? await PokemonTCGService.shared.searchCards(name: cleaned), !cards.isEmpty {
      let exact = cards.contains { $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame }
      return exact ? 100 : 70
    }

    // Prefix suggestions from the API.
    let prefix = String(cleaned.prefix(4))
    let suggestions = await PokemonTCGService.shared.suggestNames(matching: prefix)
    for suggestion in suggestions {
      if suggestion.localizedCaseInsensitiveCompare(cleaned) == .orderedSame { return 90 }
      if suggestion.localizedCaseInsensitiveContains(cleaned) { return 75 }
      if cleaned.localizedCaseInsensitiveContains(suggestion) { return 60 }
    }

    return 0
  }

  // MARK: - Filters

  private static func looksLikeCardName(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()

    let blocked = [
      "hp", "weakness", "resistance", "retreat", "trainer", "energy",
      "pokémon", "pokemon", "illus", "©", "ability", "attack", "put",
      "coin", "damage", "during", "your", "opponent", "this", "the",
    ]
    if blocked.contains(lower) { return false }
    if lower.hasPrefix("stage ") { return false }
    if trimmed.count < 3 || trimmed.count > 45 { return false }

    let letterCount = trimmed.filter(\.isLetter).count
    guard letterCount >= 3 else { return false }
    if trimmed.rangeOfCharacter(from: .letters) == nil { return false }

    // Reject obvious gibberish: all very short words with no Pokémon suffix.
    let words = lower.split(separator: " ").map(String.init)
    let pokemonSuffixes = ["ex", "gx", "v", "vmax", "vstar", "lv.x", "-gx", "-ex"]
    let hasSuffix = pokemonSuffixes.contains { lower.contains($0) }
    if words.allSatisfy({ $0.count <= 3 }) && !hasSuffix { return false }

    return true
  }

  private static func cleanCardName(_ name: String) -> String {
    name
      .replacingOccurrences(of: #"^(Basic|Stage 1|Stage 2)\s+"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Image crops

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

  /// Top of card where the Pokémon name is printed (CGImage origin is top-left).
  private static func cropNameBand(_ cardImage: CGImage) -> CGImage {
    let width = cardImage.width
    let height = cardImage.height
    let bandHeight = Int(Double(height) * 0.24)
    let rect = CGRect(x: 0, y: 0, width: width, height: bandHeight)
    return cardImage.cropping(to: rect) ?? cardImage
  }

  /// Bottom-right corner where collector number is printed (e.g. 025/165).
  private static func cropNumberBand(_ cardImage: CGImage) -> CGImage {
    let width = cardImage.width
    let height = cardImage.height
    let bandWidth = Int(Double(width) * 0.4)
    let bandHeight = Int(Double(height) * 0.14)
    let rect = CGRect(
      x: width - bandWidth,
      y: height - bandHeight,
      width: bandWidth,
      height: bandHeight
    )
    return cardImage.cropping(to: rect) ?? cardImage
  }

  private static func enhanceForOCR(_ image: CGImage) -> CGImage {
    let ciImage = CIImage(cgImage: image)
    let context = CIContext()

    let contrast = ciImage.applyingFilter("CIColorControls", parameters: [
      kCIInputContrastKey: 1.35,
      kCIInputBrightnessKey: 0.04,
      kCIInputSaturationKey: 1.0,
    ])
    let sharpened = contrast.applyingFilter("CISharpenLuminance", parameters: [
      kCIInputSharpnessKey: 0.8,
    ])

    guard let output = context.createCGImage(sharpened, from: sharpened.extent) else {
      return image
    }
    return output
  }
}
