# Sinnfaden 0.3 — weiße Oberfläche

Stand: 18.10.2026. Die jüngste Nutzeranweisung ersetzt die frühere warme Farbwelt: Weiß als Hintergrund, Schwarz/Weiß/Grau für die App, Blau für Lernmarkierungen und Erklärungen.

## Umsetzung

- Weiße Darstellung unabhängig von der Systemeinstellung; keine widersprüchliche Dunkel-Auswahl mehr.
- Milchige native Materialflächen mit weißer Auflage, weichen Schatten und klaren Kanten. Text bleibt scharf. Bei reduzierter Transparenz sind die Flächen deckend.
- Schwebende, gegliederte Navigation mit erreichbarem Einstellungsbereich auch bei geringer Fensterhöhe; aktuelle Seite ist für Bedienungshilfen ausgezeichnet.
- Größerer Schreibbereich, Entwurf und Vorschlag nebeneinander ab 1180 pt, darunter gestapelt. Kurze Erklärungen zum Ablauf.
- Schwarze Hauptaktionen und erkennbare sekundäre Buttons mit konkreten deutschen Beschriftungen: Text kopieren, Text bearbeiten, Als Vorlage speichern.
- Monochrome originale Wort-/Bildmarke und App-Icon. Unveränderte offizielle ChatGPT-Marke.
- Helle blaue Bubble mit gut lesbarem blauem Text; native Bewegung und Interaktionslogik erhalten.
- Verbindungsanzeige unterscheidet ChatGPT-Plan und OpenAI API; bereits gute Prompts werden als solche bezeichnet. Der Rückfrage-Shortcut übernimmt die Ergänzung.

## Bestanden

| Prüfung | Ergebnis |
|---|---|
| Release-Build Apple Silicon | Erfolgreich, App gestartet; `Artifacts/sinnfaden-redesign-package.log` |
| Tests | 69 Tests, 0 Fehler; `Artifacts/sinnfaden-redesign-tests.log` |
| Native Annotationen | 55 Assertions bestanden; `Artifacts/sinnfaden-redesign-native.log` |
| Visuelle Prüfung | Weißer Start, breite Zweispaltenansicht, blaue Bubble mit vollständiger Erklärung und Schließen über Escape |
| Kompaktes Fenster | macOS-Viertelfenster, Screenshot 1730×1298 px: Navigation, Scrollen und Ergebnisaktionen erreichbar |
| Datenbestand | Bestehende Verbindung nach Neustart wiederhergestellt, vorhandenen Verlauf und echten Vorschlag geöffnet |
| Kontrast | Blau auf blauer Lesefläche ca. 4,98:1; Sekundärtext auf Weiß ca. 5,46:1 |
| Unabhängige Code-Review | Providerbeschriftung, Already-good-Beschriftung, Rückfrage-Shortcut, Seitenauswahl, Fensterhöhe und Platzhalterkontrast korrigiert |
| Paket | Lokale Ad-hoc-Signatur geprüft; DMG erzeugt und geprüft |

Interaktionsnachweise: `Artifacts/09-Weiss-Kompakt.png`, `10-Weiss-Aktionen.png`, `11-Weiss-Arbeitsplatz.png`, `12-Weiss-Blaue-Bubble.png`.

## Grenzen

Keine fehlgeschlagenen Funktionsprüfungen offen. Kontinuierliches Hover/Folgen als reale Mausbewegung und Video/FPS wurden mit der verfügbaren Bedienautomation nicht erneut geprüft. VoiceOver als End-to-End-Sitzung, Änderungen der systemweiten Barrierefreiheitseinstellungen sowie Intel/macOS 14 wurden nicht ausgeführt. Die 69 Tests wurden vor den letzten rein visuellen Anpassungen von Platzhalter-Deckkraft, Shortcut-Hinweis und Speichersymbol ausgeführt; der finale Stand wurde erneut gebaut.

Der Build ist weiterhin lokal ad hoc signiert, nicht notarisiert. Reguläre Weitergabe benötigt Developer-ID-Signatur und Notarisierung. Die frühere Gatekeeper-Ablehnung eines Entwicklungsbuilds ist dadurch nicht aufgehoben.

## Artefakte

- `Artifacts/Sinnfaden.app`
- `Artifacts/Sinnfaden-0.3-arm64-development.dmg`
- `Artifacts/Sinnfaden-0.3-source.zip`
- `Artifacts/Sinnfaden-0.3-Logo-Set.zip`
- `Artifacts/Sinnfaden-0.3-SHA256SUMS.txt`

Interpretation der Formulierung „milky unscharf“: Unschärfe betrifft Material und Hintergrund, nicht Schrift. Für eine nächste Gestaltungsrunde wäre ein einzelnes gewünschtes Referenzfenster mit Zielgröße die hilfreichste Ergänzung.
