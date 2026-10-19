# Sinnfaden 0.2 — Ausführungsbericht

Stand: 18.10.2026. Diese Weiterentwicklung baut auf dem vorhandenen KLAR-Projekt auf. Der ältere Bericht `VALIDATION.md` beschreibt den vorherigen Stand, nicht die neuen Funktionen.

## Ergebnis

Native SwiftUI-/AppKit-App mit neuer Sinnfaden-Identität, dynamischer heller/dunkler Farbwelt, organischer Erklärungsblase, offizieller ChatGPT-Dienstmarke, ehrlicher Clipboard-/Browser-Übergabe sowie vier vollständigen Lernbereichen. Kein Website-Ersatz, kein simuliertes Login. Bestehende Bundle-, Schlüsselbund-, OAuth- und Datenkennungen bleiben erhalten.

## Ausgeführt und bestanden

| Prüfung | Beobachteter Nachweis |
|---|---|
| Release-Build arm64 | `Artifacts/sinnfaden-build.log`; App tatsächlich geöffnet |
| Automatisierte Tests | **69 Tests, 0 Fehler**, `Artifacts/sinnfaden-tests.log` |
| Native Annotationen | **55 Assertions**, `Artifacts/sinnfaden-native-checks.log`: Unicode, Umbruchgeometrie, tatsächliche Segmentabbildung, Dämpfung bei 30/60/120 Hz, Cursorgrenzen, unterbrochenes Retargeting, Verbindungskorridor, Membran, gemessene Inhalte, Platzmangel/Inline-Fallback, Cache-Invalidierung |
| Bestehende Anmeldung | Verbindung nach Umbenennung und normalem Neustart wiederhergestellt; keine neue Anmeldung nötig |
| Bestehender Verlauf | Sechs vorhandene Einträge sichtbar; gespeicherter Vorschlag erneut geöffnet |
| Helle/dunkle Oberfläche | Laufende App visuell geprüft; Hell über App-Einstellung aktiviert, dunkle Darstellung anschließend wieder gewählt |
| Originale Identität | Master, Mono, Light/Dark, eigenständig gezeichnete und in Flächen umgewandelte Wortmarke; PNG-Prüfbilder 16/24/64/1024 px angesehen |
| Offizielle Dienstgrafik | Originaldownload nach ausdrücklicher Zustimmung zu Markenbedingungen; unveränderte lokale Dateien mit Herkunft/Hashes |
| Bubble-Klick/Tastatur | Tatsächlich geöffnet und fixiert; vollständiger Text und Aktionen sichtbar; Escape kehrt zur richtigen Erklärung zurück, Leertaste öffnet erneut |
| Aha-Labor live | Aus bestehender Annotation vorbereiteter isolierter Zusatz; beide Prompts vorab sichtbar; nach Klick zwei echte Antworten mit `gpt-6.1-sol`; beide vollständig gespeichert |
| Aha-Navigation/Neustart | Wechsel während der Anfrage zu Lektionen; Rückkehr zeigt beide fertigen Antworten ohne Neuanforderung; nach echtem Neustart erneut vollständig verfügbar |
| Eigener Versuch | „Fasse den Text in drei kurzen Absätzen zusammen.“ wurde als konkrete Form-/Längenangabe erkannt und als eigener Versuch gespeichert |
| Folgeprompt live | Eingefügte allgemeine Antwort zur Tagesorganisation + Wunsch nach drei konkreten Schritten → echter validierter Folgeprompt mit passender Annotation; nach Neustart erhalten |
| Rezeptfelder | Leeres benötigtes Feld blockiert Übergabe; Live-Vorschau zeigt offene Angabe; mehrzeilige Unicode-Feldwerte bleiben exakt erhalten und nach Neustart verfügbar |
| Übergabe live | Expliziter Klick kopiert vollständigen Rezeptprompt und öffnet Browser; anschließendes ⌘V in lokalem Prüffeld stimmt einschließlich Umlaut, Emoji, Zeilenumbruch, Anführungszeichen und `& # + %` mit Vorschau überein; Prüfänderung verworfen, keine Nachricht gesendet |
| Lange Prompts/Link-Encoding | Automatisierte Roundtrip-/Fallbacktests, genau ein zulässiger Queryparameter, keine Kürzung |
| Lernen/Rezepte/Recovery | Automatisierte Tests für sechs Lektionen, tatsächliche Abweichungen, Hilfe/Kopie, eigene verschiedene Versuche, Versionen/Nutzungsschnappschüsse, Duplikatgrenzen, Kontotrennung, beschädigte/neue Speicherdateien, Rückfragenkontext, explizite offene Angaben, Teilantworten/Fehler, Cancellation und Unicode-Deltas |
| Lokaler UI-Export | `Artifacts/Sinnfaden-UI-Pruefexport.json`: vier Rezepte, eine Verwendung, ein eigener Lernversuch, ein Vergleich mit zwei vollständigen Antworten und ein verbesserter Folgeprompt; JSON erneut gelesen und geprüft |
| Unabhängige Codeprüfung | Konkrete Funde behoben und nachgeprüft; zuletzt keine offenen konkreten P1/P2-Befunde |
| Paketintegrität | Ad-hoc-Codesign verifiziert; DMG-Prüfsumme mit hdiutil validiert |
| Projektgraph | `graphify update .` aktualisiert; reine JSON-Belegdateien liefern erwartungsgemäß keine Codeknoten |

