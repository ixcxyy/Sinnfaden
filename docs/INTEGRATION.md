# OpenAI-Anbindung in KLAR

Stand der Dokumentationsprüfung: 18.10.2026. Native Swift-Implementierung ohne fremde OAuth-Client-ID, Cookies, übernommene Sitzungen oder interne ChatGPT-Endpunkte.

## Zugang und Einschränkung

KLAR bietet den in der offiziellen Dokumentation beschriebenen dynamischen öffentlichen OAuth-Flow für lokal ausgeführte Clients. Die Übersicht nennt lokal betriebene Apps; der Quickstart unterscheidet offene Integrationen und ausgewählte private Clients. Daraus wird keine allgemeine Freischaltung für jede private App abgeleitet. Der tatsächlich gewährte Login und Plan-Scope entscheiden über Modellnutzung. Es wurde kein Repository veröffentlicht und kein Dienst gebucht.

Die native Schaltfläche öffnet den Systembrowser. Die Nutzerin prüft dort Konto, Registrierung und Einwilligung selbst. Die App verwendet nur ihr eigenes Keychain-Service `de.klar.promptcoach.credentials.v1`. Sie liest keine Tokens anderer Apps. Anmeldung importiert keine ChatGPT-Verläufe oder Memories. Nutzung gehört laut Nutzerdokumentation zum vorhandenen Codex-/ChatGPT-Work-Kontingent und schafft kein zusätzliches Kontingent.

## Implementierte Schnittstelle

`ConnectionManager` ist MainActor-isoliert und veröffentlicht Verbindungszustand, erklärenden Status, aktive Konto-ID, gespeicherte Konten und den tatsächlichen Modellkatalog. `signIn()` verwendet die ausgewählte vorhandene Registrierung, `addAccount()` startet eine getrennte Registrierung, `selectAccount(_:)` schaltet zum gespeicherten Zugang um. `enablePlanUsage()` fordert nach bewusster Auswahl erneut den vollständigen Scope mit `prompt=consent` an. Ein Identitätslogin ohne `chatgpt.tokens.use.direct` bleibt `identityOnly` und erlaubt keine Generierung.

Konten sind aus verifiziertem Issuer, Subject und ausgegebener Client-ID abgeleitet. Gleiche E-Mail-Adressen verbinden keine getrennten Registrierungen. Kontowechsel leert den Katalog; späte Ergebnisse werden anhand einer Verbindungsrevision verworfen. Ein abgebrochener neuer Login ersetzt kein bereits bestätigtes Konto.

Optional eingegebene reguläre API-Schlüssel werden separat gespeichert. Dieser Provider wird nur durch `connectAPIKey` aktiviert. Es gibt keinen automatischen Wechsel nach einem Plan-Limit.

## OAuth und Geheimnisse

