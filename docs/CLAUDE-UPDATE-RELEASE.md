# Claude: Sinnfaden als geprüftes App-Update veröffentlichen

Stand dieser Anleitung: 20. Oktober 2026. Dies ist der Release-Auftrag nach den Design- und Animationsänderungen. Lies die Anleitung vollständig, bevor du veröffentlichst. Arbeite im vorhandenen Projekt und verwende dessen Release-Skripte.

## 1. Was „fertig“ bedeutet

Ein Git-Push speichert den Quellcode auf GitHub. Er veröffentlicht **noch kein herunterladbares App-Update**. Das Projekt hat dafür zwei getrennte Wege:

- **Quellcode:** privates Repository `https://github.com/ixcxyy/Sinnfaden.git`.
- **App-Update:** lokal gebautes und signiertes Archiv plus signierter Sparkle-Feed auf dem vorhandenen Cloudflare-Worker.

Der Auftrag ist erst vollständig erfüllt, wenn der geprüfte Quellcode auf GitHub liegt, genau das getestete Paket veröffentlicht ist, der Updater funktioniert und die neue Version auf Jonas’ Mac gestartet wurde. Berichte getrennt, welche dieser Schritte tatsächlich abgeschlossen sind.

Die vorhandene Gestaltung außerhalb des beauftragten Hover-/Send-/Loading-Verhaltens bleibt erhalten. Prompt-Erstellung, Lernfeedback, gespeicherte Daten und bestehende ChatGPT-Verbindung dürfen durch den Release nicht verloren gehen.

## 2. Projekt und bekannte Ausgangslage

| Zweck | Pfad oder Adresse |
|---|---|
| Projekt | `/Users/jonas/Downloads/Mama_prompten/KLAR` |
| Installierte App | `/Applications/Sinnfaden.app` |
| Versions- und öffentliche Update-Konfiguration | `Config/Info.plist` |
| App bauen | `scripts/build-app.sh` |
| Update vorbereiten und signieren | `scripts/prepare-update.sh` |
| Veröffentlichungsdateien prüfen und zusammenstellen | `scripts/stage-updates.py` |
| Lokales Archiv bisheriger Releases | `Artifacts/updates/` |
| Ausschließlich zu veröffentlichende Dateien | `Artifacts/update-site/` |
| Update-Worker-Konfiguration | `services/update-host/wrangler.jsonc` |
| Fehlerbericht-Worker-Konfiguration | `services/bug-relay/wrangler.jsonc` |
| Öffentlicher Update-Feed | `https://sinnfaden-updates.sinnfaden-bug-relay.workers.dev/appcast.xml` |
| Fehlerberichte | `https://sinnfaden-bug-relay.sinnfaden-bug-relay.workers.dev/v1/reports` |
| Sparkle-Keychain-Konto | `at.klar.promptcoach` |

Beim Schreiben dieser Anleitung:

- Die zuletzt dokumentierte veröffentlichte Version ist **0.4.5 / Build 10**. Nachweis: `docs/RELEASE-0.4.5.md`.
- Der aktuelle Design-Branch heißt `feat/hover-send-loading-motion`; der lokale Design-Commit ist `c21f4b6`. Das ist kein Nachweis einer Veröffentlichung oder eines erfolgreichen Installationstests.
- Der bisherige Feed enthält laut Release-Nachweis Builds **10, 9, 8 und 6**.
- Die früheren 204 bestandenen Tests gelten für Build 10. Übernimm diese Zahl nicht als Testergebnis für deine Änderungen.

Diese Werte sind eine Momentaufnahme. Prüfe Branch, Remote, installierte Version und den **live geladenen Feed** erneut. Vergib keine bereits verwendete Buildnummer.

Lies außerdem `docs/MAINTENANCE.md`, `docs/FREE-HOSTING.md` und den neuesten `docs/RELEASE-*.md`-Nachweis. Bei Abweichungen sind tatsächliche Konfiguration, Skripte und überprüfte Ergebnisse maßgeblich.

## 3. Verbindliche Grenzen

