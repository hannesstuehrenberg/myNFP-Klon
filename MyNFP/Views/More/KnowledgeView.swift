import SwiftUI

struct Article: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let body: String
}

enum KnowledgeBase {
    static let articles: [Article] = [
        Article(id: "intro", title: "Einführung in NFP", icon: "sparkles", body: """
        Die **symptothermale Methode** (NFP, Natürliche Familienplanung) bestimmt die fruchtbaren und unfruchtbaren Tage im Zyklus anhand von Körperzeichen:

        • der **Basaltemperatur** (Aufwachtemperatur),
        • dem **Zervixschleim** oder alternativ dem **Muttermund**.

        Es gibt zwei unfruchtbare Phasen: am **Zyklusanfang** und **nach dem Eisprung**. Beide werden getrennt ausgewertet. Dazwischen liegt die fruchtbare Phase.

        Die Auswertung in dieser App folgt dem Regelwerk der symptothermalen Methode nach Sensiplan, wie es im Buch „Natürlich & Sicher“ beschrieben ist. Die App ersetzt nicht das Erlernen der Methode: Prüfe jede Auswertung selbst auf Plausibilität. Bei Unsicherheit hilft eine ausgebildete Sensiplan-Beraterin (sensiplan.de).

        **Voraussetzungen:** ein Thermometer mit zwei Nachkommastellen (Auflösung 0,05 °C oder genauer), regelmäßige und sorgfältige Messung und Beobachtung, kein Einfluss hormoneller Präparate.
        """),
        Article(id: "temp", title: "Temperatur messen & auswerten", icon: "thermometer.medium", body: """
        **Messen:** Jeden Morgen direkt nach dem Aufwachen, vor dem Aufstehen, möglichst zur gleichen Uhrzeit, immer am gleichen Ort (oral, vaginal oder rektal) und gleich lange. Thermometer, Messort und Messdauer nur zu Beginn eines neuen Zyklus wechseln.

        **Runden:** Werte werden auf 0,05 °C gerundet (36,23 → 36,25; 37,02 → 37,00). Die App rundet automatisch.

        **Auswertung – Grundregel:**
        1. Suche **6 zusammenhängende niedrige Werte**, auf die ein **höherer Wert** folgt (= 1. höhere Messung, 1.hM). Lücken und ausgeklammerte Werte werden übersprungen.
        2. Die **Hilfslinie** liegt auf dem höchsten der 6 niedrigen Werte.
        3. Es müssen **3 höhere Werte** über der Hilfslinie folgen, der **3. mindestens 0,2 °C** darüber. Die Temperaturauswertung ist am **Abend** des 3. höheren Werts abgeschlossen.

        **1. Ausnahmeregel:** Liegt der 3. Wert weniger als 0,2 °C über der Hilfslinie, wird ein **4. Wert** abgewartet. Er muss über der Hilfslinie liegen (nicht unbedingt 0,2 °C).

        **2. Ausnahmeregel:** Fällt der **2. oder 3. Wert** auf oder unter die Hilfslinie, wird er nicht gewertet. Der nächste Wert zählt als 3. höherer Wert und muss **mindestens 0,2 °C** über der Hilfslinie liegen.

        **Wichtig:** Beide Ausnahmeregeln dürfen **nicht kombiniert** werden. Klappt eine Auswertung nicht, kann später im Zyklus eine neue Folge von 6 niedrigen Werten gesucht werden.

        **Ausklammern:** Nur Werte ausklammern, die **nach oben gestört** sind (z. B. Alkohol, Krankheit, kurze Nacht, abweichende Messzeit) – und nur in der Tieflage. Ausgeklammerte Werte werden grau dargestellt und behandelt, als gäbe es sie nicht. Entscheide dabei konsequent.
        """),
        Article(id: "mucus", title: "Zervixschleim beobachten", icon: "drop", body: """
        Beobachte im Laufe des Tages, was du am Scheideneingang **fühlst/empfindest** und was du **siehst**. Eingetragen wird die **beste Qualität des Tages**; bei mehreren Eigenschaften zählt die fruchtbarste.

        • **t** – trocken: trockenes, raues, juckendes Gefühl, nichts gesehen
        • **∅** – nichts gefühlt, nichts gesehen
        • **f** – feucht gefühlt, nichts gesehen
        • **S** – Schleim gesehen: dicklich, weißlich, trüb, cremig, klumpig, gelblich, klebrig, milchig, nicht ziehbar
        • **S+** – besonders gut: glasig, durchsichtig, dehnbar, spinnbar, wie rohes Eiweiß – oder nass, rutschig, glitschig gefühlt

        Die App bestimmt das Symbol automatisch aus deinen Angaben.

        **Höhepunkt (HP):** der Tag mit der individuell besten Schleimqualität, auf den **3 Tage mit schlechterer Qualität** folgen. Die Schleimauswertung ist am **Abend des 3. Tages nach dem Höhepunkt** abgeschlossen. Tritt die Höhepunkt-Qualität vor Abschluss der Doppelkontrolle erneut auf, wird der Höhepunkt neu bestimmt.

        **Binnendifferenzierung (S) / (S+):** Für erfahrene Anwenderinnen, die fast täglich S+ haben und trotzdem Unterschiede bemerken. Die Klammer bedeutet „etwas schlechter als üblich“. Aktivierbar im Fortgeschrittenen-Modus.

        **Strenge vs. laxe Auswertung:** Standardmäßig wird vom möglichen Höhepunkt bis zum Abschluss der Temperaturauswertung an jedem Tag ein Eintrag benötigt. Bei laxer Auswertung zählt ein Tag ohne Eintrag wie die schlechteste Qualität.
        """),
        Article(id: "double", title: "Doppelkontrolle nach dem Eisprung", icon: "checkmark.seal", body: """
        Die unfruchtbare Phase nach dem Eisprung beginnt erst, wenn **beide** Auswertungen abgeschlossen sind:

        • die **Temperaturauswertung** (Abend des 3. bzw. 4. höheren Werts) und
        • die **Schleimauswertung** (Abend des 3. Tages nach dem Höhepunkt) – oder alternativ die Muttermund-Auswertung.

        Es zählt die Auswertung, die **zuletzt** abgeschlossen ist: Ab dem **Abend dieses Tages** gilt Unfruchtbarkeit. Im Zyklusblatt ist dieser Tag halb gefärbt.

        Einmal korrekt bestimmt, wird die unfruchtbare Phase nicht wieder fruchtbar. S oder S+ in der Hochlage nach abgeschlossener Auswertung ändert nichts.

        **Zeitlicher Zusammenhang:** Liegt der Höhepunkt mehr als 5 Tage vor oder mehr als 3 Tage nach der 1. höheren Messung, weist die App darauf hin – prüfe die Auswertung dann besonders sorgfältig.
        """),
        Article(id: "start", title: "Unfruchtbarkeit am Zyklusanfang", icon: "calendar.badge.clock", body: """
        **Vorbedingung:** Im Vorzyklus muss eine 1. höhere Messung festgestellt worden sein. Sonst gilt Fruchtbarkeit ab dem 1. Zyklustag (z. B. erster NFP-Zyklus, Zyklus ohne Eisprung, Schmierblutung mit Periode verwechselt).

        **5-Tage-Regel:** Für Einsteigerinnen gelten die ersten 5 Zyklustage als unfruchtbar.

        **Minus-8-Regel:** Früheste 1. höhere Messung − 8 = letzter unfruchtbarer Tag.
        • Solange weniger als **12 Zyklen** mit 1. höherer Messung vorliegen, darf sie die 5 Tage nur **verkürzen** (z. B. früheste 1.hM an ZT 12 → nur bis ZT 4).
        • Ab 12 Zyklen gilt sie auch **verlängernd** (z. B. früheste 1.hM an ZT 16 → bis ZT 8).
        • Die früheste 1. höhere Messung gilt sicherheitshalber ein Leben lang – auch aus früheren Aufzeichnungen (in den Katalogeinstellungen eintragen).

        **Minus-20-Regel:** Wer die Längen der letzten 12 Zyklen kennt und nicht hormonell verhütet hat: kürzester Zyklus − 20. Am besten nur mit Beratung anwenden.

        **Schleim beendet sofort:** Sobald am Zyklusanfang Schleim der Kategorie **f, S oder S+** auftritt (bzw. sich der Muttermund verändert), gilt ab sofort Fruchtbarkeit – für alle Regeln.

        Der 1. Zyklustag ist der erste Tag der Blutung **in gewohnter Stärke**; Schmierblutungen davor zählen noch zum alten Zyklus.
        """),
        Article(id: "cervix", title: "Muttermund als Alternative", icon: "circle.dashed", body: """
        Gelingt die Schleimbeobachtung nach mehreren Zyklen nicht gut, kann der **Muttermund** abgetastet werden – möglichst täglich zur gleichen Zeit, in gleicher Position.

        Beurteilt werden **Öffnung** (geschlossen ● / leicht geöffnet ◐ / geöffnet ○), **Härte** (hart H / weich W) und die **Position** (tief / hoch).

        **Höhepunkt:** der letzte Tag, an dem der Muttermund geöffnet und/oder weich ist, gefolgt von **3 Tagen geschlossen und hart**. Die Muttermund-Auswertung ist am Abend des 3. Tages abgeschlossen.

        Aktivierung: Mehr → App-Einstellungen → „Doppelkontrolle mit: Muttermund“ und die Zeile „Muttermund“ in den Tagesdaten-Einstellungen einblenden. Im Fortgeschrittenen-Modus kann auch der Zyklusanfang nach dem Muttermund ausgewertet werden.
        """),
        Article(id: "postpill", title: "Nach hormoneller Verhütung (Post-Pill)", icon: "pills", body: """
        Unmittelbar nach dem Absetzen hormoneller Verhütungsmittel gelten verschärfte Regeln:

        • **Fruchtbarkeit ab dem 1. Zyklustag** (keine 5-Tage-Regel).
        • Bei der Temperaturauswertung wird ein **zusätzlicher höherer Wert** benötigt, der über der Hilfslinie liegen muss (nicht 0,2 °C höher): Grundregel → 4. Wert, 1. bzw. 2. Ausnahmeregel → 5. Wert.
        • Die Regeln gelten, bis in einem Zyklus eine 1. höhere Messung **bestätigt** wurde.

        Bleibt nach dem Absetzen die Blutung aus, beginnt der 1. Zyklus rückwirkend am 1. pillenfreien Tag; ohne Blutung gilt ab dem 8. pillenfreien Tag Fruchtbarkeit.

        In der App: Lege einen Katalog mit der Option „Post-Pill“ an (Mehr → Kataloge oder in den Zyklus-Einstellungen „Neuen Katalog ab diesem Zyklus“).
        """),
        Article(id: "wish", title: "Kinderwunsch & Schwangerschaft", icon: "heart", body: """
        **Kinderwunsch:** In den Zyklus-Einstellungen kannst du pro Zyklus „Kinderwunsch“ aktivieren. Dann werden die fruchtbaren Tage blau hervorgehoben – die Auswertung selbst ändert sich nicht. Die besten Chancen bestehen an den Tagen mit bester Schleimqualität bis zum Höhepunkt. LH- und Schwangerschaftstests kannst du als Zusatzleisten erfassen.

        **Schwangerschaft:** Bleibt die Temperatur lange in der Hochlage, ist eine Schwangerschaft wahrscheinlich. Ab **Hochlagentag 19** zeigt das Zyklusblatt einen **lila Balken**, den **voraussichtlichen Entbindungstermin** (vET = 1. höhere Messung + 266 Tage) und die **Schwangerschaftswoche** (die 1.hM entspricht SSW 2+0). Beides kannst du in den App-Einstellungen ausblenden.

        **Nach der Geburt:** Der Schwangerschaftszyklus endet am Tag vor der Geburt; der Geburtstag ist der 1. Tag eines neuen Zyklus. Lege danach einen **neuen Katalog** an, damit die Minus-8-Regel von vorne beginnt. Für die Stillzeit gelten eigene Regeln, die diese App (wie das Original) nicht auswertet.
        """),
        Article(id: "app", title: "Tipps zur App", icon: "iphone", body: """
        **Zyklusblatt:** Jede Spalte ist ein Tag. Tippe auf eine Spalte, um den Tag auszuwählen (Details erscheinen darunter), und erneut, um ihn zu bearbeiten. Der Stift unten rechts öffnet die Tageseingabe, der ℹ-Button die Zyklusinfos mit dem Auswertungsprotokoll und dem PDF-/Bild-Export.

        **Neuer Zyklus:** In der Tageseingabe die Blutung eintragen und „Ist 1. Zyklustag“ aktivieren.

        **Schnelleingabe** (Fortgeschrittenen-Modus): z. B. „3667 s+ gv # Notiz“ – Temperatur, Schleim, Geschlechtsverkehr und Notiz in einer Zeile.

        **Kataloge** trennen Lebensabschnitte (z. B. nach Schwangerschaft oder Pille). Jeder Katalog wird für sich ausgewertet.

        **Zusatzleisten** (Mehr → Tagesdaten-Einstellungen): Stimmung, LH-Test, Schmerzen, Slider 1–5, eigene Leisten … ein- und ausblenden, sortieren, umbenennen.

        **Datensicherung:** Richte unter Mehr → Datensicherung ein automatisches, verschlüsseltes Backup in iCloud Drive ein. Zusätzlich legt die App täglich lokale Snapshots an und repariert beschädigte Daten automatisch.
        """),
    ]
}

struct KnowledgeListView: View {
    var body: some View {
        List(KnowledgeBase.articles) { a in
            NavigationLink {
                ArticleView(article: a)
            } label: {
                Label(a.title, systemImage: a.icon)
            }
        }
        .navigationTitle("Wissen")
    }
}

struct ArticleView: View {
    let article: Article

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(article.body.components(separatedBy: "\n\n").enumerated()), id: \.offset) { item in
                    Text(markdown(item.element))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
