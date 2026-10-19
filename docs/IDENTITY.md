# Sinnfaden-Identität, Version 0.3

Die Originalzeichnung ist ein offener, asymmetrischer S-Faden mit separatem Endstück in derselben monochromen Farbe. `scripts/make-icon.swift` erzeugt das Master-SVG, monochrome und helle/dunkle Varianten, die Wortmarke sowie PNG-Iconsets und ICNS. Die Buchstaben der Vektor-Wortmarke wurden als eigene Kurven gezeichnet und anschließend in Flächenkonturen umgewandelt; es werden keine Schriftdateien oder fremden Bildbestandteile benötigt.

Alle SVGs sind selbstständig: sinnvolles viewBox, echte Pfade, keine externen Ressourcen oder eingebetteten Bitmaps. `sinnfaden-mono.svg` verwendet `currentColor`. Die App zeichnet dieselbe S-Geometrie nativ. Die offizielle ChatGPT-Blossom-Grafik ist davon getrennt und unverändert; ihre Herkunft steht in BRAND-SOURCES.md.

Prüfraster: `check-{16,24,64,1024}-{light,dark}.png`; bei 16/24px wird die Strichstärke leicht angehoben. Farben kommen aus `DesignSystem.swift`. Die App verwendet bewusst eine weiße Darstellung, unabhängig von der macOS-Systemdarstellung. Schwarze Schrift und Aktionen, neutrale Grautöne für Struktur. Karten nutzen natives Material mit einer stark deckenden weißen Auflage; bei reduzierter Transparenz sind sie deckend. Lernmarkierungen und Erklärungen bleiben blau.

Sinnfaden ist eine Arbeitsmarke, keine Aussage über Marken- oder Domainrechte.
