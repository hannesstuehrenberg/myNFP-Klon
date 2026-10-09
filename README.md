# NFP Zyklus (myNFP-Klon)

Native iPhone-App (SwiftUI, iOS 17+) zur Protokollierung und Auswertung von Zyklen nach der
**symptothermalen Methode (Sensiplan-Regelwerk)**, nachgebaut nach dem Funktionsumfang von myNFP
(Gebrauchsanleitung v22.0, Release Notes, FAQ). Komplett offline, ohne Konto, ohne Tracking.

> Privater Nachbau, **kein zertifiziertes Medizinprodukt** und kein Verhütungsmittel.
> Jede Auswertung muss selbst auf Plausibilität geprüft werden.

## Funktionen

**Zyklusblatt (Reiter „Kurve“)**
- Datumsbereich mit Messuhrzeit, Wochenenden rot markiert
- Temperaturbereich mit 0,1 °C-Kästchen, Kurve, ausgeklammerte Werte grau, Lücken gestrichelt
- Farbige Auswertung: unfruchtbar am Zyklusanfang, fruchtbar, „ab abends unfruchtbar“, unfruchtbar nach dem Eisprung
- Hervorhebung der 6 niedrigen Werte, Hilfslinie, nummerierte höhere Messungen und Absacker (abschaltbar)
- Höhepunkt (HP) mit den Tagen 1–2–3 danach
- Roter Balken: Periodenprognose ab der 1. höheren Messung
- Lila Balken ab Hochlagentag 19 mit voraussichtlichem Entbindungstermin (vET) und SSW, einzeln ausblendbar
- Zeilen für Blutung, Zervixschleim, Muttermund, Brustsymptom, Mittelschmerz, Geschlechtsverkehr, Störungen, Notiz, Medikamente und alle Zusatzleisten
- Zoom (60–200 %, Standard 115 %); Tagesdetails per Tipp auf eine Spalte
- Zyklusinfos „Wie wurde ausgewertet?“: vollständiges Auswertungsprotokoll, Farblegende sowie Export als PDF und als Bild

**Auswertung nach Sensiplan** (siehe [NFPCore](NFPCore/Sources/NFPCore/Evaluation))
- Temperatur: 6 niedrige Werte, Hilfslinie, Grundregel sowie 1. und 2. Ausnahmeregel (nicht kombinierbar), Ausklammern, Lücken
- Zervixschleim: t / ∅ / f / S / S+ wird automatisch aus „gefühlt“ und „gesehen“ bestimmt; optional Binnendifferenzierung (S) und (S+)
- Höhepunkt-Bestimmung inkl. neuem Höhepunkt bei erneutem Anstieg vor Abschluss
- Muttermund (Position, Öffnung, Härte) als Alternative für die Doppelkontrolle und den Zyklusanfang
- Doppelkontrolle: unfruchtbar ab dem Abend des zuletzt abgeschlossenen Kriteriums
- Zyklusanfang: Vorbedingung (1.hM im Vorzyklus), 5-Tage-Regel, Minus-8 (verkürzend bzw. ab 12 Zyklen verlängernd), Minus-20; Schleim f/S/S+ beendet die Phase sofort
- Post-Pill: Fruchtbarkeit ab ZT 1 und ein zusätzlicher höherer Wert, bis eine 1.hM bestätigt ist
- Strenge oder laxe Auswertung (Fortgeschrittenen-Modus)
- Manuelle Auswertung pro Zyklus
- Hinweis, wenn der Höhepunkt mehr als 5 Tage vor bzw. mehr als 3 Tage nach der 1.hM liegt

**Weitere Funktionen**
- Tageseingabe mit allen Symptomen, „Jetzt“-Button für die Messzeit, Vorschlägen für Notizen/Medikamente, „Vom Vortag übernehmen“ und Schnelleingabe (z. B. `3667 s+ gv # Notiz`)
- Zyklen-Liste mit Länge, 1.hM und „früheste“; Zyklus-Einstellungen: Messort/-dauer/Thermometer, Kinderwunsch, Katalog, manuelle Auswertung, Kommentar
- Kataloge: frühere Zyklen, früheste 1.hM, kürzester Zyklus (Minus-20), Post-Pill, Prognose-Verschiebung, fixe Temperaturskala
- Zusatzleisten: LH-Test, Schwangerschaftstest, Stimmung, Libido, Hautbild, Kopfschmerzen, Verdauung, Schmerzen (Intensität), (Peri-)Menopause, Sport, Slider 1–5, Gewicht, Ruhepuls, Ja/Nein-Leisten und eigene Leisten; umbenennbar und sortierbar
- Periodenkalender mit realistischer Prognose (Schwankungsbereich)
- Statistik mit Diagrammen; Zeilen antippbar, um zur Kurve zu springen
- Suche (mit Zyklustag) und eine Tabelle aller Notizen
- Benachrichtigungen: Temperatur messen, „Periode in X Tagen“, „Brust abtasten“, Phasenwechsel, Backup-Erinnerung; Zeitplan einsehbar
- Code-Sperre mit Face ID / Touch ID und Sichtschutz im App-Umschalter
- Dark Mode, Demo-Modus, Wissensteil zu den Regeln