- OIDC-Discovery ausschließlich von `https://auth.openai.com/.well-known/openid-configuration`; Issuer und Endpoint-Hosts werden geprüft. Redirects werden für Token-/API-Anfragen nicht verfolgt.
- Öffentliche Registrierung: `dynamic_agent_client` ausschließlich als initialer Einstieg; tatsächlicher App-Name `KLAR`; anschließend Speicherung und Wiederverwendung der ausgegebenen ID. Eine schon ausgegebene ID bleibt auch nach fehlgeschlagenem Codeaustausch erhalten.
- Eine pro Installation gespeicherte `urn:uuid:`-Host-ID. Kein Personenbezug und keine Neuerzeugung beim gewöhnlichen Login/Logout.
- Frische kryptografische Zufallswerte für state, nonce und PKCE mit S256; 64 zufällige Bytes für den PKCE-Verifier.
- Network.framework-Listener bindet ausschließlich `127.0.0.1`, zufälliger verfügbarer Port, unveränderlicher Pfad `/auth/callback`. Host, Methode, Pfad, doppelte Parameter, state und zurückgegebene Client-ID werden geprüft. Timeout und Abbruch lösen den wartenden Vorgang auf.
- ID-Token: ausschließlich RS256; gültiger RSA-Schlüssel aus frischer JWKS, Signatur, exakter Issuer, Audience, azp bei mehreren Audiences, sub, exp, iat, optional nbf sowie ursprüngliche nonce. Bei Wiederanmeldung muss sub zur gewählten Registrierung passen. Das frische JWKS-Laden umfasst Schlüsselrotation; keine unbekannten Algorithmen werden stillschweigend akzeptiert.
- Tokens und API-Schlüssel nur in macOS Keychain; lokale Registrierungsmetadaten mit Verzeichnisrechten 0700 und Dateirechten 0600. Metadaten enthalten Kontolabel, Subject/Client-Mapping, Host-ID, aber keine Tokens oder Promptinhalte.
- Token-Erneuerung ersetzt rotierende Refresh-Tokens. Eine pro Konto zusammengefasste Refresh-Task und eine Dateisperre koordinieren App und Probe. Der Schreibabschluss einer Rotation wird durch Abbruch einer Textgenerierung nicht verworfen.
- Logout stoppt lokale Modellnutzung sofort und speichert zuerst, dass die Sitzung nicht automatisch wiederhergestellt werden darf. Nach Abschluss einer laufenden Token-Rotation wird der Widerruf-Token nur im Speicher behalten und die lokale Keychain-Kopie gelöscht; anschließend folgt der dokumentierte Widerruf mit begrenztem Wiederholungsversuch. So bleibt lokaler Logout auch bei Beenden während einer Netzwerkanfrage wirksam. Fehlende Widerrufbestätigung und fehlgeschlagene lokale Löschung werden sichtbar erklärt; die Löschung bleibt erneut ausführbar. Registrierung und Host-ID bleiben für bewusste Wiederanmeldung erhalten.

## Responses-Vertrag

Das Modell kommt aus `GET https://api.openai.com/v1/models` mit dem gewählten Konto. Beim SIWC-Provider werden nur Einträge mit `visibility: list` angezeigt; `display_name` dient der Anzeige, `slug` der Anfrage. Der reguläre API-Katalog verwendet `data[].id`. Der Katalog garantiert bei regulären API-Schlüsseln keine Textfähigkeit jedes Eintrags; deshalb bleibt die Modellauswahl dort leer, bis die Nutzerin ausdrücklich ein Textmodell auswählt. Modellfehler werden sichtbar behandelt.

Die Anfrage geht an `POST https://api.openai.com/v1/responses` und enthält genau `model`, `instructions`, ein `input`-Array, `store:false` und `stream:true`. Keine ausgeschlossenen Standardparameter, keine Tools, kein `previous_response_id`, keine unbeabsichtigten automatischen Wiederholungen.

Die reale SIWC-Antwort lieferte HTTP 200 ohne Content-Type, aber gültige SSE-Ereignisse. Ein fehlender Content-Type wird deshalb akzeptiert; ein explizit widersprechender Typ wird abgelehnt. SSE-Zeilengrenzen werden aus den Rohbytes gebildet, damit leere Ereignistrenner auf der getesteten Foundation-Version erhalten bleiben.

Der SSE-Parser behandelt `response.completed`, `response.failed`, `response.incomplete`, Refusal und Abbruch getrennt. Nur ein beobachtetes `response.completed` mit passendem Abschlussstatus gibt den fertigen Text zurück. Ein `[DONE]` allein genügt nicht. Größenlimits: 2 MB Eventgesamtumfang, 512 KB Einzelereignis, 256 KB Antworttext. Unvalidierte Textfragmente werden nicht als Vorschlag veröffentlicht; Fortschritt meldet nur die Anzahl empfangener Zeichen. Fehlerdaten bewahren Status, Code, Parameter und Request-ID soweit vorhanden, aber keinen potenziell vertraulichen Fehlertext oder Antwortbody in Logs.

Der produktive Tutor verwendet den begrenzten JSON-Textadapter mit strenger lokaler Vertragsprüfung. Ein gesonderter Live-Test bestätigte `text.format.type=json_schema`, `strict:true`, ein kleines festes Schema und `response.completed` für das tatsächlich verfügbare SIWC-Modell `gpt-6.1-sol`. Dieser Test bestätigt die Grundfunktion für dieses Konto/Modell; er bestätigt keinen vollständigen Coach-Schemaweg. Der produktive JSON-Textadapter bleibt deshalb klar getrennt. Genau ein gezielter Format-Reparaturversuch gehört zur übergeordneten Coach-Steuerung und bleibt sichtbar.

