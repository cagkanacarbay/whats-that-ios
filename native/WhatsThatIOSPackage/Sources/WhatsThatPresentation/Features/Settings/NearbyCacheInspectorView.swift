import SwiftUI
import WhatsThatDomain

public struct NearbyCacheInspectorView: View {
    let loadSnapshots: () async -> [NearbyPlacesSnapshot]
    let loadCurrent: () async -> DiscoveryLocation?
    let clearSnapshots: () async -> Void

    @State private var snapshots: [NearbyPlacesSnapshot] = []
    @State private var current: DiscoveryLocation?
    @State private var isLoading = false
    @State private var showClearConfirm = false

    public init(
        loadSnapshots: @escaping () async -> [NearbyPlacesSnapshot],
        loadCurrent: @escaping () async -> DiscoveryLocation?,
        clearSnapshots: @escaping () async -> Void
    ) {
        self.loadSnapshots = loadSnapshots
        self.loadCurrent = loadCurrent
        self.clearSnapshots = clearSnapshots
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Summary")) {
                    HStack {
                        Text("Cache entries")
                        Spacer()
                        Text("\(snapshots.count)")
                            .foregroundStyle(.secondary)
                    }
                    if let current {
                        Text(String(format: "Current: %.6f, %.6f", current.latitude, current.longitude))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Current: unavailable")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Snapshots")) {
                    if snapshots.isEmpty {
                        Text("No cached nearby places")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshots, id: \.id) { snap in
                            NavigationLink {
                                NearbyCacheSnapshotDetailView(snapshot: snap, current: current)
                            } label: {
                                SnapshotRow(snapshot: snap, current: current)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nearby Cache")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Refresh") { Task { await refresh() } }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("Clear")
                    }
                }
            }
            .confirmationDialog(
                "Clear nearby cache?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear cache", role: .destructive) {
                    Task {
                        await clearSnapshots()
                        await refresh()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        isLoading = true
        async let s = loadSnapshots()
        async let c = loadCurrent()
        let (newSnaps, newCurrent) = await (s, c)
        // Sort most recent first
        let sorted = newSnaps.sorted { $0.fetchedAt > $1.fetchedAt }
        await MainActor.run {
            self.snapshots = sorted
            self.current = newCurrent
            self.isLoading = false
        }
    }
}

private struct SnapshotRow: View {
    let snapshot: NearbyPlacesSnapshot
    let current: DiscoveryLocation?

    var body: some View {
        let origin = snapshot.origin
        let places = snapshot.places.count
        let distance = current.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude).distance(to: origin) }
        let distanceText = distance.map { "\(Int($0.rounded())) m" } ?? "—"

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Origin: %.6f, %.6f", origin.latitude, origin.longitude))
                    .font(.system(size: 15, weight: .semibold))
                Text("Fetched: \(snapshot.fetchedAt.formatted())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Places: \(places)")
                    .font(.system(size: 15, weight: .semibold))
                Text("Distance: \(distanceText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct NearbyCacheSnapshotDetailView: View {
    let snapshot: NearbyPlacesSnapshot
    let current: DiscoveryLocation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Snapshot") {
                    KeyValue("ID", snapshot.id.uuidString)
                    KeyValue("Fetched", snapshot.fetchedAt.formatted())
                    KeyValue("Radius (m)", String(Int(snapshot.radiusMeters)))
                    KeyValue("Origin lat", String(format: "%.6f", snapshot.origin.latitude))
                    KeyValue("Origin lon", String(format: "%.6f", snapshot.origin.longitude))
                    KeyValue("Centroid lat", String(format: "%.6f", snapshot.centroid.latitude))
                    KeyValue("Centroid lon", String(format: "%.6f", snapshot.centroid.longitude))
                    if let current {
                        let d = GeoCoordinate(latitude: current.latitude, longitude: current.longitude).distance(to: snapshot.origin)
                        KeyValue("Distance to current", "\(Int(d.rounded())) m")
                    }
                    KeyValue("Source sample", snapshot.sourceSampleId.uuidString)
                    KeyValue("Places", String(snapshot.places.count))
                }

                GroupBox("Places") {
                    if snapshot.places.isEmpty {
                        Text("No places in this snapshot")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(snapshot.places.enumerated()), id: \.offset) { idx, place in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("#\(idx + 1)  \(place.name ?? place.displayName?.text ?? place.primaryType ?? place.id)")
                                    .font(.system(size: 15, weight: .semibold))
                                if let loc = place.location {
                                    Text(String(format: "(%.6f, %.6f)", loc.latitude, loc.longitude))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                if let address = place.formattedAddress {
                                    Text(address)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Snapshot Detail")
    }
}

private struct KeyValue: View {
    let key: String
    let value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }
    var body: some View {
        HStack {
            Text(key)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote)
        }
        .padding(.vertical, 2)
    }
}
