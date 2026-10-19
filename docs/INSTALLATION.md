# Sinnfaden installieren

1. Öffne `Sinnfaden-0.4.2-arm64-development.dmg`.
2. Ziehe `Sinnfaden.app` in den angezeigten Ordner „Programme“.
3. Öffne Sinnfaden und verwende in den Einstellungen die offizielle ChatGPT-Anmeldung, sofern keine bestehende Verbindung wiederhergestellt wurde.

Dieser lokale Entwicklungsbuild ist **ad hoc signiert, nicht notarisiert**. Gatekeeper kann heruntergeladene Kopien daher ablehnen. Die macOS-Sicherheitsprüfung wurde nicht umgangen. Für eine regulär weitergebbare Ausgabe fehlen ein `Developer ID Application`-Zertifikat und ein zulässiges Notarisierungsprofil. `scripts/notarize.sh` enthält den reproduzierbaren Ablauf, kauft oder veröffentlicht nichts.

Geprüft: Apple Silicon (arm64), macOS 27.0. Deklariertes Minimum: macOS 14. Intel und ältere unterstützte Systemversionen wurden nicht praktisch getestet.

## Update von KLAR

Die Bundle-ID, bisherigen lokalen Daten, Schlüsselbundkennungen und OAuth-Registrierungen bleiben gleich. Sinnfaden kann den vorhandenen Verlauf und die Anmeldung weiterverwenden. Beende die alte KLAR-App vor dem Start der neuen App; führe beide Versionen nicht gleichzeitig aus. Alte App-Pakete lassen sich nach Sicherung entfernen, ohne den Ordner `~/Library/Application Support/KLAR` anzutasten.

## Bedienung

Schreibe deinen Prompt, fordere einen Vorschlag an und öffne die Erklärungen am markierten Text oder über die beschrifteten Schaltflächen. Leertaste/Return öffnen, Escape schließt; die Pfeiltasten wechseln zwischen Erklärungsschaltflächen. Ein Klick fixiert die Blase. Für große Schrift oder zu wenig Platz erscheint die Erklärung im Lesebereich.

„Kopieren & ChatGPT öffnen“ kopiert den aktuell sichtbaren Text vollständig und öffnet ChatGPT im Browser. Füge mit ⌘V ein und entscheide dort selbst über das Senden. Die Anmeldung des Coaches und die geöffnete ChatGPT-Sitzung sind voneinander unabhängig.

Die App bleibt weiß. Die Einstellungen bieten Schriftgröße sowie den lokalen Export und das Löschen von Lerninhalten. Den Prompt-Verlauf exportierst oder löschst du unter „Verlauf“.

## Neue Versionen und Fehlerberichte

Unter „Updates & Fehler“ kannst du nach neuen Versionen suchen und technische Fehlerberichte lokal ansehen oder exportieren. Automatische Übermittlung ist freiwillig. Im aktuellen Entwicklungsbuild fehlen noch der private Meldekanal und der signierte Release-Feed; das wird ausdrücklich angezeigt. [Aktivierung für die Entwicklung](MAINTENANCE.md). Bereits installierte ältere Versionen ohne Updater brauchen zunächst eine manuelle Installation.
