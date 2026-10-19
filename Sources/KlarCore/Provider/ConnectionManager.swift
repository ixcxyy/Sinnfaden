import Foundation
import Combine
import AppKit

@MainActor
public final class ConnectionManager: ObservableObject {
    @Published public private(set) var status: ConnectionStatus = .disconnected
    @Published public private(set) var statusMessage = "Noch nicht verbunden"
    @Published public private(set) var accountID: String?
    @Published public private(set) var models: [String] = []
    @Published public private(set) var modelNames: [String: String] = [:]
    @Published public var selectedModel = ""
    @Published public private(set) var providerKind: ProviderKind = .chatGPT
    @Published public private(set) var savedAccounts: [SavedAccount] = []
    @Published public private(set) var lastFailure: ProviderFailure?
    public var onFailure: ((Error) -> Void)?
    public var canGenerate: Bool { status == .connected && accountID != nil && models.contains(selectedModel) }
    public var activeAccountLabel: String { savedAccounts.first { $0.id == accountID }?.label ?? "Kein Konto ausgewählt" }
    private let secure = SecureStorage()
    private let transport = OpenAITransport()
    private var registrations: RegistrationStore?
    private var callback: LoopbackCallback?
    private var revision = UUID()
    private var refreshTasks: [String: Task<String, Error>] = [:]
    private var signOutTask: Task<Void, Never>?

    public init(restore: Bool = true) {
        do { registrations = try RegistrationStore.load(); savedAccounts = registrations?.accounts ?? [] }
        catch { status = .error; statusMessage = "Die gespeicherte Verbindung konnte nicht geladen werden." }
        if restore, let id = registrations?.selectedID { Task { await selectAccount(id) } }
    }

    public func restoreSelectedAccount() async -> Bool {
        guard let id = registrations?.selectedID else { return false }
        await selectAccount(id); return true
    }
    public func signIn() async { await authenticate(newAccount: false) }
    public func addAccount() async { await authenticate(newAccount: true) }
    public func enablePlanUsage() async { await authenticate(newAccount: false, consent: true) }

    private func authenticate(newAccount: Bool, consent: Bool = false) async {
        await signOutTask?.value
        guard status != .connecting, var registration = registrations else { return }
        let attempt = UUID(); revision = attempt
        let previousID = accountID
        status = .connecting; statusMessage = "Anmeldung im Browser …"; lastFailure = nil
        let selected = newAccount ? nil : registration.accounts.first { $0.id == (registration.selectedID ?? registration.lastSignedOutID) && $0.provider == .chatGPT }
        let savedClientID = selected?.clientID ?? (newAccount ? nil : registration.pendingClientID)
        let server = LoopbackCallback(); callback = server
        defer { server.cancel(); if revision == attempt { callback = nil } }
        do {
            let config = try await transport.configuration()
            try await server.start()
            let state = try OAuthProof.random(), nonce = try OAuthProof.random(), verifier = try OAuthProof.random(64)
            var components = URLComponents(url: config.authorization_endpoint, resolvingAgainstBaseURL: false)!
            var params = ["client_id": savedClientID ?? "dynamic_agent_client", "ext_agent_host_id": registration.hostID, "response_type": "code", "redirect_uri": server.redirectURI, "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct", "resource": "https://api.openai.com/v1", "state": state, "nonce": nonce, "code_challenge_method": "S256", "code_challenge": OAuthProof.challenge(verifier: verifier)]
            if savedClientID == nil { params["agent_name_hint"] = "Sinnfaden" }
            if consent { params["prompt"] = "consent" }
            if let selected, let token = try await secure.load(OAuthTokens.self, account: selected.id)?.idToken { params["id_token_hint"] = token }
            components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard revision == attempt, let url = components.url, NSWorkspace.shared.open(url) else { throw ProviderFailure(.authentication, "Der Systembrowser konnte nicht geöffnet werden.") }
            let returned = try await server.result()
            guard revision == attempt else { throw CancellationError() }
            let result = try Self.validateCallback(returned, state: state, savedClientID: savedClientID)
            // Persist an issued registration before exchanging the one-use code.
            if selected == nil { registration.pendingClientID = result.clientID; try registration.save(); registrations = registration }
            let data = try await transport.data(transport.form(config.token_endpoint, fields: ["grant_type": "authorization_code", "client_id": result.clientID, "code": result.code, "code_verifier": verifier, "redirect_uri": server.redirectURI, "resource": "https://api.openai.com/v1"]))
            let tokens = try Self.decodeTokens(data, previous: nil)
            guard let idToken = tokens.idToken else { throw ProviderFailure(.authentication, "OpenAI hat keine überprüfbare Identität geliefert.") }
            let keys = try await transport.json(JWKSet.self, url: config.jwks_uri)
            let identity = try IDTokenVerifier.verify(idToken, keys: keys, issuer: config.issuer, audience: result.clientID, nonce: nonce)
            if let selected, selected.subject != identity.subject { throw ProviderFailure(.authentication, "Das angemeldete Konto stimmt nicht mit dem ausgewählten Konto überein.") }
            guard revision == attempt else { throw CancellationError() }
            let id = OAuthProof.identityID(subject: identity.subject, clientID: result.clientID)
            let label = (identity.email ?? identity.name ?? "ChatGPT") + " · " + String(id.prefix(6))
            let account = SavedAccount(id: id, clientID: result.clientID, subject: identity.subject, label: label, provider: .chatGPT)
            let lock = SessionFileLock(); try await lock.acquire(); defer { lock.release() }
            guard revision == attempt else { throw CancellationError() }
            try secure.save(tokens, account: id)
            registration.accounts.removeAll { $0.id == id }; registration.accounts.append(account)
            registration.selectedID = id; registration.pendingClientID = nil; try registration.save()
            registrations = registration; savedAccounts = registration.accounts
            accountID = id; providerKind = .chatGPT; models = []; selectedModel = ""
            if !tokens.canUsePlan || tokens.accessToken == nil {
                status = .identityOnly; statusMessage = "Angemeldet · Nutzung noch nicht freigegeben"; return
            }
            status = .connected; statusMessage = "ChatGPT verbunden"
            // Keep the lock scoped to credential persistence; refreshModels may refresh.
            _ = lock
        } catch {
            guard revision == attempt else { return }
            accountID = previousID
            setFailure(error)
            return
        }
        if revision == attempt { await refreshModels() }
    }

