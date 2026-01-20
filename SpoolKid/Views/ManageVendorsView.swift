import SwiftUI

struct ManageVendorsView: View {
    @StateObject private var spoolManService = SpoolManService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @State private var showingAddSheet = false
    @State private var vendorToEdit: SpoolManVendor?
    
    var body: some View {
        List {
            if spoolManService.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let error = spoolManService.errorMessage {
                Text(error).foregroundColor(.red)
            } else {
                ForEach(spoolManService.vendors) { vendor in
                    Button(action: {
                        vendorToEdit = vendor
                    }) {
                        VStack(alignment: .leading) {
                            Text(vendor.name)
                                .font(.headline)
                            Text("ID: \(vendor.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let vendor = spoolManService.vendors[index]
                        Task {
                            await spoolManService.deleteVendor(id: vendor.id, baseUrl: spoolmanUrl)
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage Vendors")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            VendorFormView(service: spoolManService, baseUrl: spoolmanUrl)
        }
        .sheet(item: $vendorToEdit) { vendor in
            VendorFormView(service: spoolManService, baseUrl: spoolmanUrl, vendorToEdit: vendor)
        }
        .refreshable {
            await spoolManService.fetchVendors(baseUrl: spoolmanUrl)
        }
        .onAppear {
            Task {
                await spoolManService.fetchVendors(baseUrl: spoolmanUrl)
            }
        }
    }
}
