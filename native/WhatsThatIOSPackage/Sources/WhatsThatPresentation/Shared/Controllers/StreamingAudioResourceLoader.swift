import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Bridges progressive audio data chunks to AVPlayer via a custom URL scheme.
///
/// Usage:
/// 1. Create an instance
/// 2. Create `AVURLAsset` with `x-streaming-voiceover://discovery/{id}`
/// 3. Set `asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)`
/// 4. Feed data via `appendData(_:)` as it arrives
/// 5. Call `markComplete()` when all data has arrived
final class StreamingAudioResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "x-streaming-voiceover"

    let loaderQueue = DispatchQueue(label: "com.whatsthat.streaming-audio-loader")

    private var buffer = Data()
    private var pendingRequests: [AVAssetResourceLoadingRequest] = []
    private var isComplete = false

    /// Append newly received audio data and attempt to serve pending requests.
    func appendData(_ data: Data) {
        loaderQueue.async { [self] in
            buffer.append(data)
            processPendingRequests()
        }
    }

    /// Mark the stream as complete (all data received). Finalizes pending requests.
    func markComplete() {
        loaderQueue.async { [self] in
            isComplete = true
            processPendingRequests()
        }
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        pendingRequests.append(loadingRequest)
        processPendingRequests()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        pendingRequests.removeAll { $0 === loadingRequest }
    }

    // MARK: - Private

    private func processPendingRequests() {
        var completed: [AVAssetResourceLoadingRequest] = []

        for request in pendingRequests {
            // Fill content information if requested
            if let contentInfo = request.contentInformationRequest {
                contentInfo.contentType = UTType.mp3.identifier
                contentInfo.isByteRangeAccessSupported = false
                if isComplete {
                    contentInfo.contentLength = Int64(buffer.count)
                } else {
                    // AVPlayer needs a non-zero contentLength to begin parsing audio frames.
                    // The actual end-of-stream is signalled by finishLoading() when markComplete() is called.
                    contentInfo.contentLength = Int64(10_000_000) // 10 MB estimate
                }
            }

            // Fill data if requested
            if let dataRequest = request.dataRequest {
                // currentOffset tracks where we left off after previous respond(with:) calls.
                // requestedOffset is the immutable original offset and must NOT be used for
                // subsequent respond(with:) calls — doing so would re-send already-delivered bytes.
                let currentOffset = Int(dataRequest.currentOffset)
                let requestEnd: Int
                if dataRequest.requestsAllDataToEndOfResource {
                    requestEnd = isComplete ? buffer.count : Int.max
                } else {
                    requestEnd = Int(dataRequest.requestedOffset) + dataRequest.requestedLength
                }

                if currentOffset >= buffer.count {
                    // No new data available at this offset yet
                    if isComplete {
                        request.finishLoading()
                        completed.append(request)
                    }
                    continue
                }

                let availableEnd = min(requestEnd, buffer.count)
                if currentOffset < availableEnd {
                    let dataSlice = buffer.subdata(in: currentOffset..<availableEnd)
                    dataRequest.respond(with: dataSlice)
                }

                let fullyServed = availableEnd >= requestEnd
                if fullyServed || (isComplete && currentOffset >= buffer.count) {
                    request.finishLoading()
                    completed.append(request)
                }
            } else {
                // No data request — just content info
                request.finishLoading()
                completed.append(request)
            }
        }

        pendingRequests.removeAll { req in completed.contains { $0 === req } }
    }
}