## Prüfvorrichtung und beobachteter Stand

```sh
swift test --filter ProviderTests
swift run KlarProbe --login
swift run KlarProbe --probe
swift run KlarProbe --structured-probe
swift run KlarProbe --coach-suite
```

`--login` startet bewusst den Browser. `--probe` verwendet ausschließlich die aktuell ausgewählte eigene gespeicherte KLAR-ChatGPT-Registrierung; ein aktiver API-Schlüssel wird nicht verwendet. Der Probe sendet eine kurze feste Textanfrage; ein erfolgreicher Test meldet das tatsächliche Modell und beobachtetes `response.completed`, aber weder Tokens noch persönliche Eingabe. Ohne KLAR-Anmeldung meldet er „NICHT AUSGEFÜHRT“ und Exitcode 2.

Beobachtet: 17 gezielte Provider-Tests bestanden auf arm64 macOS 27.0, darunter RFC-PKCE-Testvektor, ungültiger state, abgelehnte Einwilligung, abweichende Client-ID, echte RSA-Signatur und beschädigte Signatur, Claims-/Scope-Prüfung, exakter Request-Vertrag, Streamabbruch/Limit/unvollständig sowie ein tatsächlicher lokaler HTTP-Callback und dessen Abbruch. Ein zusätzlicher URLSession-Test speist einen synthetischen SSE-Stream Byte für Byte ohne Content-Type ein und prüft Unicode, leere Trennzeilen und erfolgreichen Abschluss. Logout-Metadaten und Folge-Zustände nach Auth-/Scope-/Limitfehlern sind gezielt geprüft. Der RSA-Test deckte einen Data-Indexfehler auf; dieser wurde korrigiert und der Test erneut bestanden.

Während der laufenden UI-Prüfung wurde ein eigenes KLAR-Konto vom Benutzer angemeldet. Die ersten kurzen Probes deckten den fehlenden Content-Type sowie die nicht erhaltenen SSE-Leerzeilen des verwendeten Foundation-Zeilenadapters auf. Beide Fehler wurden korrigiert. Der anschließende Live-Probe **bestand** mit tatsächlichem Kontokatalog, Modell `gpt-6.1-sol`, erwarteter Textantwort und beobachtetem `response.completed`. Der gesonderte Strict-JSON-Schema-Probe **bestand** ebenfalls. Kein API-Fallback, kein Logout und keine Änderung der Zustimmung wurden ausgeführt.

Die sechs synthetischen Alltagstasks sind in `Artifacts/live-coach-suite.json` mit tatsächlichen validierten Antworten dokumentiert. E-Mail, Erklärung, Zusammenfassung und kreatives Schreiben wurden als bereits klar unverändert zurückgegeben; Namen/Zahlen/Grenzen blieben erhalten. Die Planung fragte sinnvoll nach dem fehlenden Startort. Die wiederverwendbare Aufgabe benötigte genau einen angekündigten Format-Reparaturversuch und wurde anschließend ebenfalls als schon klar unverändert zurückgegeben. Insgesamt sieben Anfragen für sechs Fälle, keine auffälligen Literalprüfungen, keine behauptete Lernwirksamkeit. Ein live erzeugter `improved`-Fall ist durch diese sechs bereits detaillierten Eingaben nicht belegt.

Token-Erneuerung mit real abgelaufenen Credentials, reale Ablehnung, reale Kontowechsel und Serverwiderruf sind ungeprüft; lokale Vertragstests ersetzen diese Checks nicht.

## Offizielle Quellen

- https://developers.openai.com/siwc/quickstart
- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery
- https://developers.openai.com/siwc/token-sharing-open-source/token-reference
- https://developers.openai.com/siwc/website
- https://learn.chatgpt.com/docs/sign-in-with-chatgpt
- https://developers.openai.com/api/docs/guides/structured-outputs
