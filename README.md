# Sinnfaden

**Deine Gedanken. Klar formuliert.** Eine native macOS-App zum Promptenlernen, mit SwiftUI und AppKit. Projekt- und interne Modulnamen bleiben aus Kompatibilitätsgründen teilweise `KLAR`.

## Starten

Die gebaute App liegt unter `Artifacts/Sinnfaden.app`, das Installationsabbild unter `Artifacts/Sinnfaden-0.4.2-arm64-development.dmg`. Der Entwicklungsbuild ist lokal ad hoc signiert. Für reguläre Weitergabe fehlen Developer-ID-Signatur und Notarisierung; siehe [Installation](docs/INSTALLATION.md).

## Enthalten

- **Updates & Fehler:** lokale, inhaltsarme Fehlerberichte mit Export, optionaler Übermittlung an private GitHub-Issues und signierte App-Updates über Sparkle. Der Meldekanal und Release-Feed sind im Entwicklungsbuild noch nicht aktiviert. [Einrichtung und Grenzen](docs/MAINTENANCE.md) · [Backend-Prüfung](docs/BACKEND-AUDIT.md).

- Eigene ChatGPT-Anmeldung mit getrennter Freigabe zur Plan-Nutzung. Kein automatischer Wechsel zur separat berechneten API.
- Strukturierte, streng geprüfte Prompt-Vorschläge; echte Änderungen mit Erklärungen, manuell editierbar.
- Erklärungslinse: Aus der markierten Stelle wächst eine opaline Flüssigkeitslinse (Kern → Hals → Körper), folgt dem Cursor mit Trägheit, ändert beim Wechsel ihr Volumen und fließt beim Schließen in die Wörter zurück, umkehrbar mitten im Rückfluss. Textauswahl, Tastatur, Fixieren, Escape und Alternativen für reduzierte Bewegung/Transparenz bleiben erhalten. Aktuelle Aufnahmen: `Artifacts/Sinnfaden-Intro.mp4`, `Artifacts/Sinnfaden-App-Rundgang.mp4`.
- Exakte Übergabe des sichtbaren Texts: Auf dem geprüften Mac wird der vollständige Prompt kopiert und ChatGPT im Browser geöffnet. Automatisches Senden findet nicht statt. Die dokumentierte Desktop-Vorbefüllung bleibt bis zu einer echten Zieloberflächenprüfung deaktiviert.
- **Antworten vergleichen:** einzelne sicher rekonstruierte Änderung oder ausdrücklich gekennzeichneter Gesamtvergleich; zwei reale Antworten erst nach Klick, mit festgehaltenem Modell und unabhängigen Fehler-/Teilzuständen.
- **Selbst ausprobieren / Kurz lernen:** eigene Versuche vor der Lösung, Hinweise, sechs kompakte Lektionen und getrennte Aufzeichnung von Hilfe, Übernahme und selbstständiger Anwendung.
- **Antwort verfeinern:** eingefügte Antwort + Änderungswunsch → geprüfter Folgeprompt; Rückfragen und manuelle Bearbeitung bleiben erhalten.
- **Meine Vorlagen:** explizite Felder, Live-Vorschau, offene Angaben, eigene Vorlagen und Meta-Prompts, Bearbeitung, Umbenennung, Duplikate, Versionen, Verwendungsschnappschüsse und JSON-Export.
- Oberfläche 0.4: Intro bei jedem Start (der Faden zeichnet das S von „Sinnfaden“, beim ersten Start mit Profil und 12 Vektor-Avataren), milchiger Metal-Shader-Hintergrund, flüssiges Navigationsrad unten in der Mitte (⌘K), ruhiger Start mit einem Eingabefeld, flüssige Nachdenk-Animation, Ergebnis als Split View. Die KI baut passende Eingabefelder (Text, Auswahl, Skala, Datum, Zahl) für fehlende Angaben; der Prompt füllt sich live, damit ChatGPT nicht nachfragen muss. Über markierten Stellen wird der Cursor zur blauen Erklärungsblase; Klick hält sie fest. Alternativen für reduzierte Bewegung und Transparenz.
- Weißer Hintergrund, milchige Glasflächen, schwarze Bedienelemente und blaue Lernmarkierungen/Erklärungen. Adaptive Anordnung mit Entwurf und Vorschlag nebeneinander ab 1180 pt Fensterbreite. Systemschrift, Textgröße 16–24 pt und monochrome originale SVG-Identität.

