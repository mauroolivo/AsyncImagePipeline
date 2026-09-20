import SwiftUI

struct ContentView: View {
    @State var model = GalleryModel()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    var body: some View {
        NavigationSplitView {
            // Primary view: controls
            controlPanel
                .navigationTitle("Pipeline")
        } detail: {
            // Detail view: gallery and log
            galleryAndLog
        }
    }
    
    // MARK: - Control Panel
    
    private var controlPanel: some View {
        ScrollView {
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
                
                Spacer()
            }
            .padding()
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.gallery) { image in
                            VStack(spacing: 4) {
                                Image(systemName: "photo")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tint)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 140)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                                
                                Text(image.id)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(width: 120)
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGray6))
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