- Nutze die bestehenden kostenlosen Dienste. Keine kostenpflichtige Hosting-Stufe, kein neuer kostenpflichtiger Dienst, keine bezahlten API-Aufrufe und kein Kauf einer Apple-Mitgliedschaft.
- Nutze den vorhandenen Sparkle-Schlüssel. Keinen Ersatzschlüssel erzeugen und keinen privaten Schlüssel exportieren. Der öffentliche Schlüssel der App muss zum vorhandenen Keychain-Konto passen.
- Keine Tokens, Passwörter, privaten Schlüssel, persönlichen Prompts oder Kontodaten in Git, Logs, Screenshots oder Chat schreiben.
- Das Repository bleibt privat. Die Update-Dateien sind öffentlich erreichbar und enthalten ausschließlich dafür geeignete App-Pakete, öffentliche Konfiguration und Release Notes.
- Die bestehende kostenlose Veröffentlichung verwendet Ad-hoc-App-Signierung plus Sparkle-Ed25519-Signaturen. Sie ist **nicht Apple-notarisiert**. Nicht als Developer-ID-signierte Veröffentlichung bezeichnen.
- Gatekeeper, Keychain-Schutz und Sparkle-Signaturprüfung bleiben aktiv. Eine nötige macOS-Freigabe muss im Systemdialog erfolgen. Bei einem echten Zugriffsblocker den konkreten Zustand melden und alle unabhängig möglichen Schritte abschließen.
- Bereits veröffentlichte Archive bleiben bytegenau unverändert. Kein Überschreiben eines alten Builds mit einem neuen Inhalt, kein Force-Push und kein Zurücksetzen fremder Änderungen.
- Vorhandene Benutzerdateien und Kontospeicher weder löschen noch durch Testdaten ersetzen. Testkopien mit derselben Bundle-ID sind nicht automatisch von den Benutzerdaten isoliert.

## 4. Zustand prüfen und Version festlegen

Alle folgenden Befehle werden vom Projektverzeichnis aus ausgeführt, sofern nicht ausdrücklich anders angegeben:

```sh
cd /Users/jonas/Downloads/Mama_prompten/KLAR
git status --short
git branch --show-current
git remote -v
git fetch origin
git log -5 --oneline
```

Prüfe lokale Änderungen und Änderungen anderer Beteiligter vor Branchwechseln. In einem nicht sauberen Arbeitsverzeichnis nicht blind wechseln, zurücksetzen oder automatisch alles committen.

Lege unter `Artifacts/` einen neuen, eindeutig benannten Nachweisordner für diesen Release an. Sichere dort den bisherigen Live-Feed und dessen Signaturprüfung, die Liste seiner Builds sowie die bisherigen Dateinamen und Hashes. Prüfe die installierte Version direkt in `/Applications/Sinnfaden.app/Contents/Info.plist`.

Setze in `Config/Info.plist`:

- `CFBundleShortVersionString`: die neue sichtbare Versionsnummer.
- `CFBundleVersion`: eine strikt höhere, bisher unbenutzte Buildnummer.

**Beispiel:** `0.4.6 / 11` ist nur dann zulässig, wenn die Prüfung keine neuere oder bereits verwendete Nummer ergibt. Bei größeren Funktionsänderungen kann eine passend höhere sichtbare Version gewählt werden; die Buildnummer muss trotzdem steigen.

Ergänze exakt `VERSION+BUILD` in `ALLOWED_RELEASES` in `services/bug-relay/wrangler.jsonc`. Behalte alle noch unterstützten bisherigen Einträge. Ohne diesen Eintrag lehnt der Relay Fehlerberichte des neuen Builds ab.

Schreibe deutsche, nutzerverständliche Release Notes nach `docs/release-notes/VERSION.md`. Beschreibe tatsächliche Änderungen und bekannte Einschränkungen. Ein Design-Update darf keine ungetesteten Verbesserungen an Prompt-Qualität oder Lernfeedback behaupten.

## 5. Funktion, Design und Build prüfen

Nach Änderungen am Code den vorhandenen Projektgraphen gemäß `AGENTS.md` aktualisieren. Prüfe den Diff auf unbeabsichtigte Backend-, Konto-, Speicher- und Update-Änderungen.

```sh
swift test
npm --prefix services/bug-relay ci
npm --prefix services/bug-relay test
npm --prefix services/bug-relay run check
python3 -m unittest discover -s Tests/ReleaseTests -v
git diff --check
```