## Reproduzierbar bauen

Voraussetzungen: macOS 14 oder neuer, Xcode/Command Line Tools mit Swift 5.10 oder neuer; Sparkle 2.10.0 wird beim ersten Build über Swift Package Manager geladen.

```sh
cd /Pfad/zum/Projekt/KLAR
swift test
./scripts/check-annotations.sh
./scripts/build-app.sh
./scripts/make-dmg.sh
```

Isoliertes Labor für die Erklärungslinse (kein Produktbildschirm, keine KI-Anfrage):

```sh
swift build && .build/debug/KLAR --demo --bubble-lab            # selbst mit der Maus prüfen
.build/debug/KLAR --demo --bubble-lab --autoplay                 # geskriptete Prüfsequenz mit Zustandslog
.build/debug/KLAR --demo --bubble-lab --autoplay --lab-reduce-motion --lab-reduce-transparency
.build/debug/KLAR --demo --ui-tour                               # Rundgang durch alle Seiten (Aufnahme: Artifacts/Sinnfaden-App-Rundgang.mp4)
.build/debug/KLAR --demo --intro                                 # Intro erneut zeigen (Aufnahme: Artifacts/Sinnfaden-Intro.mp4)
```

`KLAR_ARCH` und `KLAR_CONFIG` bleiben die kompatiblen Variablennamen. Der geprüfte Build ist arm64; ein Intel-Build wurde nicht geprüft. Ein echter Developer-ID-Build kann über `KLAR_SIGNING_IDENTITY` und ein bestehendes `KLAR_NOTARY_PROFILE` mit `scripts/notarize.sh` erstellt werden.

## Daten und Identität

Bundle-ID `at.klar.promptcoach`, OAuth-Registrierungen, Schlüsselbundkennungen und `~/Library/Application Support/KLAR` bleiben unverändert. Der bestehende SQLite-Verlauf wird nicht migriert oder überschrieben. Neue Lerndaten liegen als versionierte, atomar gespeicherte Datei beim jeweiligen Konto. Schreibvorgänge werden kurz zusammengefasst und beim regulären Beenden/Kontowechsel geleert. Beschädigte oder neuere Dateien bleiben unangetastet; Export verwendet den aktuellen Fensterinhalt auch bei einem Speicherfehler.

Verlauf und Lerndaten haben separate lokale Export- und Löschkontrollen. Rezepte werden bewusst angelegt; keine automatische Profilbildung aus persönlichen Angaben. Die KI verarbeitet nur ausdrücklich angeforderte Eingaben. Hover löst keine Anfrage aus.

## Nachweise und Grenzen

- [Neugestaltung 0.3 und Prüfergebnisse](docs/REDESIGN-VALIDATION.md)
- [Funktionsprüfung 0.2](docs/SINNFADEN-VALIDATION.md)
- [ChatGPT-Übergabe und Zielprüfung](docs/HANDOFF.md)
- [Offizielle Servicezeichen und Nutzungsfreigabe](docs/BRAND-SOURCES.md)
- [Originale Sinnfaden-Identität](Sources/KlarApp/Resources/Identity)
- [Anmeldung und Provider](docs/INTEGRATION.md)
- [Quellenregister und Aussagegrenzen](docs/EVIDENCE.md)

Sinnfaden ist die gewählte Arbeitsmarke; eine Marken- oder Domainfreigabe wird nicht behauptet. Einzelne KI-Vergleiche illustrieren Möglichkeiten und belegen keine allgemeine Wirksamkeit.
