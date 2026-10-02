# AsyncImagePipeline

A SwiftUI sample app that demonstrates production-minded Swift Concurrency patterns for image loading.

This repository is the runnable companion to the article (link to be added).

## What this demo shows

- Duplicate request deduplication (shared in-flight work)
- Bounded prefetch concurrency
- Failure eviction and retry
- Cancellation behavior with shared work

## Requirements

- Xcode 26+
- iOS 26 simulator/device (project currently targets iOS 17.6+, but latest tooling is recommended)

## Run

1. Open `AsyncImagePipeline.xcodeproj` in Xcode.
2. Select the `AsyncImagePipeline` scheme.
3. Run on an iPhone simulator.
4. Use the 4 tabs to run each experiment.

## Optional verbose console logs

Verbose diagnostics are disabled by default for cleaner runs.

To enable them, add this environment variable in the run scheme:

- `PIPELINE_VERBOSE_LOGS=1`