Jeder notwendige Prüfschritt muss erfolgreich sein. Fehler beheben und betroffene Prüfungen wiederholen. Bei Protokollierung mit Pipes sicherstellen, dass ein fehlgeschlagener Test nicht durch den Exitcode von `tee` verdeckt wird.

Zusätzlich die echte App prüfen:

- Hover über kurze, lange und umgebrochene Annotationen; schnelle Wechsel, Randpositionen, Scrollen, Pinning, Textauswahl und Tastatur.
- Senden kurzer, langer und mehrzeiliger Prompts; schneller Erfolg, Abbruch und Fehlerzustand.
- Reduce Motion, Lesbarkeit, beide Erscheinungsbilder und Verhalten beim Fenstergrößenwechsel.
- Mehrere synthetische Prompt-Beispiele über die bestehende Verbindung: ein vager Auftrag, ein klar spezifizierter Auftrag und eine Rückfrage mit anschließender Antwort. Fakten und Einschränkungen müssen erhalten bleiben; Lehrhinweise müssen sich auf die tatsächlichen Änderungen beziehen.
- Eine Übung mit richtiger und falscher Antwort, Verlauf und Wiederaufnahme eines Entwurfs. Keine persönlichen gespeicherten Inhalte in Nachweise übernehmen.

Baue die App mit den neuen, eingecheckten Versionswerten. Prüfe vorher, dass keine alten `KLAR_*`-Overrides die Version, Feed-URL, Architektur, Signieridentität oder Ausgabeordner unerwartet überschreiben. Gib dabei keine geheimen Umgebungsvariablen aus.

```sh
./scripts/build-app.sh
codesign --verify --deep --strict Artifacts/Sinnfaden.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Artifacts/Sinnfaden.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Artifacts/Sinnfaden.app/Contents/Info.plist
file Artifacts/Sinnfaden.app/Contents/MacOS/KLAR
```

Das Build-Skript baut standardmäßig für die Architektur dieses Macs. Keine universelle Intel-/Apple-Silicon-Kompatibilität behaupten, wenn nur eine Architektur gebaut und getestet wurde.

## 6. Exakten Quellstand auf GitHub sichern

Prüfe die vorgesehenen Dateien einzeln und stage nur diese. Quelländerungen, Versionsanhebung, Relay-Allowlist und Release Notes gehören zum nachvollziehbaren Release-Stand. `Artifacts/`, `.build/`, lokale Zugangsdaten und Benutzerinhalte gehören nicht in Git.

```sh
git diff --stat
git diff --cached --stat
git diff --cached --check
```

Committe die geprüften Änderungen mit einer aussagekräftigen Nachricht. Push den aktuellen Arbeitsbranch ohne Force:

```sh
git push -u origin HEAD
```

Das veröffentlicht den Branch, aber weder automatisch `main` noch das App-Update. Integriere den geprüften Release-Stand anschließend über den vorhandenen Repository-Workflow in `main`. Bei Branch-Schutz einen PR verwenden und vorgeschriebene Prüfungen erfüllen; Schutzregeln nicht umgehen. Bei direkter Integration nur auf sauberem Arbeitsverzeichnis arbeiten, `main` zuerst ohne History-Rewrite aktualisieren und den geprüften Branch regulär integrieren.

Ändert die Integration App-Code oder Build-Konfiguration, erneut testen und bauen. Notiere die vollständige SHA des endgültigen Release-Quellstands mit `git rev-parse HEAD`; das Paket muss diesem Stand entsprechen. Prüfe nach dem Push, dass der Remote den vorgesehenen Commit enthält. Erzeuge keinen Release-Tag auf einem ungetesteten Zwischenstand.

## 7. Historie erhalten und Update signieren

**Wichtigster bereits aufgetretener Veröffentlichungsfehler:** Ein frisch erzeugter Feed enthielt nur den neuesten Build. Das Staging kopierte deshalb keine alten Archive, obwohl diese lokal vorhanden waren. Ihre bisherigen öffentlichen URLs lieferten anschließend 404.

Daher vor der Vorbereitung:

