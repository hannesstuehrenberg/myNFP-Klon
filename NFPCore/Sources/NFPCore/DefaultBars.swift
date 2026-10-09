import Foundation

/// Vordefinierte Zusatzleisten. Die IDs sind stabil, damit Backups kompatibel bleiben.
public enum DefaultBars {
    public static let moodOptions = [
        "fröhlich", "zufrieden", "ausgeglichen", "ruhig / entspannt", "energiegeladen / aktiv", "motiviert",
        "entschlossen", "erfüllt", "aufgeregt / begeistert", "kontaktfreudig", "so lala", "müde",
        "lustlos / unmotiviert", "rückzugsbedürftig", "grübelnd / nachdenklich", "ängstlich", "gestresst",
        "gereizt", "traurig", "unzufrieden", "depressiv",
    ]

    public static let all: [BarDefinition] = [
        BarDefinition(id: "lh", name: "LH-Test", kind: .singleChoice,
                      options: ["negativ", "schwach positiv", "positiv"], icon: "testtube.2"),
        BarDefinition(id: "pregnancyTest", name: "Schwangerschaftstest", kind: .singleChoice,
                      options: ["negativ", "unklar", "positiv"], icon: "testtube.2"),
        BarDefinition(id: "mood", name: "Stimmung", kind: .multiChoice, options: moodOptions, icon: "face.smiling"),
        BarDefinition(id: "libido", name: "Libido", kind: .singleChoice,
                      options: ["niedrig", "normal", "hoch"], icon: "heart"),
        BarDefinition(id: "skin", name: "Hautbild", kind: .singleChoice,
                      options: ["rein", "normal", "unrein", "Pickel"], isVisible: false, icon: "sparkles"),
        BarDefinition(id: "headache", name: "Kopfschmerzen", kind: .singleChoice,
                      options: ["leicht", "mittel", "stark", "Migräne", "Schwindel"], isVisible: false,
                      icon: "brain.head.profile"),
        BarDefinition(id: "digestion", name: "Verdauung", kind: .multiChoice,
                      options: ["Blähungen", "Bauchschmerzen", "Durchfall", "Verstopfung", "Übelkeit", "Sodbrennen"],
                      isVisible: false, icon: "stomach"),
        BarDefinition(id: "cramps", name: "Unterleibsschmerzen", kind: .intensity,
                      options: BarKind.intensityLevels, isVisible: false, icon: "bolt.heart"),
        BarDefinition(id: "backpain", name: "Rückenschmerzen", kind: .intensity,
                      options: BarKind.intensityLevels, isVisible: false, icon: "figure.walk"),
        BarDefinition(id: "discharge", name: "Ausfluss", kind: .singleChoice,
                      options: ["wenig", "normal", "viel", "auffällig"], isVisible: false, icon: "drop"),
        BarDefinition(id: "menopause", name: "(Peri-)Menopause", kind: .multiChoice,
                      options: ["Hitzewallungen", "Nachtschweiß", "Schlafstörungen", "Stimmungsschwankungen",
                                "Scheidentrockenheit", "Gelenkschmerzen", "Herzklopfen", "Konzentrationsprobleme"],
                      isVisible: false, icon: "thermometer.sun"),
        BarDefinition(id: "sport", name: "Sport", kind: .multiChoice,
                      options: ["Laufen", "Radfahren", "Schwimmen", "Yoga", "Krafttraining", "Wandern", "Sonstiges"],
                      isVisible: false, icon: "figure.run"),
        BarDefinition(id: "energy", name: "Energie", kind: .sliderRedGreen, isVisible: false, icon: "bolt"),
        BarDefinition(id: "sleep", name: "Schlafqualität", kind: .sliderRedGreen, isVisible: false, icon: "bed.double"),
        BarDefinition(id: "strain", name: "Belastung", kind: .sliderGreenRed, isVisible: false, icon: "scalemass"),
        BarDefinition(id: "weight", name: "Gewicht", kind: .textValue, isVisible: false, icon: "scalemass"),
        BarDefinition(id: "pulse", name: "Ruhepuls", kind: .textValue, isVisible: false, icon: "waveform.path.ecg"),
        BarDefinition(id: "supplement", name: "Nahrungsergänzung", kind: .takenIcon, isVisible: false, icon: "pills"),
        BarDefinition(id: "goal", name: "Ziel erreicht", kind: .goalReached, isVisible: false, icon: "flag.checkered"),
        BarDefinition(id: "done", name: "Erledigt", kind: .done, isVisible: false, icon: "checkmark.seal"),
        BarDefinition(id: "value1", name: "Wert 1", kind: .textValue, isVisible: false, icon: "textformat"),
        BarDefinition(id: "value2", name: "Wert 2", kind: .textIcon, isVisible: false, icon: "text.bubble"),
    ]
}
