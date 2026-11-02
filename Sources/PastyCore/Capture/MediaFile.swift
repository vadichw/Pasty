import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Helpers for image and video files: type detection, thumbnails, metadata.
enum MediaFile {
    enum Kind {
        case image, video
    }

    static let thumbnailMaxPixels = 320

    static func kind(of url: URL) -> Kind? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        return nil
    }

    struct ImageInfo {
        var thumbnail: Data?
        var width: Int
        var height: Int
    }

    static func imageInfo(url: URL) -> ImageInfo? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(imageInfo(source:))
    }

    static func imageInfo(data: Data) -> ImageInfo? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(imageInfo(source:))
    }

    private static func imageInfo(source: CGImageSource) -> ImageInfo? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,
        ] as CFDictionary
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        return ImageInfo(
            thumbnail: thumbnail.flatMap(pngData),
            width: props?[kCGImagePropertyPixelWidth] as? Int ?? 0,
            height: props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
    }

    struct VideoInfo {
        var thumbnail: Data?
        var duration: Double?
    }

    static func videoInfo(url: URL) async -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnailMaxPixels, height: thumbnailMaxPixels)
        let time = CMTime(seconds: min(1, (duration ?? 0) / 2), preferredTimescale: 600)
        let image = try? await generator.image(at: time).image
        return VideoInfo(thumbnail: image.flatMap(pngData), duration: duration)
    }

    /// A video's frame size in pixels, as displayed (rotation applied); nil if it can't be read.
    static func videoSize(url: URL) async -> NSSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return NSSize(width: abs(rect.width), height: abs(rect.height))
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
