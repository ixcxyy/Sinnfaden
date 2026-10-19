# Prüfbericht – KLAR 0.1

Stand: 18. Oktober 2026. Nur beobachtete Ergebnisse; keine Wirksamkeitsbewertung der App.

## Gerät und Build

- MacBook Pro (Mac17,8), Apple M5 Pro, 48 GB RAM.
- macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4; Swift-Sprachmodus 5, Mindestdeployment macOS 14.
- Debug und Release erfolgreich gebaut. Tatsächliche Zielarchitektur arm64; kein Universal-Build.
- App-Bundle: `Artifacts/KLAR.app`; eigene ad-hoc-Signatur, `codesign --verify --deep --strict` erfolgreich.
- Vorhanden ist ein Apple-Development-Zertifikat, aber kein Developer-ID-Application-Zertifikat. Notarisierung/Stapling wurden nicht ausgeführt. Entwicklungs-DMG ist kein regulär freigegebener Installer.

## Automatisierte Prüfung

`swift test`: **40 Tests bestanden**, darunter:

- Coach-Vertrag, Schema- und Größenprüfungen, echte Originalzitate, eindeutige IDs/Referenzen, null Änderungen bei already_good und getrennte Entfernungen.
- UTF-16-Bereiche mit Umlauten, Emoji, Kombinationszeichen, Wiederholungen und Zeilenumbrüchen; keine Segmentgrenze innerhalb eines Graphems.
- Pipeline: genau ein sichtbarer Reparaturversuch, kein Retry bei Transportfehlern, Abbruch vor verspäteter Rückgabe und vor Reparatur, Eingabelimit vor Netzwerkaufruf.
- RFC-PKCE-Testvektor, state/clientID/Consent-Fehler, tatsächlich generierte RSA-Signatur mit Manipulationsprüfung, Issuer/Audience/Nonce/Zeit, Plan-Scopes und Kontoabgrenzung.
- Isolierter echter Loopback-Listener und dessen Abbruch; SSE-Abschluss, failed/incomplete/[DONE], fehlender MIME-Header und byteweise Foundation-Streamrahmung.
- SQLite-Neustart, kontogetrenntes Löschen, Export, private Dateirechte, Schutz vor unbekannter neuerer Datenbankversion.
- Konkretes lokales Feedback für Ausgabeformen, verneinte Ausgabeformen, Grenzen und Uhrzeiten. Unterstützte Versuche zählen nicht zur selbstständigen Übungsfolge.

`scripts/check-annotations.sh`: **36 native Assertions bestanden**. AppKit-Textlayout mit drei Breiten (220, 560, 1000 pt), zwei Schriftgrößen (17, 26 pt), wiederholtem Unicode-Text und Bubble-Positionen an Fensterrändern.

Ein unabhängiger Swift-Review wurde durchgeführt. Gefundene Probleme wurden korrigiert: RSA-Datenindex, Erhalt beantworteter Rückfragen beim Retry, Logout-Wiederherstellung, echte Auth-Fehlerzustände, versehentliche Wahl eines Nicht-Text-API-Modells, Mehrsegmentanker, Navigationsentwürfe, Übungsübernahmen und Paketressourcen. SwiftLint war nicht installiert.

## Echte OpenAI-Integration

Der Benutzer schloss die Anmeldung selbst im Systembrowser ab. Beobachtet wurden eigene dynamische KLAR-Registrierung, gewährte Plan-Nutzung, tatsächlicher Kontokatalog und `gpt-6.1-sol`.

- Kurzer Live-Probe bestanden: erwartete Textantwort und **response.completed**.
- Separater Strict-JSON-Schema-Probe bestanden: `text.format.type=json_schema`, `strict:true`, kleines Schema, vollständig abgeschlossene Antwort. Der produktive vollständige Coach-Vertrag nutzt weiterhin den begrenzten JSON-Textadapter und strenge lokale Validierung. Der vollständige Coach-Schemaweg wurde nicht als Structured Output geprüft.
- Erste Probes deckten fehlenden Content-Type trotz SSE und verlorene Leerzeilengrenzen des Foundation-Zeilenadapters auf. Korrigiert auf strenge byteweise SSE-Rahmung; fehlendes MIME allein gilt nicht mehr als Fehler. Explizit widersprüchliches MIME und fehlender Abschluss bleiben Fehler.
- Kein kostenpflichtiger API-Fallback. Es wurden keine fremden Sitzungen verwendet.

