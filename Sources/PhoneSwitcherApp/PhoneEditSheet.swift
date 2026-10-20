import PhoneCore
import SwiftUI

struct PhoneEditSheet: View {
    let phone: Phone
    let save: (String, String) -> Void
    @State private var label: String
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    init(phone: Phone, save: @escaping (String, String) -> Void) {
        self.phone = phone
        self.save = save
        _label = State(initialValue: phone.label)
        _notes = State(initialValue: phone.notes)
    }

    var body: some View {
        Form {
            TextField("Label", text: $label, prompt: Text("Google account, e.g. xyz@gmail.com"))
            TextField("Notes", text: $notes, prompt: Text("What this user is for"))
        }
        .formStyle(.grouped)
        .navigationTitle("Phone \(phone.number)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(label.trimmingCharacters(in: .whitespaces), notes); dismiss() }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 380)
    }
}
