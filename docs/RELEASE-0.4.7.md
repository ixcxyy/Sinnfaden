# Sinnfaden 0.4.7 / Build 12 – Veröffentlichungsnachweis

Veröffentlicht und auf dem Mac installiert am **20. Oktober 2026, ca. 23:44 Uhr Europe/Vienna**. Reguläres Update mit kostenloser Entwicklungssignierung.

## Quellstand und Änderungen

- Release-Quellstand: `32314b7f0dda2e8382698af6159554527d68773a`, auf `main` gepusht.
- Enthält die geprüften Interaktionskorrekturen aus `9ca03039e2a94820af6bcd85a40310e75df8f9a9`: verlässliche Platzhalterfelder, bereinigte Hinweise nach dem Ausfüllen, Cursor-Zentrierung, korrigierte Wortpositionen und Animation bei Abbruch, schnellem Ergebnis oder ausgeblendeter App.
- Details und Grenzen der Oberflächenprüfung: [Interaktionsprüfung](INTERACTION-REVIEW-2026-10-20.md). Nutzerseitige Änderungen: [Release Notes](release-notes/0.4.7.md).
- Das Release-Skript erhält mit `--maximum-versions 0` alle bisherigen Feed-Einträge, statt ab der sechsten Version alte Downloads beim Staging zu entfernen.

## Erneut ausgeführte Prüfungen

- Swift: **203 Tests erfolgreich** (149 Core, 54 App).
- Native Annotationen: **78 Prüfungen erfolgreich**.
- Fehlerbericht-Dienst: Installation aus Lockfile, **17 Tests** und Syntaxprüfung erfolgreich.
- Release-Staging: **5 Tests erfolgreich**, einschließlich Signaturfehler, Pfadvalidierung und Größenlimit.
- Shell-Syntaxprüfung, manueller Diff-Review, `git diff --check`, Codegraph-Aktualisierung und Release-Build erfolgreich.
- Beide Cloudflare-Deployments zunächst als Dry Run geprüft.

## Paket

| Eigenschaft | Wert |
|---|---|
| Archiv | `Sinnfaden-0.4.7-12.zip` |
| URL | `https://sinnfaden-updates.sinnfaden-bug-relay.workers.dev/Sinnfaden-0.4.7-12.zip` |
| Größe | 3.750.612 Bytes |
| SHA-256 | `e3f438958aa2d1cf6768dff8a83aea50ecb313c28d96b52a2d82883f8d4f9ea7` |
| Architektur | arm64 |
| Signierung | Ad-hoc-Codesignatur; Sparkle Ed25519 für Feed, Pakete und Release Notes |

Die App ist **nicht Apple-notarisiert**. Es wurden keine kostenpflichtigen Dienste hinzugefügt.

## Echte Installation vor Veröffentlichung

- Separat entpacktes, vom Live-Host heruntergeladenes Build 11 unter `Artifacts/release-0.4.7-12/update-test/InstallTarget/`.
- Separater signierter Loopback-Feed auf `127.0.0.1:8772`; identisches Kandidatenarchiv, keine Änderung am produktiven Feed für den Test.
- Sparkle fand Build 12 und installierte es nach „Install and Relaunch“. Das Installationsziel meldet **0.4.7/12**, besteht die tiefe/strenge Codesignaturprüfung und enthält exakt die Binärdatei des Kandidaten.
- Sparkle startete den Testhelfer neu. Dieser blieb danach ohne Fenster in seiner Ereignisschleife und wurde nach Abschluss der Dateiprüfung beendet. Die tatsächlich aktualisierte App wurde zusätzlich direkt im lokalen Demomodus gestartet: Senden, Verarbeitungsanzeige, fertiges Ergebnis und Zutaten-Eingabefeld erfolgreich sichtbar.
- Test-App regulär geschlossen und Loopback-Server beendet.

## Veröffentlichung und Live-Prüfung

- Fehlerbericht-Dienst zuerst veröffentlicht; Allowlist um `0.4.7+12` ergänzt. Deployment: `91ef7fff-6c37-49f2-91ff-4ed02318b94d`.
- Update-Host danach veröffentlicht. Deployment: `8625b7ad-48b5-43de-9f9f-e31af914a052`.
- Live-Feed erneut über HTTPS geladen und Signatur geprüft. Enthaltene Builds: **12, 11, 10, 9, 8, 6**.
- **Alle 20 referenzierten Dateien** liefern HTTP 200, stimmen bytegenau mit dem geprüften Staging überein und bestehen ihre Ed25519-Prüfung. Die 13 bereits zuvor verlinkten Dateien behalten URL, Größe und SHA-256.
- Lokale Nachweise einschließlich Feed-Snapshots, Hashes und Build-/Deployment-Logs: `Artifacts/release-0.4.7-12/` (nicht in Git).

## Auf dem Mac installiert

- Bisheriges App-Bundle vorher unter `Artifacts/release-0.4.7-12/applications-backup/` gesichert.
- `/Applications/Sinnfaden.app` über die echte Funktion **„Nach Updates suchen …“** aktualisiert und neu gestartet.
- Installierte Version **0.4.7 / Build 12**, tiefe/strenge Codesignatur gültig, ausführbare Datei bytegleich zum veröffentlichten Paket: SHA-256 `7d7da0d2110d53fa4288335fcc850d57c3af3aa69ed3a8bfb07d1380f573e2ef`.
- App läuft aus `/Applications/Sinnfaden.app`. Gespeicherter Prompt und Anzeige **„ChatGPT verbunden“** nach Neustart vorhanden; keine Anmeldedaten geändert.
- Erneute Updateprüfung bestätigt ausdrücklich: **„Sinnfaden 0.4.7 is currently the newest version available.“**

Die kontinuierliche Hover-Bewegung und subjektive Animationsqualität bleiben zur persönlichen Abnahme offen; die vorherigen automatisierten und manuellen Nachweise werden nicht als vollständiger Bildratentest dargestellt.