## Datensicherheit & Ausfallschutz

| Ebene | Was passiert |
|---|---|
| Verschlüsselung auf dem Gerät | Alle Dateien liegen mit iOS Data Protection „Complete“ vor, sind also verschlüsselt, solange das iPhone gesperrt ist |
| Integrität | Jede Speicherung schreibt atomar mit SHA-256-Prüfsumme und wird vor dem Schreiben verifiziert |
| Automatische Reparatur | Ist die Datei beschädigt, wird automatisch der letzte gültige Stand oder ein Snapshot geladen |
| Lokale Snapshots | Täglich: 7 Tages- und 12 Monats-Snapshots, dazu Sicherheits-Snapshots vor Import und Löschen |
| iCloud Drive | Automatisches, AES-256-verschlüsseltes Backup in einen frei wählbaren Ordner nach jeder Änderung und täglich (funktioniert ohne bezahlten Developer-Account) |
| iPhone-Backup | Die App-Daten sind im normalen iCloud-/Finder-Backup des iPhones enthalten |
| Export | ZIP mit CSV-Dateien, Einstellungen und Backup-Datei, optional passwortverschlüsselt |
| Code-Sperre | PIN nur als gesalzener Hash in der Keychain; Fehlversuche führen zu Wartezeiten |

**Einmal einrichten:** In der App unter *Mehr → Datensicherung → Backup-Ordner* einen Ordner in **iCloud Drive** wählen
und ein Backup-Passwort festlegen. Das Passwort sicher notieren, denn ohne es lässt sich ein verschlüsseltes Backup nicht öffnen.

## Auf das iPhone bringen (kostenlose Apple-ID)

1. **Xcode** aus dem Mac App Store installieren und einmal starten (Zusatzkomponenten installieren lassen).
2. `MyNFP.xcodeproj` öffnen.
3. Links das Projekt „MyNFP“ auswählen und unter *Signing & Capabilities* bei **Team** deine Apple-ID hinzufügen und auswählen.
   Meldet Xcode, dass die Bundle ID vergeben ist, den **Bundle Identifier** ändern, z. B. `de.<dein-name>.nfpzyklus`.
4. Das iPhone per Kabel verbinden, entsperren und „Diesem Computer vertrauen“ bestätigen.
5. Auf dem iPhone unter *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* aktivieren (Neustart nötig).
6. In Xcode oben das iPhone als Ziel wählen und auf ▶︎ (Run) klicken.
7. Beim ersten Start auf dem iPhone unter *Einstellungen → Allgemein → VPN & Geräteverwaltung* deinem Entwicklerzertifikat vertrauen.

**Wichtig bei kostenloser Apple-ID:** Die App läuft **7 Tage**. Danach in Xcode erneut auf ▶︎ klicken.
**Die Daten bleiben dabei erhalten**, solange du die App nicht löschst. Mit einem bezahlten Developer-Account (99 €/Jahr)
läuft die App 1 Jahr.

## Entwicklung

```
MyNFP.xcodeproj         Xcode-Projekt (Ordner MyNFP/ wird automatisch synchronisiert)
MyNFP/                  SwiftUI-App (Views, Services: Backup, Code-Sperre, Benachrichtigungen)
NFPCore/                Swift-Package: Datenmodell, Sensiplan-Auswertung, Prognosen, Statistik,
                        Schnelleingabe, Speicherung, Verschlüsselung, Export/Import
scripts/check.sh        Prüft den Kern und baut – falls Xcode vorhanden – die App
```

Tests der Kernlogik (laufen auch ohne Xcode):

```sh
cd NFPCore && swift run NFPCoreChecks
```

## Unterschiede zum Original

- Kein Konto und kein Online-Sync über mehrere Geräte. Stattdessen gibt es verschlüsselte Backups in iCloud Drive.
- Partnerfreigabe per Link entfällt. Das Zyklusblatt kann als PDF oder Bild geteilt werden.
- Stillzeit-Regeln werden, wie im Original, nicht ausgewertet.
