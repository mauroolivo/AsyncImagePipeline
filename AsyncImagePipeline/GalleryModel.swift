import Foundation
import Observation

/// The UI model for the gallery view.
/// This is @MainActor because all UI state belongs to the main presentation domain.
@MainActor
@Observable
final class GalleryModel: Sendable {
    private(set) var events: [LogEvent] = []
    private(set) var gallery: [DecodedImage] = []
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
    }
    
    // MARK: - Experiment: Duplicate Request Sharing
    
    /// Demonstrates that duplicate requests share in-flight work.
    func runDuplicateRequestExperiment() {
        cancelExperiment()
        
        experimentTask = Task {
            clearUI()
            isRunning = true
            events.append(LogEvent(timestamp: Date(), message: "Starting duplicate request experiment", level: .info))
            
            // These URLs include a duplicate
            let urls: [URL] = [
                NetworkLoader.imageURLs[0],
                NetworkLoader.imageURLs[1],
                NetworkLoader.imageURLs[0],  // Duplicate
            ]
            
            events.append(LogEvent(timestamp: Date(), message: "Submitting 3 requests: [url0, url1, url0]", level: .info))
            
            // Launch concurrent fetch tasks
            async let fetch1 = pipeline.fetch(url: urls[0])
            async let fetch2 = pipeline.fetch(url: urls[1])
            async let fetch3 = pipeline.fetch(url: urls[2])  // Duplicate of fetch1
            
            let results = await (fetch1, fetch2, fetch3)
            
            // Collect results
            gallery = [results.0.image, results.1.image, results.2.image].compactMap { $0 }
            metrics = await pipeline.getMetrics()
            
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
            gallery = results.compactMap { $0.image }
            metrics = await pipeline.getMetrics()
            
            events.append(LogEvent(timestamp: Date(), message: "Prefetch complete. Max concurrent requests: \(metrics?.maxConcurrentRequests ?? 0)", level: .success))
            
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
            events.append(LogEvent(timestamp: Date(), message: "Attempt 1 result: \(result1.source.description)", level: .warning))
            
            // Small delay
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Second attempt - should succeed because failed entry was evicted
            events.append(LogEvent(timestamp: Date(), message: "Attempt 2: Retrying after eviction", level: .info))
            let result2 = await pipeline.fetch(url: url)
            events.append(LogEvent(timestamp: Date(), message: "Attempt 2 result: \(result2.source.description)", level: .success))
            
            if let image = result2.image {
                gallery = [image]
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
                gallery = [image]
                events.append(LogEvent(timestamp: Date(), message: "Caller B: Successfully received result \(resultB.source.description)", level: .success))
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