1. Sicherstellen, dass `Artifacts/updates/` den überprüften bisherigen signierten `appcast.xml` **und** dessen referenzierte Archive, Release Notes und gegebenenfalls Deltas enthält.
2. Lokale Archivdateien gegen den gesicherten Live-Stand prüfen. Fehlende Dateien vom bekannten Update-Host laden und verifizieren. Keine unbekannten/unveröffentlichten Kandidaten versehentlich als historische Releases übernehmen.
3. Vorhandene Dateien und den bisherigen Feed separat sichern. Ein frischer Ausgabeordner muss mit dem bisherigen Feed **und seinen Dateien** befüllt werden.
4. Die Liste der zu erhaltenden Builds ausdrücklich festhalten. Das aktuelle Skript verwendet `--maximum-versions 5`. Sobald mehr Einträge erhalten werden sollen, diese Grenze vor der Generierung bewusst anpassen; keine unbemerkte Entfernung alter Downloads akzeptieren.

Lege den Release-Typ fest:

- `regular`: normale Korrekturen und kleinere Verbesserungen.
- `major`: größerer Funktions-/Design-Patch mit Sparkles Major-Markierung.
- `critical`: ausschließlich tatsächlich dringende Fehlerbehebungen, nicht zur Bewerbung eines Design-Updates.

Lies die installierte Werkzeughilfe bei Bedarf. Verwende für die bestehende kostenlose Distribution ausdrücklich `--development`.

```sh
# VERSION.md durch den tatsächlich angelegten Dateinamen ersetzen.
KLAR_RELEASE_NOTES="$PWD/docs/release-notes/VERSION.md" ./scripts/prepare-update.sh regular --development
python3 scripts/stage-updates.py
```

Bei einem bewusst als groß eingeordneten Patch `regular` durch `major` ersetzen. Die Skripte prüfen unter anderem App-Signatur, Schlüsselübereinstimmung, Feed-/Dateisignaturen, referenzierte Dateigrößen und das konfigurierte 25-MiB-Limit pro Hosting-Datei. Sie laden nichts hoch.

Vor dem Weitergehen:

- Neuer Build und alle vorgesehenen alten Builds stehen im erzeugten Feed.
- Neue Version, Buildnummer, Archivname, Architektur und Release Notes stimmen überein.
- Alle Produktionslinks verwenden den bestehenden HTTPS-Host. Kein `localhost`, kein Testport, kein privater GitHub-Download mit Token.
- SHA-256 und Bytezahl des neuen ZIPs notieren.
- Ab jetzt genau dieses Archiv verwenden. Wird die App nachträglich neu gebaut oder geändert, gilt der vorherige Installationstest nicht mehr. Ein bereits öffentlich angebotenes Paket darf nur durch einen neuen Build abgelöst werden.

## 8. Vor Veröffentlichung: echte Update-Installation testen

Ein erfolgreicher Build, eine erkannte Update-Version oder eine Logmeldung „INSTALLING“ beweist noch keine erfolgreiche Installation.

1. Eine **separate Kopie eines bisherigen veröffentlichten Builds** in einem neuen Testordner unter `Artifacts/` vorbereiten. Niemals `/Applications/Sinnfaden.app` als erstes Testziel verwenden.
2. Das exakt zur Veröffentlichung bestimmte ZIP unverändert in einen getrennten Testfeed-Ordner kopieren.
3. Nur für den Test einen eigenen signierten Feed mit Loopback-URLs erzeugen. Auch `--release-notes-url-prefix` muss auf den Testserver zeigen; sonst werden noch unveröffentlichte Produktions-Release-Notes angefordert. Produktionsfeed und Produktionskonfiguration bleiben unverändert.
4. Den Testserver ausschließlich an `127.0.0.1` binden und den Update-Test auf diese App-Kopie begrenzen. Ein vorhandener Referenz-Helfer ist `Artifacts/prompt-quality/UpdateCheck.m`. Er enthält fest codierte Pfade, Port und Builds 9/10 und muss für einen neuen Test in einer neuen Kopie angepasst und neu gebaut werden. Ihn nicht ungeprüft starten. Er ist ein lokales Nachweisartefakt und möglicherweise auf einem anderen Mac nicht vorhanden.
5. Über Sparkle Download, Signaturprüfung, tatsächlichen Austausch und Relaunch durchführen. Die Installation über `ditto` allein ersetzt diesen Test nicht.
6. Danach im Zielbundle neue Version und Buildnummer lesen, `codesign --verify --deep --strict` ausführen und das installierte Executable mit dem aus dem Kandidatenarchiv vergleichen. Das gestartete App-Bundle muss nachweislich die Testkopie sein.
7. Für einen isolierten Starttest kann die App im vorhandenen `--demo`-Modus geöffnet werden. Der produktive Updater ist in diesem Modus deaktiviert; ein Demo-Start ist daher kein Updater- oder Live-Konto-Nachweis.
8. Nach erfolgreichem Abschluss nur die eigenen Testprozesse normal beenden und den eigenen Loopback-Server stoppen. Nachweis und Archive erhalten.

