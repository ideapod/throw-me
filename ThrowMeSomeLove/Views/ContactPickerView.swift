import Contacts
import ContactsUI
import SwiftUI

/// A small window that shows the system contact picker. Choosing someone makes them the
/// recipient on the next gift tag. The system picker needs no Contacts permission.
struct ContactPickerWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ContactPickerHost { person in
            if let person { model.pickedRecipient = person }
            dismissWindow()
        }
        .onAppear { model.contactsOpen = true }
        .onDisappear { model.contactsOpen = false }
    }
}

/// Presents `CNContactPickerViewController` (it only works presented, not embedded).
private struct ContactPickerHost: UIViewControllerRepresentable {
    let onPick: (Person?) -> Void

    func makeUIViewController(context: Context) -> HostController { HostController(onPick: onPick) }
    func updateUIViewController(_ controller: HostController, context: Context) {}

    final class HostController: UIViewController, CNContactPickerDelegate {
        private let onPick: (Person?) -> Void
        private var presented = false

        init(onPick: @escaping (Person?) -> Void) {
            self.onPick = onPick
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !presented else { return }
            presented = true
            let picker = CNContactPickerViewController()
            picker.delegate = self
            present(picker, animated: true)
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            // Pull out plain values here; CNContact itself isn't safe to hand across.
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Someone"
            let email = contact.isKeyAvailable(CNContactEmailAddressesKey) ? contact.emailAddresses.first?.value as String? : nil
            let phone = contact.isKeyAvailable(CNContactPhoneNumbersKey) ? contact.phoneNumbers.first?.value.stringValue : nil
            let photoData = contact.isKeyAvailable(CNContactThumbnailImageDataKey) ? contact.thumbnailImageData : nil
            MainActor.assumeIsolated {
                let photo = photoData.flatMap { try? MediaStore.importImage(data: $0) }
                onPick(Person(name: name, handle: email ?? phone, photo: photo))
            }
        }

        nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            MainActor.assumeIsolated { onPick(nil) }
        }
    }
}
