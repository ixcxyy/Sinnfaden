# Forschungsinformiert, nicht als wirksam nachgewiesen

Prüfdatum: 18.10.2026. Regelverzeichnis und Tutor haben Version 1. Die App hat noch keinen Lerntest mit der Nutzerin absolviert. Ein gültiger Datenvertrag beweist weder Aufgabentreue eines Modells noch didaktischen Nutzen. Lokale Übungsrückmeldungen erkennen einzelne sprachliche Merkmale, zitieren die eigene Antwort und fordern zur Prüfung auf; sie vergeben keinen Kompetenzwert.

| Regel | Evidenztyp und Geltungsbereich | Quelle |
| --- | --- | --- |
| `goal-v1`, `direct-v1` | Anbieterempfehlung: konkrete Ziele, Grenzen und direkte Anweisungen für Reasoning-Modelle; keine privaten Gedankenprotokolle verlangen. Die Eignung muss an der jeweiligen Aufgabe geprüft werden. | [OpenAI, Reasoning best practices](https://developers.openai.com/api/docs/guides/reasoning-best-practices) |
| `examples-v1` | Empirischer Befund: Studie 2 mit 245 Studierenden. Erklärte Beispiele verbesserten die bewertete Promptkonstruktion in einer von zwei Aufgaben gegenüber bloßen Anweisungen; für KI-Ausgaben war dieser Unterschied nicht signifikant. Die Aufgaben waren aufeinanderfolgend, und Promptqualität wurde über Komponenten bewertet. Keine Wirksamkeitsaussage über KLAR. | [Tolzin, Knoth & Janson, ICIS 2024, S. 10–14](https://pubs.wi-kassel.de/wp-content/uploads/2024/10/JML_990.pdf) |
| `retrieval-v1` | Empirischer Befund zum späteren Erinnern von Texten. Motiviert freiwillige eigene Versuche, untersucht aber keine Promptlern-App. | [Roediger & Karpicke, 2006](https://learninglab.psych.purdue.edu/downloads/2006/2006_Roediger_Karpicke_PsychSci.pdf) |
| `check-v1` | Empirischer Befund: Formatvariation beeinflusste Few-shot-Ergebnisse älterer offener Modelle; Formatleistungen waren zwischen Modellen nur schwach korreliert. Keine Effektgröße für heutiges ChatGPT. | [Sclar et al., ICLR 2024](https://proceedings.iclr.cc/paper_files/paper/2024/hash/6c0e99d736da621403018ca7b32b1a4d-Abstract-Conference.html) |
| `unknowns-v1` | Produktentscheidung aus dem Auftrag: entscheidende Lücken erfragen, andere offen markieren, Fakten erhalten. Der verlinkte Anbietertext dient nur als Hintergrund. | Versionierter Tutor in `Sources/KlarCore/Resources/tutor-v1.txt` |

Die Quellen in Bubbles werden ausschließlich aus `RuleRegistry` aufgelöst. Unbekannte Regel-IDs werden vor der Darstellung abgelehnt. Die Nutzerin bleibt bei einer KI-Überarbeitung eingeladen, das tatsächliche Ergebnis auf ihr Ziel zu prüfen.

## Beobachtete lokale Prüfungen

Die Core-Testausführung am 18.10.2026 bestand zunächst 15 Tests: Vertrag, sechs unveränderte Alltagstask-Fixtures (E-Mail, Erklärung, Planung, Zusammenfassung, Kreativität, wiederverwendbare Aufgabe), Unicode/UTF-16, ungültige Referenzen, Rückfrage/Entfernung, SQLite-Neustart, Kontentrennung, Export/Löschen, Rechte, Versionsschutz und differenziertes lokales Übungsfeedback. Nachfolgende Testläufe können zusätzliche Fälle enthalten; der Release-Prüfbericht ist maßgeblich für den finalen Stand.

Die sechs Alltagstasks sind lokale Vertragsbeispiele. Sie wurden nicht von einem verbundenen Modell beantwortet. Live-Aufgabentreue, Namenserhalt, gelungene Rückfragen, tatsächlich nützliche Überarbeitungen und Lernerfolg mit der Nutzerin bleiben ungeprüft, solange kein entsprechender Test protokolliert ist.

## Daten und Grenzen

Der Verlauf nutzt eine SQLite-Datei pro SHA-256-abgeleitetem Konto-Verzeichnis. Verzeichnisrechte sind 0700 und Datenbankrechte 0600. Das ist lokale Zugriffsbeschränkung, keine zusätzliche Datenbankverschlüsselung; FileVault ist eine separate Systemeinstellung. Exporte enthalten bewusst Promptinhalte, keine Zugangsdaten. Die Versionsnummer der Datenbank schützt vor stiller Rückmigration. Löschen ist pro Konto und schließt Entwurf, Änderungen und Übungsversuche ein.

Der Validator prüft Form, Größen, eindeutige IDs, echte Originalzitate, Zielreihenfolge, registrierte Regeln und strukturell nachvollziehbare Änderungen. Eine vollständige semantische Prüfung aller Namen, Absichten, Termine und Einschränkungen ist damit nicht bewiesen. Der Tutor fordert deren Erhalt ausdrücklich. Diese Grenze muss bei echten Modelltests überprüft werden.
