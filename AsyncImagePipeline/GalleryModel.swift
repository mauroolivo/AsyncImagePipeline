import Foundation
import Observation

/// The UI model for the gallery view.
/// This is @MainActor because all UI state belongs to the main presentation domain.
@MainActor
@Observable
final class GalleryModel: Sendable {
    private(set) var events: [LogEvent] = []
    private(set) var gallery: [GalleryItem] = []
    private(set) var isRunning: Bool = false
    private(set) var metrics: PipelineMetrics?
    
    private let pipeline: AsyncImagePipeline
    private var experimentTask: Task<Void, Never>?
    
    init() {
        self.pipeline = AsyncImagePipeline()
        Task {
            await pipeline.setLogHandler { [weak self] event in
                DispatchQueue.main.async {
                    self?.events.append(event)
                    // Keep log bounded at 100 events
                    if self?.events.count ?? 0 > 100 {
                        self?.events.removeFirst()
                    }
                }
            }
        }
        
        // Debug: log app startup
        events.append(LogEvent(timestamp: Date(), message: "GalleryModel initialized, pipeline ready", level: .info))
    }
    
    // MARK: - Experiment: Duplicate Request Sharing
    
    /// Demonstrates that duplicate requests share in-flight work.
    func runDuplicateRequestExperiment() {
        cancelExperiment()
        
        experimentTask = Task {
            clearUI()
            isRunning = true
            events.append(LogEvent(timestamp: Date(), message: "=== DUPLICATE REQUEST EXPERIMENT START ===", level: .info))
            
            // These URLs include a duplicate
            let urls: [URL] = [
                NetworkLoader.imageURLs[0],
                NetworkLoader.imageURLs[1],
                NetworkLoader.imageURLs[0],  // Duplicate
            ]
            
            events.append(LogEvent(timestamp: Date(), message: "URL 0: \(urls[0].absoluteString)", level: .info))
            events.append(LogEvent(timestamp: Date(), message: "URL 1: \(urls[1].absoluteString)", level: .info))
            events.append(LogEvent(timestamp: Date(), message: "URL 2: \(urls[2].absoluteString) (duplicate of URL 0)", level: .info))
            
            events.append(LogEvent(timestamp: Date(), message: "Submitting 3 concurrent fetch tasks...", level: .info))
            
            // Launch concurrent fetch tasks
            async let fetch1 = pipeline.fetch(url: urls[0])
            async let fetch2 = pipeline.fetch(url: urls[1])
            async let fetch3 = pipeline.fetch(url: urls[2])  // Duplicate of fetch1
            
            let results = await (fetch1, fetch2, fetch3)
            
            // Log results in detail
            events.append(LogEvent(timestamp: Date(), message: "All 3 fetches completed", level: .info))
            for (i, result) in [results.0, results.1, results.2].enumerated() {
                let hasImage = result.image != nil
                let status = hasImage ? "✓ HAS IMAGE" : "✗ NO IMAGE"
                events.append(LogEvent(timestamp: Date(), message: "Request \(i+1): \(result.source.description) - \(status) - \(String(format: "%.2fs", result.duration))", level: hasImage ? .success : .error))
                if let img = result.image {
                    events.append(LogEvent(timestamp: Date(), message: "  └─ Image size: \(img.byteCount) bytes", level: .info))
                }
            }
            
            // Collect results - wrap each in GalleryItem so duplicates don't share the same ID
            let images = [results.0.image, results.1.image, results.2.image].compactMap { $0 }
            events.append(LogEvent(timestamp: Date(), message: "Successfully decoded \(images.count)/3 images", level: images.count == 3 ? .success : .warning))
            
            gallery = images.map { GalleryItem(image: $0) }
            print("[GalleryModel] Gallery array populated with \(gallery.count) items")
            for (idx, item) in gallery.enumerated() {
                print("[GalleryModel]   [\(idx)] \(item.image.filename) - \(item.image.byteCount) bytes - platformImage available: \(item.image.platformImage != nil)")
            }
            
            events.append(LogEvent(timestamp: Date(), message: "Gallery UI updated with \(gallery.count) items", level: gallery.isEmpty ? .error : .success))
            
            metrics = await pipeline.getMetrics()
            events.append(LogEvent(timestamp: Date(), message: "Metrics: \(metrics?.newWorkStarts ?? 0) new work, \(metrics?.sharedInFlightHits ?? 0) shared hits", level: .info))
            events.append(LogEvent(timestamp: Date(), message: "=== DUPLICATE REQUEST EXPERIMENT END ===", level: .info))
            
            isRunning = false
        }
    }
    
    // MARK: - Experiment: Bounded Prefetch
    