Sechs synthetische Alltagstasks, sieben Requests einschließlich genau einer Format-Reparatur, sind in `Artifacts/live-coach-suite.json` mit tatsächlichen Eingaben und validierten Ergebnissen dokumentiert:

| Aufgabe | Beobachtung |
|---|---|
| E-Mail | already_good, Original mit Frau Berger, 24. Oktober, 14 Uhr und 80 Wörtern exakt erhalten |
| Erklärung | already_good, Vorgaben zu Photosynthese, fünf Sätzen und Alltagsvergleich exakt erhalten |
| Planung | needs_clarification: sinnvolle Rückfrage nach dem Startort; keine fertige Ausgabe behauptet |
| Zusammenfassung | already_good, Namen und Zahlen exakt erhalten |
| Kreatives Schreiben | already_good, Lina, Komet, 120 Wörter und Grenze zum Ende exakt erhalten |
| Wiederverwendbare Aufgabe | nach einmaliger Format-Reparatur already_good; Teamgröße, Freitag, 45 Minuten und Kosten-Grenze exakt erhalten |

Diese bereits recht konkreten Prompts prüfen vor allem Zurückhaltung und Faktenerhalt. Sie beweisen keine allgemeine Promptverbesserung. Zusätzlich wurde in der nativen App der grobe Beispielprompt zur Terminverschiebung tatsächlich überarbeitet: ein gültiger improved-Vorschlag ergänzte sichtbare Platzhalter und erklärte diese passend. Screenshot `02-Echter-Vorschlag.png`.

## Bedienung der laufenden App

Beobachtet über native Mac-UI-Automation:

- Startansicht, Beispieleingabe, Wechsel Verlauf ↔ Dein Prompt mit erhaltenem Entwurf.
- Echte Verbindung sowie echte Fehlermeldung der zunächst fehlerhaften Streamverarbeitung; anschließend gültiger echter Vorschlag.
- Erklärungsbutton öffnet passende Bubble, Inhalt unbeschnitten; Escape schließt. Im abschließenden Build kehrt der Fokus zum passenden Erklärungsbutton zurück.
- „Prompt kopieren“ und Einfügen in den Editor ergeben exakt den sichtbaren Text ohne Erklärungen, Links oder Markierungszeichen.
- Eigene Ergänzung gespeichert; blaue Markierungen verschwinden und deren Aufhebung wird erklärt.
- Freiwillige eigene Antwort mit konkretem Datum/Uhrzeit eingegeben, Feedback zur tatsächlichen Antwort und verwendete Hilfe gespeichert. Die daraufhin präzisierte Zeitpunkterkennung ist zusätzlich automatisiert geprüft.
- Nativer Exportdialog gespeichert: `Artifacts/KLAR-UI-Pruefexport.json`, gültiges JSON mit fünf Einträgen, einer bearbeiteten Fassung und einem Übungsversuch. Diese Datei ist ein lokaler Bediennachweis und wird nicht automatisch übertragen.
- Große Schrift über den App-Schieberegler erreichbar. Weitere finale Layoutbeobachtungen werden unten ergänzt.

Die Screenshots zeigen echte laufende Fenster. Demo-Bilder sind im Dateinamen und in der Oberfläche ausdrücklich als Demo gekennzeichnet.

## Abnahme und verbleibende Grenzen

