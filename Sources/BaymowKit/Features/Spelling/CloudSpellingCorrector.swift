import Foundation
import Security
import BaymowCore

// Stavehjælp via internet (AP-64). Et tilvalg: slået fra som standard, og kun med brugerens egen nøgle.
// Den markerede tekst sendes til det valgte firma, når brugeren trykker ⌃⌥R – aldrig af sig selv, og aldrig som en
// stille reserve for Macens egen model. Fejlbeskeder og logs indeholder aldrig teksten eller svaret.

/// Firmaerne, brugeren kan vælge. Modellerne er valgt ud fra stavetesten 23. november 2026 (115 sætninger):
/// GPT-6 Luna fandt 63 af 63 fejl, Claude Sonnet 5.5 62 af 63, begge uden forkerte rettelser.
enum CloudProvider: String, CaseIterable, Identifiable, Sendable {
    // ChatGPT først: brugerens standard (23. november 2026), lige så god og billigst.
    case openai
    case claude

    var id: String { rawValue }
    /// Navnet, brugeren kender.
    var title: String { self == .claude ? "Claude" : "ChatGPT" }
    var company: String { self == .claude ? "Anthropic" : "OpenAI" }
    var model: String { self == .claude ? "claude-sonnet-5-5" : "gpt-6-luna" }
    var keySite: String { self == .claude ? "console.anthropic.com" : "platform.openai.com" }
    fileprivate var keychainService: String { "dk.baymow.spelling.\(rawValue)" }
}

/// Hvorfor internet-hjælpen ikke blev brugt. Indeholder aldrig brugerens tekst.
enum CloudSpellingError: Error, Equatable {
    case noKey
    case badKey
    case offline
    case failed
}

/// Brugerens API-nøgler i Macens nøglering. Nøglen vises aldrig igen, når den er gemt.
enum CloudKeyStore {
    static func key(for provider: CloudProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func hasKey(for provider: CloudProvider) -> Bool { key(for: provider) != nil }

    /// Gemmer nøglen uden mellemrum og linjeskift (de kommer let med, når man kopierer).
    @discardableResult
    static func save(_ key: String, for provider: CloudProvider) -> Bool {
        let clean = key.filter { !$0.isWhitespace }
        guard !clean.isEmpty, let data = clean.data(using: .utf8) else { return false }
        delete(provider)
        var item = baseQuery(provider)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "Baymow stavehjælp (\(provider.title))"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ provider: CloudProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
    }

    private static func baseQuery(_ provider: CloudProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: provider.keychainService,
         kSecAttrAccount as String: "api-key"]
    }
}

/// Retter én sætning ad gangen med Claude eller ChatGPT. Svaret går gennem `SpellingGuard` som Macens model.
struct CloudSpellingCorrector: SpellingCorrector {
    let provider: CloudProvider
    let key: String
    var level: SpellingLevel = .standard
    /// Får tokens fra hvert svar (til forbruget på siden Stavning). `nil` i stavetesten.
    var onUsage: (@Sendable (_ input: Int, _ output: Int) -> Void)?
    var source: SpellingSource { .cloud(provider) }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral // intet gemmes på disken
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func correct(_ sentence: String, language: Language) async throws -> String {
        let answer = try await send(instructions: SpellingPrompts.instructions(for: language, level: level, cloud: true),
                                    prompt: SpellingPrompts.prompt(sentence, language: language, level: level),
                                    maxTokens: max(200, sentence.count * 3))
        return Self.cleanAnswer(answer)
    }

    func choose(in sentence: String, candidates: [String], language: Language) async throws -> String {
        let list = candidates.map { "- \($0)" }.joined(separator: "\n")
        let instructions = language == .danish
            ? "Du vælger det ord fra listen, der passer bedst på pladsen ___ i en dansk sætning, så sætningen er rigtig dansk og giver mening. Svar kun med ordet, præcis som det står på listen."
            : "You choose the word from the list that fits best in the blank ___ in an English sentence, so the sentence is correct and makes sense. Reply only with the word, exactly as written in the list."
        let prompt = (language == .danish ? "Sætning: " : "Sentence: ") + sentence + "\n\n"
            + (language == .danish ? "Ord:\n" : "Words:\n") + list
        let answer = Self.cleanAnswer(try await send(instructions: instructions, prompt: prompt, maxTokens: 50))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•*\"'. "))
        // Svaret skal være ét af ordene; ellers står brugerens eget ord (det sidste på listen).
        return candidates.first { $0.lowercased() == answer.lowercased() } ?? candidates[candidates.count - 1]
    }

    /// En lille prøve, når brugeren trykker "Prøv" i indstillingerne. Sender kun en fast testsætning.
    func test() async throws {
        _ = try await correct("Jeg har ikke tit til det i dag.", language: .danish)
    }

    // MARK: Forespørgsel og svar

    private func send(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        let request = Self.request(provider: provider, key: key, instructions: instructions, prompt: prompt, maxTokens: maxTokens)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                throw CloudSpellingError.offline
            default:
                throw CloudSpellingError.failed
            }
        }
        guard let http = response as? HTTPURLResponse else { throw CloudSpellingError.failed }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw CloudSpellingError.badKey
        default: throw CloudSpellingError.failed // svaret læses ikke: det kan indeholde teksten
        }
        if let usage = Self.usage(from: data, provider: provider) { onUsage?(usage.input, usage.output) }
        guard let text = Self.text(from: data, provider: provider) else { throw CloudSpellingError.failed }
        return text
    }

    static func request(provider: CloudProvider, key: String, instructions: String, prompt: String,
                        maxTokens: Int) -> URLRequest {
        var request: URLRequest
        let body: [String: Any]
        switch provider {
        case .claude:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": provider.model, "max_tokens": maxTokens, "system": instructions,
                    "messages": [["role": "user", "content": prompt]],
                    "thinking": ["type": "between_tools"], "output_config": ["effort": "low"]]
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            // Tænke-tokens tæller med i loftet, derfor et rummeligt loft.
            body = ["model": provider.model, "instructions": instructions, "input": prompt,
                    "reasoning": ["effort": "low"], "store": false, "max_output_tokens": maxTokens + 2000]
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Teksten i svaret, eller `nil`, hvis modellen afviste eller svaret er tomt.
    static func text(from data: Data, provider: CloudProvider) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var parts: [String] = []
        switch provider {
        case .claude:
            if json["stop_reason"] as? String == "refusal" { return nil }
            for block in json["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "text" {
                parts.append(block["text"] as? String ?? "")
            }
        case .openai:
            for item in json["output"] as? [[String: Any]] ?? [] where item["type"] as? String == "message" {
                for content in item["content"] as? [[String: Any]] ?? [] where content["type"] as? String == "output_text" {
                    parts.append(content["text"] as? String ?? "")
                }
            }
        }
        let text = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Tokens, firmaet tager betaling for. Begge firmaer kalder dem `input_tokens` og `output_tokens`.
    static func usage(from data: Data, provider: CloudProvider) -> (input: Int, output: Int)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any],
              let input = usage["input_tokens"] as? Int, let output = usage["output_tokens"] as? Int else { return nil }
        return (input, output)
    }

    /// Første rigtige linje af svaret. Nogle modeller gentager opgaven ("Ret stavningen i denne tekst:") først (målt).
    static func cleanAnswer(_ answer: String) -> String {
        let lines = answer.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { line in
                let lower = line.lowercased()
                return !["ret stavningen", "fix the spelling", "ret og gør", "fix and make"].contains { lower.hasPrefix($0) }
            }
        return lines.first ?? ""
    }
}
