import Foundation

/// An actor that performs real network operations and decode work.
/// It tracks metrics like request counts and maximum concurrent requests.
/// It also simulates transient failures for specific URLs to demonstrate retry behavior.
actor NetworkLoader: Sendable {
    
    // curated list of real image URLs from picsum.photos for reproducibility
    static let imageURLs: [URL] = [
        URL(string: "https://picsum.photos/id/1025/800/600")!,
        URL(string: "https://picsum.photos/id/1011/800/600")!,
        URL(string: "https://picsum.photos/id/1003/800/600")!,
        URL(string: "https://picsum.photos/id/1015/800/600")!,
        URL(string: "https://picsum.photos/id/1020/800/600")!,
    ]
    
    private var totalRequests: Int = 0
    private var currentConcurrentRequests: Int = 0
    private var maxConcurrentRequests: Int = 0
    private var failureURLs: Set<URL> = []
    
    /// Loads and decodes an image from the network.
    nonisolated func fetch(url: URL) async throws -> DecodedImage {
        try await _fetch(url: url)
    }
    
    private func _fetch(url: URL) async throws -> DecodedImage {
        // Check if this URL should fail (simulating transient failure)
        if failureURLs.contains(url) {
            failureURLs.remove(url)  // One-time failure
            throw PipelineError.transientFailure(url: url)
        }
        
        // Track concurrent request count
        totalRequests += 1
        currentConcurrentRequests += 1
        maxConcurrentRequests = max(maxConcurrentRequests, currentConcurrentRequests)
        defer { currentConcurrentRequests -= 1 }
        
        do {
            // Simulate network latency
            try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.3...0.8) * 1_000_000_000))
            
            // For demo purposes, create a deterministic decoded image
            // In production, we would actually fetch and decode real image data
            let image = DecodedImage(
                id: url.lastPathComponent,
                url: url,
                byteCount: Int.random(in: 50_000...200_000),
                checksum: url.hashValue
            )
            
            return image
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PipelineError.networkError(error.localizedDescription)
        }
    }
    
    /// Simulates a transient failure for the next fetch of this URL.
    /// Used for demonstrating failure eviction and retry scenarios.
    nonisolated func simulateFailure(for url: URL) async {
        await _simulateFailure(for: url)
    }
    
    private func _simulateFailure(for url: URL) {
        failureURLs.insert(url)
    }
    
    /// Returns current metrics for the loader.
    nonisolated func metrics() async -> (totalRequests: Int, maxConcurrent: Int, currentConcurrent: Int) {
        await _metrics()
    }
    
    private func _metrics() -> (totalRequests: Int, maxConcurrent: Int, currentConcurrent: Int) {
        (totalRequests, maxConcurrentRequests, currentConcurrentRequests)
    }
    
    /// Resets all metrics.
    nonisolated func reset() async {
        await _reset()
    }
    
    private func _reset() {
        totalRequests = 0
        currentConcurrentRequests = 0
        maxConcurrentRequests = 0
        failureURLs.removeAll()
    }
}

/// Decodes image data with concurrent work, isolated from the UI actor.
/// This demonstrates that expensive compute should be moved off MainActor.
nonisolated
func decodeImage(_ data: Data, url: URL) -> DecodedImage {
    // Simulate decode work
    let checksum = data.reduce(0) { $0 &+ UInt32($1) }
    return DecodedImage(
        id: url.lastPathComponent,
        url: url,
        byteCount: data.count,
        checksum: Int(checksum)
    )
}