Frühere Installationen warteten zeitweise beim Dateiaustausch (`renamex_np`). Bei Stillstand zuerst konkretes Ziel, Installerzustand und mögliche Systemdialoge prüfen. Keinen noch laufenden Austausch durch einen zweiten Installationsversuch überlagern, keine Schutzfunktion abschalten und den Test nicht allein nach einer Wartezeit als erfolgreich werten. Bei einem nicht auflösbaren Fehler bleibt die öffentliche Veröffentlichung aus; Quellcode und Nachweise können dennoch gesichert werden.

## 9. Auf den vorhandenen Cloudflare-Diensten veröffentlichen

Voraussetzung: Tests, Signaturen, Feed-Historie und Installationstest sind erfolgreich; der zugehörige Quellstand ist auf GitHub gesichert. Die bestehenden Wrangler-Zugangsdaten nutzen. Bei abgelaufener Anmeldung den vorhandenen Verbindungsweg aus `docs/FREE-HOSTING.md` verwenden, keine Tokens in Befehle oder Chat einfügen.

Zuerst beide Konfigurationen ohne Veröffentlichung prüfen:

```sh
WRANGLER_SEND_METRICS=false services/bug-relay/node_modules/.bin/wrangler deploy --dry-run --config services/bug-relay/wrangler.jsonc
WRANGLER_SEND_METRICS=false services/bug-relay/node_modules/.bin/wrangler deploy --dry-run --config services/update-host/wrangler.jsonc
```

Dann die geprüfte Relay-Allowlist und anschließend die geprüften Update-Dateien veröffentlichen:

```sh
WRANGLER_SEND_METRICS=false services/bug-relay/node_modules/.bin/wrangler deploy --config services/bug-relay/wrangler.jsonc
WRANGLER_SEND_METRICS=false services/bug-relay/node_modules/.bin/wrangler deploy --config services/update-host/wrangler.jsonc
```

Der statische Worker veröffentlicht `Artifacts/update-site/`. Nicht das gesamte Projekt oder den gesamten `Artifacts/`-Ordner hochladen. Der vorhandene Weg lädt Assets vor dem Wechsel der aktiven Bereitstellung hoch. Bei einem anderen Hosting-Verfahren müssten Pakete und Notes vor dem Feed veröffentlicht werden; für diesen Auftrag ist kein Hosting-Wechsel nötig.

Beide Deployment-IDs und Zeitpunkte notieren. Eine erfolgreiche Relay-Veröffentlichung bedeutet nicht, dass das App-Update veröffentlicht wurde.

## 10. Öffentlichen Download und installierte App verifizieren

Nach der Bereitstellung den Feed erneut über verifiziertes HTTPS in einen frischen Nachweisordner laden. Kein `curl -k` und kein Vertrauen allein auf lokale Dateien.

- Den tatsächlich heruntergeladenen Feed mit `.build/artifacts/sparkle/Sparkle/bin/sign_update --account at.klar.promptcoach --verify PFAD_ZUM_FEED` prüfen.
- Aus diesem Feed alle Archiv-, Delta- und Release-Notes-Verweise ermitteln. Nur den erwarteten HTTPS-Host und die erwarteten Dateinamen akzeptieren.
- Jede referenzierte Datei herunterladen; HTTP-Erfolg, Bytezahl und SHA-256 mit der lokalen Veröffentlichung vergleichen. Für Dateien die jeweilige `sparkle:edSignature` aus dem verifizierten Feed zusätzlich an `sign_update --verify DATEI SIGNATUR` übergeben, zusammen mit `--account at.klar.promptcoach`.
- Die vorgesehenen alten Builds müssen weiterhin im Feed und ihre bisherigen URLs unverändert erreichbar sein. Auch ihre Hashes prüfen. Bei einem Fehler sofort die vollständige vorherige Deployment-Version wiederherstellen, Ursache beheben und neu verifizieren.