    static func validateCallback(_ values: [String: String], state: String, savedClientID: String?) throws -> (code: String, clientID: String) {
        guard values["state"] == state else { throw ProviderFailure(.authentication, "Die Anmeldung konnte nicht sicher zugeordnet werden. Bitte starte sie erneut.") }
        if let error = values["error"] { throw ProviderFailure(.permission, error == "access_denied" ? "Die Anmeldung wurde nicht freigegeben. Du kannst sie später erneut starten." : "OpenAI konnte die Anmeldung nicht abschließen.", code: error) }
        guard let code = values["code"], !code.isEmpty else { throw ProviderFailure(.authentication, "Der Anmeldecode fehlt.") }
        if let savedClientID, let returned = values["client_id"], returned != savedClientID { throw ProviderFailure(.authentication, "Die Anmeldung gehört zu einer anderen Registrierung.") }
        guard let clientID = savedClientID ?? values["client_id"], !clientID.isEmpty, clientID != "dynamic_agent_client" else { throw ProviderFailure(.authentication, "Die Registrierung wurde nicht abgeschlossen.") }
        return (code, clientID)
    }

    public func cancelSignIn() {
        revision = UUID(); callback?.cancel(); callback = nil
        if accountID != nil && !models.isEmpty { status = .connected; statusMessage = "Vorherige Verbindung beibehalten" }
        else { status = .disconnected; statusMessage = "Anmeldung abgebrochen" }
    }

    public func selectAccount(_ id: String) async {
        await signOutTask?.value
        guard let account = savedAccounts.first(where: { $0.id == id }) else { return }
        let attempt = UUID(); revision = attempt; callback?.cancel()
        accountID = id; providerKind = account.provider; models = []; modelNames = [:]; selectedModel = ""
        status = .connecting; statusMessage = "Gespeicherte Anmeldung wird im macOS-Schlüsselbund geprüft …"
        do {
            registrations?.selectedID = id; try registrations?.save()
            if account.provider == .apiKey {
                let key = try await secure.load(String.self, account: id)
                guard revision == attempt else { return }
                guard key != nil else { status = .disconnected; statusMessage = "API-Schlüssel erneut eingeben"; return }
            } else {
                let loaded = try await secure.load(OAuthTokens.self, account: id)
                guard revision == attempt else { return }
                guard let tokens = loaded else { status = .disconnected; statusMessage = "Bitte erneut mit ChatGPT anmelden"; return }
                guard tokens.canUsePlan, tokens.accessToken != nil else { status = .identityOnly; statusMessage = "Angemeldet · Nutzung noch nicht freigegeben"; return }
            }
            status = .connected; statusMessage = "Verbindung wird geprüft …"; await refreshModels()
        } catch { if revision == attempt { setFailure(error) } }
    }

