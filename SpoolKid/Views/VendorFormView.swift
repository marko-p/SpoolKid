import SwiftUI

struct VendorFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var service: SpoolManService
    let baseUrl: String
    var vendorToEdit: SpoolManVendor?
    
    @State private var name: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Vendor Name", text: $name)
            }
            .navigationTitle(vendorToEdit == nil ? "Add Vendor" : "Edit Vendor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let vendor = vendorToEdit {
                                await service.updateVendor(id: vendor.id, name: name, baseUrl: baseUrl)
                            } else {
                                _ = await service.addVendor(name: name, baseUrl: baseUrl)
                            }
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let vendor = vendorToEdit {
                    name = vendor.name
                }
            }
        }
    }
}
