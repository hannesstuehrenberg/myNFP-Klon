import UIKit
import UniformTypeIdentifiers

/// Zeigt den iOS-Dateiauswahl-Dialog direkt per UIKit an.
///
/// SwiftUIs `.fileImporter` öffnet sich nicht zuverlässig, wenn an derselben Ansicht weitere
/// Sheets, Alerts oder Dialoge hängen. Die direkte Präsentation umgeht das.
@MainActor
final class DocumentPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPicker()
    private var completion: ((URL?) -> Void)?

    /// Ordner auswählen (Zugriff bleibt über ein Security-Scoped-Bookmark erhalten).
    /// - Parameter onPresented: wird aufgerufen, sobald der Dialog sichtbar ist (das kann einige Sekunden dauern).
    func pickFolder(onPresented: @escaping () -> Void = {}, completion: @escaping (URL?) -> Void) {
        present(UIDocumentPickerViewController(forOpeningContentTypes: [.folder]), onPresented: onPresented, completion: completion)
    }

    /// Datei auswählen. Die App erhält eine Kopie und braucht keinen dauerhaften Zugriff.
    func pickFile(types: [UTType], onPresented: @escaping () -> Void = {}, completion: @escaping (URL?) -> Void) {
        present(UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true), onPresented: onPresented, completion: completion)
    }

    private func present(_ picker: UIDocumentPickerViewController, onPresented: @escaping () -> Void,
                         completion: @escaping (URL?) -> Void) {
        picker.allowsMultipleSelection = false
        picker.delegate = self
        guard let top = Self.topViewController() else {
            onPresented()
            completion(nil)
            return
        }
        self.completion = completion
        top.present(picker, animated: true, completion: onPresented)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion?(urls.first)
        completion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(nil)
        completion = nil
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
