import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @State var model = GalleryModel()
    @State private var galleryContainerWidth: CGFloat = 0
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    var body: some View {
        if isCompact {
            compactLayout
        } else {
            NavigationSplitView {
                // Primary view: controls
                controlPanel
                    .navigationTitle("Pipeline")
            } detail: {
                // Detail view: gallery and log
                galleryAndLog
            }
        }
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controlPanelContent
                galleryAndLog
            }
            .padding()
        }
        .navigationTitle("Pipeline")
    }
    
    // MARK: - Control Panel
    
    private var controlPanel: some View {
        ScrollView {
            controlPanelContent
        }
    }

    private var controlPanelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Experiments")
                .font(.headline)
                .padding(.top, 8)
            
            VStack(spacing: 12) {
                experimentButton(
                    "Duplicate Requests",
                    description: "Submit 3 requests, including a duplicate. Shows in-flight deduplication.",
                    action: model.runDuplicateRequestExperiment
                )
                
                experimentButton(
                    "Bounded Prefetch",
                    description: "Load 4 images with max 2 concurrent. Shows bounded concurrency.",
                    action: model.runBoundedPrefetchExperiment
                )
                
                experimentButton(
                    "Failure & Retry",
                    description: "Trigger failure, then retry. Shows eviction semantics.",
                    action: model.runFailureEvictionExperiment
                )
                
                experimentButton(
                    "Cancellation",
                    description: "Cancel one waiter, let shared work complete for another.",
                    action: model.runCancellationExperiment
                )
            }
            
            Divider()
                .padding(.vertical, 8)
            
            VStack(spacing: 12) {
                Button(action: model.resetPipeline) {
                    Label("Reset Pipeline", systemImage: "arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .center)
                
                if model.isRunning {
                    Button(action: model.cancelExperiment) {
                        Label("Cancel Experiment", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            
            if let metrics = model.metrics {
                Divider()
                    .padding(.vertical, 8)
                
                metricsPanel(metrics)
            }
        }
    }
    
    private func experimentButton(
        _ title: String,
        description: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .disabled(model.isRunning)
        .foregroundStyle(.primary)
    }
    
    private func metricsPanel(_ metrics: PipelineMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrics")
                .font(.headline)
            
            metricRow("Total Fetches", value: "\(metrics.totalFetches)")
            metricRow("New Work Starts", value: "\(metrics.newWorkStarts)")
            metricRow("Shared In-Flight Hits", value: "\(metrics.sharedInFlightHits)")
            metricRow("Cache Hits", value: "\(metrics.cacheHits)")
            metricRow("Max Concurrent", value: "\(metrics.maxConcurrentRequests)")
            metricRow("In-Flight Now", value: "\(metrics.currentInFlightCount)")
        }
        .font(.caption)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
    
    // MARK: - Gallery and Log
    
    private var galleryAndLog: some View {
        VStack(spacing: 0) {
            // Gallery
            if !model.gallery.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Gallery")
                            .font(.headline)
                        Spacer()
                        Text("\(model.gallery.count) image\(model.gallery.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    LazyVGrid(columns: galleryColumns, spacing: isCompact ? 8 : 12) {
                        ForEach(model.gallery) { item in
                            galleryCell(item.image)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: GalleryWidthKey.self, value: proxy.size.width)
                        }
                    )
                }
                .background(Color(.systemGray6))
            } else {
                // Debug info when gallery is empty
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Gallery 3")
                            .font(.headline)
                        Spacer()
                        Text("empty")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    Text("Run an experiment to load images. Check the event log below for details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                    
                    Spacer()
                }
                .background(Color(.systemGray6))
                .frame(height: 120)
            }
            
            // Event Log
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Event Log")
                        .font(.headline)
                    Spacer()
                    if model.isRunning {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.events) { event in
                            logEventRow(event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .onPreferenceChange(GalleryWidthKey.self) { width in
            if width > 0 {
                galleryContainerWidth = width
            }
        }
    }

    private var galleryColumns: [GridItem] {
        let count = isCompact ? 2 : 3
        let spacing = gallerySpacing
        let side = galleryTileSide
        return Array(repeating: GridItem(.fixed(side), spacing: spacing, alignment: .top), count: count)
    }

    private var gallerySpacing: CGFloat {
        isCompact ? 8 : 10
    }

    private var galleryTileSide: CGFloat {
        let count = isCompact ? 2 : 3
        let width = galleryContainerWidth > 0
            ? galleryContainerWidth
            : (isCompact ? UIScreen.main.bounds.width - 32 : UIScreen.main.bounds.width - 48)
        let totalSpacing = gallerySpacing * CGFloat(max(count - 1, 0))
        let calculated = floor((width - totalSpacing) / CGFloat(count))
        return max(calculated, isCompact ? 110 : 150)
    }

    @ViewBuilder
    private func galleryCell(_ image: DecodedImage) -> some View {
        let swiftUIImage = image.swiftUIImage
        let hasImage = swiftUIImage != nil
        let side = galleryTileSide
        
        ZStack {
            if hasImage {
                swiftUIImage!
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray5))
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 24, weight: .medium))
                        Text("Failed to decode")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .onAppear {
                    print("[GalleryCell] Image \(image.filename) failed: swiftUIImage returned nil for \(image.byteCount) bytes")
                }
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        .onAppear {
            print("[GalleryCell] Cell appeared: \(image.filename) - hasImage: \(hasImage)")
        }
    }

    private func byteCountString(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
    
    private func logEventRow(_ event: LogEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            eventBadge(event.level)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.caption)
                    .lineLimit(nil)
                
                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6))
        .cornerRadius(4)
    }
    
    private func eventBadge(_ level: LogEvent.Level) -> some View {
        Image(systemName: iconForLevel(level))
            .font(.caption)
            .foregroundStyle(colorForLevel(level))
            .frame(width: 20)
    }
    
    private func iconForLevel(_ level: LogEvent.Level) -> String {
        switch level {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.circle"
        case .error:
            return "xmark.circle"
        }
    }
    
    private func colorForLevel(_ level: LogEvent.Level) -> Color {
        switch level {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

#Preview {
    ContentView()
}

private struct GalleryWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