## Nicht bestanden / noch nicht für reguläre Verteilung freigegeben

**Gatekeeper bewertet den ad hoc signierten Entwicklungsbuild als `rejected`.** Das ist ein tatsächliches negatives Distributionsergebnis, kein bestandener Installationsnachweis für fremde Macs. Es fehlt ein Developer-ID-Application-Zertifikat; Notarisierung wurde nicht ausgeführt. Es wurde keine Sicherheitsprüfung umgangen.

Zwei frühe Testfehler (zu schwache Übungsbewertung bzw. falsch diskriminierende Netzwerk-Testfixture) und die konkreten Review-Funde wurden korrigiert. Sie sind im endgültigen Testlauf nicht mehr offen.

## Nicht ausgeführt / nicht belegbar

- **Kontinuierliches echtes Mausfolgen, schnelle Hover-Wechsel, Übergangskorridor, Auswahlziehen/Doppelklick und zeitliche Animationseindrücke:** implementiert bzw. rechnerisch/native-geometrisch geprüft, aber das verfügbare UI-Werkzeug besitzt keinen freien Pointer-Move-Befehl. Keine alternative Zeigerinjektion verwendet. Deshalb keine echte Interaktionsaufzeichnung, keine gemessene FPS-/Latenz-Aussage. Die Screenshots unten sind statische reale Bediennachweise, kein Ersatzbeweis für flüssiges Folgen.
- **VoiceOver sowie systemweite Reduzierte Bewegung/Transparenz und Erhöhter Kontrast:** Codepfade vorhanden; kein vollständiger manueller Assistenztechnik-Durchlauf in dieser Weiterentwicklung.
- **Desktop-Composer-Vorbefüllung:** offizielle Dokumentation und installierte signierte ChatGPT-App geprüft. Der Aufruf wurde versucht; das UI-Werkzeug verweigerte anschließend den Zugriff auf die Ziel-App. Composer-Inhalt und Alltagstauglichkeit der Zielansicht daher unbestätigt. Der ausgelieferte Weg ist ausdrücklich der Clipboard-/Browser-Fallback. Details in `HANDOFF.md`.
- Vollständiger nativer Test unter macOS 14, Intel-Build, frisches Fremdgerät, tatsächlicher Kontoentzug/Planlimit/Tokenablauf und umfangreiche Leistungsmessung mit sehr großen lokalen Sammlungen nicht durchgeführt.
- Native Löschvorgänge an vorhandenen Nutzerdaten wurden nicht ausgeführt; die gezielten Tests verwenden isolierte temporäre Speicherorte.

## Reale visuelle Nachweise

- `Artifacts/Sinnfaden-01-Start-dark.png`: neues Hauptfenster, dunkle Darstellung.
- `Artifacts/Sinnfaden-03-Eigener-Versuch.png`: tatsächlicher eigener Lernversuch und Rückmeldung.
- `Artifacts/Sinnfaden-04-Echter-Vergleich.png`: beide realen Antworten.
- `Artifacts/Sinnfaden-05-Rezept-Handoff.png`: Übergabe und Vorschau.
- `Artifacts/Sinnfaden-06-Rezepte-light.png`: helle Darstellung, wiederhergestellte Rezeptwerte.
- `Artifacts/Sinnfaden-07-Echter-Folgeprompt.png`: echter Folgeprompt aus eingefügtem Text.
- `Artifacts/Sinnfaden-08-Bubble-final.png`: endgültige helle, fixierte Blase mit vollständigem Text und Aktionen.

`Sinnfaden-02-Bubble-pinned.png` dokumentiert einen Zwischenstand vor der abschließenden Materialkorrektur. Maßgeblich für die endgültige Blase ist Bild 08.

## Umgebung und Distribution

MacBook Pro, Mac17,8, Apple M5 Pro, 48 GB RAM; macOS 27.0 (26A428); Xcode 27.0 (27A266a); Apple Swift 6.4. Ziel: macOS 14, arm64. Keine Behauptung einer auf diesem Gerät gemessenen Framerate.

Artefakte: `Artifacts/Sinnfaden.app`, `Artifacts/Sinnfaden-0.2-arm64-development.dmg`, `Artifacts/Sinnfaden-Logo-Set.zip`, `Artifacts/Sinnfaden-0.2-source.zip`. Anleitung: `README.md`, `docs/INSTALLATION.md`, reproduzierbare Skripte unter `scripts/`.

## Auftragsklärung und Verbesserung für den nächsten Auftrag

Die Formulierung „ChatGPT-Desktop-App“ war auf diesem Mac mehrdeutig: Die installierte App heißt ChatGPT, verwendet jedoch `com.openai.codex` und den dokumentierten `codex://`-Link. Mangels beobachtbarem Ziel-Composer wurde die konservative, korrekt beschriftete Browser-Übergabe gewählt.

Ein hilfreicher Zusatz für den nächsten Auftrag: **„Lege vorab einen manuell begleiteten Maus-/VoiceOver-Abnahmetermin und das konkrete signierte Zielgerät fest; trenne dabei funktionalen Entwicklungsbuild und notarisierten Verteilungsbuild als eigene Abnahmekriterien.“**