Erst nach dem separaten Installationstest die reale Installation aktualisieren:

1. Die vorhandene `/Applications/Sinnfaden.app` als Bundle sichern. Benutzerdaten separat erhalten; keine alten Datenbanken über neuere Daten kopieren.
2. Die laufende App normal beenden. Bevorzugt über deren **„Nach Updates suchen …“** das jetzt live verfügbare Update installieren. Eine nötige manuelle Installation muss dasselbe bereits geprüfte ZIP verwenden, die vorhandene App vollständig ersetzen statt Bundle-Inhalte zu vermischen und den Rückweg zur Bundle-Sicherung erhalten.
3. Neue Versionswerte, Signatur und Executable prüfen. Bei manueller Installation ausdrücklich dokumentieren, dass dies zusätzlich zum separaten Sparkle-Test geschah.
4. `/Applications/Sinnfaden.app` explizit öffnen. Prüfen, dass dieser Pfad läuft und keine alte Testkopie.
5. Vorhandene Verbindung, Entwurf/Verlauf, Prompt-Erstellung und neue Interaktionen kontrollieren. Keine erneute Anmeldung oder Löschung des Kontos als pauschale Fehlerbehebung.
6. **„Nach Updates suchen …“** muss die installierte neue Version korrekt als aktuell erkennen. App für Jonas geöffnet lassen.

Automatische Suche und Benachrichtigung bleiben möglich, sofern sie in der App aktiviert sind. Download und Installation brauchen weiterhin die Bestätigung. Keine stille automatische Installation aktivieren. Eine Major-Markierung ersetzt weder diese Einstellung noch einen funktionierenden Feed.

## 11. Release-Nachweis, Git-Abschluss und Übergabe

Erstelle `docs/RELEASE-VERSION.md` und aktualisiere die aktuellen Versionsverweise in `docs/MAINTENANCE.md` und `docs/FREE-HOSTING.md`, ohne alte Nachweise als neue Tests auszugeben.

Dokumentiere:

- Sichtbare Version, Buildnummer, Release-Typ und vollständige Quell-Commit-SHA.
- Tatsächlich ausgeführte Tests, Ergebnisse und verbleibende Grenzen.
- Geprüfte native Interaktionen und Prompt-Szenarien, ohne persönliche Inhalte.
- Archivname, SHA-256, Bytezahl und öffentliche Download-Adresse.
- Ausgangs- und Zielbuild des erfolgreichen Sparkle-Installationstests.
- Verifizierte Version und Pfad der real installierten App.
- Update- und Relay-Deployment-ID, Feed-Versionen und öffentliche Dateiprüfung.
- Den weiterhin geltenden Entwicklungs-Signierungsstatus ohne Apple-Notarisierung.

Committe und pushe die abschließende Dokumentation. Ein Release-Tag wie `vVERSION` gehört auf den bereits geprüften Release-Quellstand, nicht versehentlich auf spätere App-Änderungen. Falls ein GitHub Release angelegt wird, Version, Commit und gegebenenfalls hochgeladenes ZIP müssen identisch sein. Ein GitHub Release allein ersetzt die Cloudflare-Veröffentlichung nicht.

Abschließend getrennt angeben: **Quellcode gepusht / Update veröffentlicht / Installation getestet / auf Jonas’ Mac installiert und geöffnet**. Nicht erledigte Punkte ausdrücklich benennen.

Wenn ein Nutzungs- oder Zugriffsproblem die Arbeit unterbricht, hinterlasse den aktuellen Branch/Commit, Paket-Hash, bereits bestandene Prüfungen, aktive eigene Testprozesse, konkrete Blocker und den nächsten sicheren Schritt. Keine erfolgreich getestete Veröffentlichung behaupten, solange nur ein Teil des Ablaufs abgeschlossen ist.
