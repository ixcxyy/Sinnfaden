# Interaktionsprüfung vom 20. Oktober 2026

## Umfang

Unabhängige Prüfung der noch nicht committeten Claude-Änderungen auf Basis von
`46e0000`: Platzhalterfelder, Cursor-Erklärungen und Sende-/Ladeanimation.
Die bestehenden Farben, Karten, Navigation und Grundgestaltung bleiben erhalten.
Die geprüften Claude-Änderungen und die unten genannten Korrekturen werden gemeinsam
auf `main` übernommen.

## Zusätzlich behobene Fehler

- Ein bereits guter Prompt mit gewöhnlichen eckigen Klammern konnte am Kopierschutz
  hängen bleiben, obwohl kein Eingabefeld existierte. Der Schutz gilt jetzt für
  verbesserte Prompts; orange markiert werden nur tatsächliche Eingabeplatzhalter.
- Die Reparatur falsch benannter Modellfelder konnte einen ungesicherten Vorschlagswert
  übernehmen oder mehrere Felder nach ihrer Reihenfolge falsch zuordnen. Nur ein
  eindeutiges einzelnes Paar übernimmt Beschriftung und ID, niemals den Vorschlagswert.
  Mehrdeutige Fälle erhalten neutrale Textfelder.
- Die Hover-Geometrie orientierte sich an der Überschrift statt am Mittelpunkt.
  Der Cursor ist jetzt im freien Fensterbereich das geometrische Zentrum; ein
  ausgeglichener Textaufbau hält dort Platz frei. An Fensterrändern bleibt die
  bestehende Begrenzung aktiv.
- Gruppierte fliegende Wörter verloren ursprüngliche Abstände und Zeilenpositionen.
  Die Gruppen behalten jetzt die einzelnen Textfragmente und ihre Positionen.
- Die native Worterfassung ließ Satzzeichen, Eurozeichen und Emojis aus und erfasste
  umgebrochene lange Wörter als mehrzeilige Rechtecke. Die Erfassung erfolgt jetzt
  einschließlich dieser Zeichen pro tatsächlich dargestellter Zeile.
- Ein ausstehender Fokuswechsel konnte nach dem Verlassen eines Ergebnisses noch
  dessen Feld aktivieren. Ergebniswechsel löschen Fokus und Kopierhinweise; verzögerte
  Fokusaktionen prüfen, ob ihr Ergebnis noch aktuell ist.
- Beim Ausblenden während des Wortflugs konnte ein pausierter Zeitgeber einen alten
  Zwischenstand behalten. Der abgeschlossene Zustand wird ausdrücklich gerendert.
- Nach dem Ausfüllen stand weiterhin „Dein Name fehlt“ im Hinweis und in der Mindmap.
  Hinweise, deren sämtliche benannten Platzhalter ausgefüllt sind, verschwinden aus
  der aktuellen Darstellung. Teilweise offene und andere Hinweise bleiben erhalten;
  das Leeren eines Feldes stellt seinen ursprünglichen Hinweis wieder her.

## Prüfung und Nachweise

- Ausgangsstand: 195 Swift-Tests erfolgreich. Zusätzliche Regressionstests reproduzierten
  die Klammer-, Vorschlagswert-, Wortgruppen-, Zeichenerfassungs-, Zentrierungs- und
  Hinweisfehler vor ihrer Korrektur.
- Endstand: `swift test` erfolgreich, **203 Tests** (149 Core, 54 App), keine Fehler.
- `scripts/check-annotations.sh`: **78 native Prüfungen** erfolgreich.
- `scripts/build-app.sh`: Release-Konfiguration erfolgreich gebaut.
- `codesign --verify --deep --strict`: Test-App erfolgreich geprüft; lokale
  Entwicklungssignatur, keine Apple-Notarisierung.
- Manueller Diff-Review und `git diff --check` durchgeführt; Codegraph aktualisiert.

In der separat gebauten App über die macOS-Oberfläche geprüft:

1. Essensplan: oranger Platzhalter führt nach dem Einzelklick ins Zutatenfeld;
   mehrzeilige Eingabe aktualisiert den Prompt und bewahrt die Grenzen.
2. Kopieren mit leerem Feld zeigt den Hinweis und fokussiert das Feld. Nach dem
   Ausfüllen funktioniert Kopieren. Rasterwechsel und Wiederöffnen aus dem Verlauf
   erhalten die Eingaben (im zuerst geprüften Kandidaten).
3. E-Mail-Beispiel: zwei Auswahlchips gemeinsam setzen, Namensfeld ausfüllen,
   Tonskala ändern; alle Werte erscheinen korrekt im Prompt.
4. Hinweis-Regression im finalen Build: Name eintragen entfernt sowohl den
   Fehlhinweis als auch den entsprechenden offenen Mindmap-Knoten.
5. Absenden per Command-Return, sichtbare Wort-/Ladeanimation, Abbrechen und
   erneutes Absenden; Entwurf einschließlich Emoji und Zeilenumbrüchen bleibt erhalten.
6. Fenster während der Verarbeitung ausblenden: Rückkehr zeigt das fertige Ergebnis
   ohne zurückgebliebene fliegende Wörter.
7. Textauswahl auf blauen Stellen und explizite Erklärung mit Escape-Schließen.
   Die Hover-Blase wurde zusätzlich sichtbar ausgelöst; Zentrierung, Randbegrenzung,
   Dämpfung und Größenwechsel sind durch native Prüfungen abgesichert.

## Grenzen und Auslieferung

Die Oberflächentests verwendeten lokale Demoantworten, keine neue Live-KI-Bewertung.
Kein ChatGPT-Login wurde geändert und es entstanden keine API- oder Hostingkosten.
Die kontinuierliche freie Mausbewegung lässt sich mit dem verfügbaren UI-Werkzeug
nicht separat von einem Klick auslösen; eine vollständige manuelle Bewegungs- oder
Bildratenabnahme wird deshalb nicht behauptet. Die Entwickleroption zur internen
Hover-Demonstration wurde für diesen Nachweis nicht ausgeführt.

Die Test-App und lokale Logs liegen unter `Artifacts/codex-interaction-review/`
(nicht im Git-Repository). Ein Screenshot dokumentiert die bereinigte Darstellung.
Dieser Auftrag liefert den geprüften Quellstand auf GitHub. Die installierte App,
Versionsnummer und der veröffentlichte Update-Feed wurden nicht ersetzt; ein neues
Release benötigt weiterhin die Prüfungen aus `docs/CLAUDE-UPDATE-RELEASE.md`.