| Kriterium | Status und Grenze |
|---|---|
| A1 | Echte improved-Ausgabe in der UI; fünf echte already_good-Ausgaben ohne Änderungen; Kopie überprüft |
| A2 | Namen/Zahlen/Termine in den synthetischen Live-Fällen erhalten; echte Rückfrage nach Startort; keine allgemeine semantische Garantie |
| A3 | Unicode/UTF-16 automatisiert und nativer Kopierweg geprüft |
| A4 | Strukturprüfung, getrennte Entfernungen und sichtbare Annotation-Aufhebung nach eigener Bearbeitung geprüft |
| A5 | Öffnen/Schließen/Fokusrückgabe nativ bedient; Layout-Geometrie automatisiert. Hover-Übergangszone, jeder Tastaturpfad und VoiceOver noch nicht vollständig manuell geprüft |
| A6 | Echter Login/Plan-Scope/Katalog/Inference bestanden. Echte abgelehnte Zustimmung, abgelaufene Tokens, Kontowechsel und Serverwiderruf nicht durchgeführt; entsprechende lokale Tests vorhanden |
| A7 | Transportfehler tatsächlich gesehen; Parser, ein Reparaturversuch und späte Abbruchantworten geprüft. Keine flächendeckenden realen Netzunterbrechungen oder Quotenüberschreitungen provoziert |
| A8 | SQLite-Neustart/Export/Löschen automatisiert; echter UI-Export vorhanden. Echter Kontoverlauf wurde nicht zu Testzwecken gelöscht |
| A9 | Eigene Antwort und Hilfen gespeichert; mehrere lokale Feedbackfälle geprüft. Kein Kompetenz- oder Wirksamkeitsnachweis |
| A10 | Auf genanntem Mac gestartet und bedient, Screenshots gespeichert. Keine Bildratenmessung, keine belastbare Aussage über 60 fps oder Ruckler; Zielgerät der Nutzerin unbekannt |

Weitere offene Punkte: Intel/macOS-14-Gerätetest, echte VoiceOver-Sitzung und systemweite Reduce-Motion/Transparency/Contrast-Prüfung. Material-Fallbacks sind implementiert, nicht auf jedem unterstützten Betriebssystem live überprüft. Sechs vollständige Lessons bleiben bewusst die anschließende Erweiterung.

## Abschließende Großschriftprüfung

Die laufende Demo wurde über den App-Schieberegler auf **24 pt** gestellt. Der Prompt brach korrekt um; eine Erklärung erschien automatisch als lesbare Inline-Fläche unter dem Text. Screenshot: `Artifacts/04-Demo-Grosse-Schrift.png`. Die Daten dieses Nachweises sind lokal hinterlegte Demonstrationsdaten. Die reale KI-Ausgabe ist separat in Screenshot 02 dokumentiert.

Die Gatekeeper-Bewertung (`spctl --assess --type execute`) meldet für diesen ad-hoc signierten Entwicklungsbuild **rejected**, wie ohne reguläre Developer-ID-/Notarisierungsfreigabe zu erwarten. Das DMG wurde erzeugt und seine Prüfsumme mit `hdiutil verify` als **VALID** bestätigt. Es wurde keine Sicherheitsfunktion deaktiviert oder umgangen.

## Abschließende Tastaturprüfung im Release-Build

Mit lokal gekennzeichneten Demodaten tatsächlich bedient: erste Erklärung geöffnet → Schließen-Knopf erhält Fokus → Escape → Fokus auf ursprünglichem Erklärungsbutton → Pfeil ab → Leertaste → zweite passende Erklärung geöffnet → Leertaste auf Schließen → Fokus auf zweitem Erklärungsbutton. Diese Folge bestand. Space/Return reagieren nur auf Key-down, damit langes Halten keine wiederholte Aktivierung auslöst. Die systemabhängige Tab-Reihenfolge sowie eine vollständige VoiceOver-Sitzung bleiben separat ungeprüft. Ein versuchter manueller Fenster-Resize über das UI-Werkzeug änderte die Größe nicht; schmale Breiten sind daher durch die nativen Layoutprüfungen, nicht durch diesen manuellen Resize, belegt.

Beim abschließenden normalen Neustart (ohne Demo) wurde das zuvor persönlich verbundene Konto wiederhergestellt. Der echte Verlauf war weiterhin vorhanden; der gespeicherte Vorschlag ließ sich mit der selbst ergänzten Zeile und aufgehobenen Markierungen wieder öffnen. Damit ist der Neustart zusätzlich zur SQLite-Testprüfung auch im laufenden App-Fenster beobachtet.
