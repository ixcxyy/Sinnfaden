# Übergabe an ChatGPT

Geprüft am 18.10.2026 für Sinnfaden. Der Coach-Zugang und die Zielanwendung sind getrennte Sitzungen. Es werden keine Konten synchronisiert, keine ChatGPT-Gespräche importiert und keine Nachrichten automatisch gesendet.

## Offizielle Referenz und tatsächlicher Mac

Die [offizielle Befehlsreferenz](https://learn.chatgpt.com/docs/reference/commands#deep-links) beschreibt `codex://threads/new?prompt=…` als ChatGPT-kompatiblen Link. `prompt` setzt den Text im Eingabefeld. Die Dokumentation erklärt ausdrücklich, dass der vorbereitete Prompt nicht automatisch gesendet wird. Zusätzliche Angaben zu Workspace, Repository, Konto, Modell oder Modus werden von Sinnfaden nicht angehängt.

Auf dem Testgerät wurde `/Applications/ChatGPT.app` gefunden:

- Angezeigter Name: ChatGPT.
- Bundle-ID: `com.openai.codex`.
- Version: `26.1013.40934`.
- Registrierte Schemes: `codex`, `http`, `https`.
- Developer-ID: OpenAI OpCo, LLC, Team `2DC432GLL2`; stapled Notarization Ticket.

Ein neutraler synthetischer Link mit Zeilenumbruch, Umlaut, Emoji und `& # + %` wurde in Safari geöffnet. Safari fragte ausdrücklich, ob ChatGPT geöffnet werden darf; diese einzelne Navigation wurde erlaubt. Anschließend verweigerte das Computer-Use-Werkzeug das Lesen der Anwendung `com.openai.codex` aus Sicherheitsgründen. Diese Einschränkung wurde nicht umgangen. Daher wurden weder der genaue Composer-Inhalt noch die Eignung der geöffneten Chat-Oberfläche als Alltagseingabe beobachtet. Es wurde kein Senden ausgelöst.

Die installierte App und ein URL-Handler allein gelten deshalb **nicht** als abgeschlossener Kompatibilitätstest. Die Liste bestätigter Desktop-Versionen bleibt leer. Die ausgelieferte Aktion verwendet den ehrlichen Browser-Fallback.

## Tatsächliches Verhalten

`ChatGPTHandoff` erhält den derzeit sichtbaren Prompt als einen unveränderten String. Der Aufruf erfolgt ausschließlich durch eine ausdrückliche Schaltflächenaktion.

Die aktuelle Beschriftung ist **„Kopieren & ChatGPT öffnen“**. Die Aktion kopiert den vollständigen Prompt und öffnet `https://chatgpt.com/` in einem Browser. Der Browser wird über den generischen HTTPS-Handler ermittelt; die ChatGPT-App wird als Webziel-Handler ausgeschlossen, um eine erneute unbestätigte Desktop-Weiterleitung zu vermeiden. Falls nötig wird ein bekannter installierter Browser verwendet. Es werden keine Promptdaten in die Browser-URL geschrieben.

Nach bestätigtem erfolgreichem Öffnen lautet der Hinweis: **„Prompt kopiert. In ChatGPT mit ⌘V einfügen.“** Schlägt nur das Öffnen fehl, bleibt die erfolgreiche Kopie bestehen und der Hinweis nennt das fehlgeschlagene Öffnen. Schlägt das Kopieren fehl, wird nicht behauptet, der Prompt sei kopiert, und das Öffnen unterbleibt.

Der implementierte Desktop-Pfad wird erst freigegeben, wenn eine konkrete Version zusätzlich zum gültigen OpenAI-Signatur-/Namen-/Scheme-Check einen beobachteten Composer- und Zieloberflächentest bestanden hat. Er adressiert dann ausdrücklich die aufgelöste ChatGPT-App statt irgendeinen registrierten Scheme-Handler. Schlägt das Öffnen fehl, folgt derselbe vollständige Clipboard-Fallback.

## Encoding und lange Texte

`ChatGPTHandoffPlan` bildet den dokumentierten Deep Link mit `URLComponents` und genau einem `prompt`-QueryItem. Literal `+` wird zusätzlich als `%2B` kodiert, damit auch formartige Query-Decoder das Zeichen bewahren. Ein interner Roundtrip prüft den unveränderten String. Kein Trimmen, keine Normalisierung, keine Markierungszeichen.

Ab 8.000 URL-Bytes greift der Clipboard-Fallback. Das ist eine konservative Produktgrenze, keine Behauptung über ein offizielles ChatGPT-Limit. Die Clipboard-Kopie bleibt vollständig. Prompttragende URLs oder Promptinhalte werden vom Übergabedienst nicht protokolliert.

## Prüfumfang

Die isolierten Tests prüfen exaktes Encoding einschließlich Unicode und Zeilenumbrüchen, den einzigen erlaubten Queryparameter, fehlende Desktop-Bestätigung und den vollständigen Fallback bei langen Texten. Die native Clipboard-/Browser-Aktion wurde in Sinnfaden ausgeführt: ein mehrzeiliger Rezepttext mit Umlauten, Emoji und `& # + %` erschien nach ⌘V exakt im lokalen Prüffeld. Der Öffnungsaufruf war erfolgreich; keine Nachricht wurde gesendet. Reine Encodingtests allein belegen keinen erfolgreichen App-Wechsel.

## Anbindung des Aha-Labors

`ConnectionManager.generate` akzeptiert zusätzlich einen vorab erfassten tatsächlichen Modell-Slug als `model:` und prüft diesen weiterhin gegen den Kontokatalog. So kann der Aufrufer denselben Slug für beide Vergleichsseiten festhalten. `onPartialText:` liefert ausschließlich tatsächlich empfangenen, bisher aufgelaufenen Antworttext. Er darf als unvollständig gekennzeichnet sichtbar bleiben, gilt aber erst nach `response.completed` als fertiges Ergebnis. Vorhandene Aufrufe ohne diese optionalen Parameter bleiben kompatibel.