    /// Demonstrates bounded concurrent loading to keep network pressure controlled.
    func runBoundedPrefetchExperiment() {
        cancelExperiment()
        
        experimentTask = Task {
            clearUI()
            isRunning = true
            events.append(LogEvent(timestamp: Date(), message: "Starting bounded prefetch experiment", level: .info))
            
            let urls = Array(NetworkLoader.imageURLs.prefix(4))
            events.append(LogEvent(timestamp: Date(), message: "Prefetching \(urls.count) images with max concurrency of 2", level: .info))
            
            let results = await pipeline.fetchBatch(urls: urls, maxConcurrent: 2)
            let successCount = results.filter { $0.image != nil }.count
            events.append(LogEvent(timestamp: Date(), message: "Prefetch complete: \(successCount)/\(results.count) succeeded", level: successCount == results.count ? .success : .warning))
            
            gallery = results
                .compactMap { $0.image }
                .map { GalleryItem(image: $0) }
            
            events.append(LogEvent(timestamp: Date(), message: "Gallery loaded: \(gallery.count) items", level: .info))
            metrics = await pipeline.getMetrics()
            
            isRunning = false
        }
    }
    
    // MARK: - Experiment: Failure Eviction and Retry
    
    /// Demonstrates that failed entries are evicted so retry starts fresh.
    func runFailureEvictionExperiment() {
        cancelExperiment()
        
        experimentTask = Task {
            clearUI()
            isRunning = true
            events.append(LogEvent(timestamp: Date(), message: "Starting failure eviction & retry experiment", level: .info))
            
            let url = NetworkLoader.imageURLs[2]
            
            // First attempt - will fail
            events.append(LogEvent(timestamp: Date(), message: "Attempt 1: Fetching with simulated failure", level: .info))
            await pipeline.simulateFailure(for: url)
            
            let result1 = await pipeline.fetch(url: url)
            if case .failed(let reason) = result1.source {
                events.append(LogEvent(timestamp: Date(), message: "Attempt 1 failed (expected): \(reason)", level: .warning))
            } else {
                events.append(LogEvent(timestamp: Date(), message: "Attempt 1 unexpectedly succeeded: \(result1.source.description)", level: .error))
            }
            
            // Small delay
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Second attempt - should succeed because failed entry was evicted
            events.append(LogEvent(timestamp: Date(), message: "Attempt 2: Retrying after eviction", level: .info))
            let result2 = await pipeline.fetch(url: url)
            if result2.image != nil {
                events.append(LogEvent(timestamp: Date(), message: "Attempt 2 succeeded: \(result2.source.description)", level: .success))
            } else {
                events.append(LogEvent(timestamp: Date(), message: "Attempt 2 failed: \(result2.source.description)", level: .error))
            }
            
            if let image = result2.image {
                gallery = [GalleryItem(image: image)]
            }
            
            metrics = await pipeline.getMetrics()
            isRunning = false
        }
    }
    
    // MARK: - Experiment: Cancellation Under Deduplication
    
    /// Demonstrates that canceling one waiter doesn't destroy shared work for everyone else.
    func runCancellationExperiment() {
        cancelExperiment()
        
        experimentTask = Task {
            clearUI()
            isRunning = true
            events.append(LogEvent(timestamp: Date(), message: "Starting cancellation under dedup experiment", level: .info))
            
            let url = NetworkLoader.imageURLs[3]
            
            events.append(LogEvent(timestamp: Date(), message: "Caller A: Starting fetch of \(url.lastPathComponent)", level: .info))
            
            // Caller A starts fetching
            let fetchTaskA = Task {
                await pipeline.fetch(url: url)
            }
            
            // Give Caller A time to start the work
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            events.append(LogEvent(timestamp: Date(), message: "Caller B: Joining in-flight work", level: .info))
            
            // Caller B joins
            let fetchTaskB = Task {
                await pipeline.fetch(url: url)
            }
            
            // Give both time to settle
            try? await Task.sleep(nanoseconds: 150_000_000)
            
            // Caller A cancels
            events.append(LogEvent(timestamp: Date(), message: "Caller A: Canceling its wait", level: .warning))
            fetchTaskA.cancel()
            
            // But Caller B waits for completion
            events.append(LogEvent(timestamp: Date(), message: "Caller B: Continuing to wait despite A's cancellation", level: .info))
            let resultB = await fetchTaskB.value
            
            if let image = resultB.image {
                gallery = [GalleryItem(image: image)]
                events.append(LogEvent(timestamp: Date(), message: "Caller B: Success despite A's cancel: \(resultB.source.description)", level: .success))
            } else {
                events.append(LogEvent(timestamp: Date(), message: "Caller B: Failed despite retry: \(resultB.source.description)", level: .error))
            }
            
            metrics = await pipeline.getMetrics()
            isRunning = false
        }
    }
    
    // MARK: - Actions
    
    func resetPipeline() {
        experimentTask = Task {
            await pipeline.reset()
            clearUI()
        }
    }
    
    func cancelExperiment() {
        experimentTask?.cancel()
        experimentTask = nil
        isRunning = false
    }
    
    private func clearUI() {
        events.removeAll()
        gallery.removeAll()
        metrics = nil
    }
}