    public func connectAPIKey(_ key: String) async {
        await signOutTask?.value
        guard registrations != nil else { setFailure(ProviderFailure(.storage, "Die Kontodatei ist nicht verfügbar. Der API-Schlüssel wurde nicht gespeichert.")); return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { setFailure(ProviderFailure(.authentication, "Bitte gib einen gültigen API-Schlüssel ein.")); return }
        let attempt = UUID(); revision = attempt; status = .connecting; statusMessage = "API-Zugang wird geprüft …"
        do {
            let catalog = try await loadModels(token: trimmed, kind: .apiKey)
            guard revision == attempt else { return }
            let id = "api-" + OAuthProof.identityID(subject: trimmed, clientID: "api")
            let account = SavedAccount(id: id, clientID: "api", subject: id, label: "OpenAI API · " + String(id.suffix(6)), provider: .apiKey)
            try secure.save(trimmed, account: id)
            registrations?.accounts.removeAll { $0.id == id }; registrations?.accounts.append(account); registrations?.selectedID = id; try registrations?.save()
            savedAccounts = registrations?.accounts ?? []; accountID = id; providerKind = .apiKey
            applyModels(catalog); status = .connected; statusMessage = "OpenAI API verbunden · separate Abrechnung"; lastFailure = nil
        } catch { if revision == attempt { setFailure(error) } }
    }

    public func refreshModels() async {
        guard let id = accountID else { return }
        let attempt = revision
        let kind = providerKind
        do {
            let token = try await bearer()
            guard attempt == revision, id == accountID else { return }
            let catalog = try await loadModels(token: token, kind: kind)
            guard attempt == revision, id == accountID else { return }
            applyModels(catalog); status = .connected
            statusMessage = providerKind == .chatGPT ? "ChatGPT verbunden" : "OpenAI API verbunden · separate Abrechnung"; lastFailure = nil
        } catch { if attempt == revision { setFailure(error) } }
    }
    private func applyModels(_ catalog: [(String, String)]) {
        var seen = Set<String>()
        models = catalog.map(\.0).filter { seen.insert($0).inserted }
        modelNames = Dictionary(catalog, uniquingKeysWith: { first, _ in first })
        if !models.contains(selectedModel) {
            selectedModel = providerKind == .apiKey ? "" : models.first ?? ""
        }
    }
    private func loadModels(token: String, kind: ProviderKind) async throws -> [(String, String)] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!); request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let data = try await transport.data(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderFailure(.invalidResponse, "Die Modellliste konnte nicht gelesen werden.") }
        let list: [(String, String)]
        if kind == .chatGPT {
            list = (object["models"] as? [[String: Any]] ?? []).filter { $0["visibility"] as? String == "list" }.compactMap { item in
                guard let slug = item["slug"] as? String, !slug.isEmpty else { return nil }; return (slug, item["display_name"] as? String ?? slug)
            }
        } else {
            list = (object["data"] as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["id"] as? String, !id.isEmpty else { return nil }; return (id, id)
            }.sorted { $0.0 < $1.0 }
        }
        guard !list.isEmpty else { throw ProviderFailure(.permission, "Für dieses Konto wurden keine verfügbaren Modelle zurückgegeben.") }
        return list
    }

    public func generate(instructions: String, input: String, model requestedModel: String? = nil, onPartialText: (@Sendable (String) -> Void)? = nil, onProgress: @escaping @Sendable (Int) -> Void) async throws -> String {
        let model = requestedModel ?? selectedModel
        guard status == .connected, let id = accountID else { throw ProviderFailure(.authentication, "Bitte verbinde zuerst einen freigegebenen Zugang in den Einstellungen.") }
        guard models.contains(model) else { throw ProviderFailure(.permission, "Das gewählte Modell ist für dieses Konto nicht mehr verfügbar.", code: "model_not_in_catalog") }
        let attempt = revision
        do {
            let token = try await bearer()
            guard revision == attempt, accountID == id else { throw CancellationError() }
            let text = try await transport.generate(token: token, model: model, instructions: instructions, input: input, onPartialText: onPartialText, onProgress: onProgress)
            guard revision == attempt, accountID == id else { throw CancellationError() }
            return text
        } catch {
            if revision == attempt, let failure = error as? ProviderFailure {
                lastFailure = failure
                let next = Self.stateAfterFailure(failure, current: status)
                if next != status { status = next; statusMessage = failure.message }
            }
            throw error
        }
    }

    /// One explicit, tiny capability probe; never automatically applied to tutor requests.
    public func probeStructuredOutput() async throws -> Bool {
        guard canGenerate, providerKind == .chatGPT else { throw ProviderFailure(.authentication, "Ein freigegebener ChatGPT-Zugang ist erforderlich.") }
        let attempt = revision
        let model = selectedModel
        let token = try await bearer()
        guard revision == attempt else { throw CancellationError() }
        let format: [String: Any] = ["type": "json_schema", "name": "klar_connection_probe", "strict": true,
            "schema": ["type": "object", "properties": ["ok": ["type": "string", "enum": ["KLAR"]]], "required": ["ok"], "additionalProperties": false]]
        let output = try await transport.generate(token: token, model: model, instructions: "Liefere das vereinbarte JSON-Objekt mit ok gleich KLAR.", input: "Dies ist ein kleiner Structured-Outputs-Verbindungstest.", textFormat: format, onProgress: { _ in })
        guard revision == attempt else { throw CancellationError() }
        let parsed = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]
        return parsed == ["ok": "KLAR"]
    }

    private func bearer() async throws -> String {
        guard let id = accountID, let account = savedAccounts.first(where: { $0.id == id }) else { throw ProviderFailure(.authentication, "Bitte melde dich zuerst an.") }
        if account.provider == .apiKey {
            guard let key = try await secure.load(String.self, account: id) else { throw ProviderFailure(.authentication, "Der API-Schlüssel fehlt.") }; return key
        }
        if let refreshTask = refreshTasks[id] { return try await refreshTask.value }
        let transport = self.transport, secure = self.secure
        let task = Task<String, Error> {
            let lock = SessionFileLock(); try await lock.acquire(); defer { lock.release() }
            guard var tokens = try await secure.load(OAuthTokens.self, account: id), tokens.canUsePlan, let current = tokens.accessToken else { throw ProviderFailure(.permission, "Die Nutzung deines ChatGPT-Plans ist noch nicht freigegeben.", code: "missing_plan_scope") }
            if tokens.expiresAt > Date().addingTimeInterval(90) { return current }
            guard let refresh = tokens.refreshToken else { throw ProviderFailure(.authentication, "Bitte melde dich erneut an, um die Verbindung zu erneuern.") }
            do {
                let config = try await transport.configuration()
                let data = try await transport.data(transport.form(config.token_endpoint, fields: ["grant_type": "refresh_token", "client_id": account.clientID, "refresh_token": refresh, "resource": "https://api.openai.com/v1"]))
                let updated = try Self.decodeTokens(data, previous: tokens)
                if let idToken = updated.idToken, idToken != tokens.idToken {
                    let keys = try await transport.json(JWKSet.self, url: config.jwks_uri)
                    let identity = try IDTokenVerifier.verify(idToken, keys: keys, issuer: config.issuer, audience: account.clientID, nonce: nil)
                    guard identity.subject == account.subject else { throw ProviderFailure(.authentication, "Die erneuerte Anmeldung gehört zu einem anderen Konto.") }
                }
                tokens = updated
                guard tokens.canUsePlan, let token = tokens.accessToken else { throw ProviderFailure(.permission, "Die Plan-Nutzung ist nicht mehr freigegeben.", code: "missing_plan_scope") }
                try secure.save(tokens, account: id); return token
            } catch {
                if let failure = error as? ProviderFailure, ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(failure.code ?? "") { try secure.delete(account: id) }
                throw error
            }
        }
        refreshTasks[id] = task
        defer { refreshTasks[id] = nil }
        // Finish rotating-token persistence even when the caller cancels its generation.
        // The caller checks its own revision before inference; logout waits for the lock.
        let value = try await task.value
        try Task.checkCancellation()
        return value
    }

    static func decodeTokens(_ data: Data, previous: OAuthTokens?) throws -> OAuthTokens {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderFailure(.invalidResponse, "Die Anmeldeantwort konnte nicht gelesen werden.") }
        if let tokenType = value["token_type"] as? String, tokenType.lowercased() != "bearer" { throw ProviderFailure(.authentication, "Der empfangene Tokentyp wird nicht unterstützt.") }
        let access = value["access_token"] as? String
        let lifetimeValue = value["expires_in"] as? NSNumber
        let lifetime = lifetimeValue?.doubleValue ?? 0
        if let access {
            guard !access.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let lifetimeValue, CFGetTypeID(lifetimeValue) != CFBooleanGetTypeID(), lifetime.isFinite, lifetime > 0 else {
                throw ProviderFailure(.authentication, "Die Gültigkeitsdauer oder das Zugriffstoken der Verbindung ist ungültig.")
            }
        } else if previous != nil || (value["id_token"] as? String)?.isEmpty != false {
            throw ProviderFailure(.authentication, "Die Anmeldeantwort enthält kein gültiges Zugriffstoken.")
        }
        return OAuthTokens(accessToken: access, refreshToken: value["refresh_token"] as? String ?? previous?.refreshToken, idToken: value["id_token"] as? String ?? previous?.idToken, scope: value["scope"] as? String ?? previous?.scope ?? "", expiresAt: Date().addingTimeInterval(lifetime))
    }

    public func disconnect() {
        revision = UUID(); callback?.cancel(); callback = nil
        guard let id = accountID, let account = savedAccounts.first(where: { $0.id == id }) else { status = .disconnected; return }
        registrations?.markSignedOut(id)
        do { try registrations?.save() }
        catch { status = .error; statusMessage = "Die Abmeldung konnte nicht sicher gespeichert werden. Bitte versuche es erneut."; return }
        accountID = nil; models = []; modelNames = [:]; selectedModel = ""; status = .disconnected; statusMessage = "Abgemeldet"
        let transport = self.transport, secure = self.secure
        signOutTask = Task { [weak self] in
            var refresh: String?
            do {
                let lock = SessionFileLock(); try await lock.acquire(); defer { lock.release() }
                if account.provider == .chatGPT { refresh = try await secure.load(OAuthTokens.self, account: id)?.refreshToken }
                // Keep the revocation token only in memory. Local logout remains effective
                // even if the process quits while the remote revocation is pending.
                try secure.delete(account: id)
            } catch {
                self?.accountID = id; self?.status = .error
                self?.statusMessage = "Abmeldung im Schlüsselbund fehlgeschlagen. Bitte versuche es erneut."; return
            }
            var revoked = account.provider == .apiKey || refresh == nil
            if let refresh {
                for attempt in 0..<2 {
                    do {
                        let config = try await transport.configuration()
                        if let endpoint = config.revocation_endpoint {
                            var request = transport.form(endpoint, fields: ["token": refresh, "token_type_hint": "refresh_token", "client_id": account.clientID]); request.timeoutInterval = 10
                            _ = try await transport.data(request); revoked = true
                        }
                        break
                    } catch { if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) } }
                }
            }
            if !revoked { self?.statusMessage = "Lokal abgemeldet. Trenne Sinnfaden bei Bedarf zusätzlich in den ChatGPT-Einstellungen; die Bestätigung von OpenAI fehlt." }
        }
    }
    static func stateAfterFailure(_ failure: ProviderFailure, current: ConnectionStatus) -> ConnectionStatus {
        if failure.kind == .authentication { return .error }
        if failure.code == "missing_plan_scope" { return .identityOnly }
        if ["chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context", "subscription_sharing_user_not_eligible"].contains(failure.code ?? "") { return .error }
        return current
    }
    private func setFailure(_ error: Error) {
        onFailure?(error)
        if error is CancellationError { status = .disconnected; statusMessage = "Abgebrochen"; return }
        let failure = error as? ProviderFailure ?? ProviderFailure(.unavailable, "Die Verbindung konnte nicht abgeschlossen werden. Bitte prüfe deine Internetverbindung und versuche es erneut.")
        lastFailure = failure; status = .error; statusMessage = failure.message
    }
}
