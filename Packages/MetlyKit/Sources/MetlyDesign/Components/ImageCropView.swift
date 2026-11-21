import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A picked photo waiting to be cropped (drives `.imageCropper(item:onCrop:)`).
public struct CropImage: Identifiable {
    public let id = UUID()
    let image: CGImage

    /// Decodes picked image data upright (EXIF orientation applied), at most `maxPixelSize` on the long
    /// side so a 48 MP photo doesn't sit in memory while the person drags it around.
    public static func load(_ data: Data, maxPixelSize: Int = 2048) async -> CropImage? {
        guard let decoded = await DecodedImage.decode(data, maxPixelSize: maxPixelSize) else { return nil }
        return CropImage(image: decoded.image)
    }
}

/// CGImage is immutable; the wrapper only carries it from the decoding task back to the main actor.
private struct DecodedImage: @unchecked Sendable {
    let image: CGImage

    @concurrent
    nonisolated static func decode(_ data: Data, maxPixelSize: Int) async -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return DecodedImage(image: image)
    }
}

public extension View {
    /// Full-screen "Move and Scale" step after a photo is picked. `onCrop` receives a square JPEG of the
    /// chosen area (callers still downscale it); cancelling just dismisses.
    func imageCropper(item: Binding<CropImage?>, onCrop: @escaping (Data) -> Void) -> some View {
        fullScreenCover(item: item) { crop in
            ImageCropView(image: crop.image) {
                item.wrappedValue = nil
            } onCrop: { data in
                item.wrappedValue = nil
                onCrop(data)
            }
        }
    }
}

/// Pinch to zoom and drag to move a photo under a round frame; the result is the square around that circle.
/// The image always covers the frame, so there are never empty corners.
struct ImageCropView: View {
    let image: CGImage
    let onCancel: () -> Void
    let onCrop: (Data) -> Void

    /// Zoom relative to "just fills the frame" (1).
    @State private var zoom: CGFloat = 1
    /// Pan of the image centre from the frame centre, in points.
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private static let maxZoom: CGFloat = 5
    private static let margin: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let side = max(1, min(proxy.size.width, proxy.size.height) - Self.margin * 2)
            let liveZoom = clampedZoom(zoom * pinch)
            let liveOffset = clampedOffset(CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
                                           zoom: liveZoom, side: side)
            let size = displaySize(zoom: liveZoom, side: side)

            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .offset(liveOffset)

                CropFrameOverlay(side: side)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(.rect)
            .gesture(cropGesture(side: side))
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    zoom = zoom > 1.01 ? 1 : 2
                    offset = clampedOffset(offset, zoom: zoom, side: side)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Photo"))
            .accessibilityValue(Text("Zoom \(Int((zoom * 100).rounded())) percent"))
            .accessibilityHint(Text("Swipe up or down to zoom"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: zoom = clampedZoom(zoom * 1.25)
                case .decrement: zoom = clampedZoom(zoom / 1.25)
                @unknown default: break
                }
                offset = clampedOffset(offset, zoom: zoom, side: side)
            }
            .overlay(alignment: .top) {
                Text("Move and Scale")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isHeader)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Button("Choose") { choose(side: side) }
                        .fontWeight(.semibold)
                }
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }

    private func cropGesture(side: CGFloat) -> some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    zoom = clampedZoom(zoom * value.magnification)
                    offset = clampedOffset(offset, zoom: zoom, side: side)
                },
            DragGesture(minimumDistance: 0)
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    offset = clampedOffset(CGSize(width: offset.width + value.translation.width,
                                                  height: offset.height + value.translation.height),
                                           zoom: zoom, side: side)
                }
        )
    }

    // MARK: Geometry

    private var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }

    /// Points per image pixel at the given zoom (zoom 1 = the short side fills the frame).
    private func pointsPerPixel(zoom: CGFloat, side: CGFloat) -> CGFloat {
        side / max(1, min(pixelSize.width, pixelSize.height)) * zoom
    }

    private func displaySize(zoom: CGFloat, side: CGFloat) -> CGSize {
        let k = pointsPerPixel(zoom: zoom, side: side)
        return CGSize(width: pixelSize.width * k, height: pixelSize.height * k)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), Self.maxZoom)
    }

    /// Keeps the frame inside the image.
    private func clampedOffset(_ value: CGSize, zoom: CGFloat, side: CGFloat) -> CGSize {
        let size = displaySize(zoom: zoom, side: side)
        let maxX = max(0, (size.width - side) / 2)
        let maxY = max(0, (size.height - side) / 2)
        return CGSize(width: min(max(value.width, -maxX), maxX), height: min(max(value.height, -maxY), maxY))
    }

    // MARK: Output

    private func choose(side: CGFloat) {
        let k = pointsPerPixel(zoom: zoom, side: side)
        let cropSide = min(side / k, pixelSize.width, pixelSize.height)
        // The frame centre sits `-offset` from the image centre.
        var x = pixelSize.width / 2 - offset.width / k - cropSide / 2
        var y = pixelSize.height / 2 - offset.height / k - cropSide / 2
        x = min(max(x, 0), pixelSize.width - cropSide)
        y = min(max(y, 0), pixelSize.height - cropSide)
        let rect = CGRect(x: x, y: y, width: cropSide, height: cropSide).integral
        guard let cropped = image.cropping(to: rect), let data = Self.jpeg(cropped) else {
            onCancel()
            return
        }
        onCrop(data)
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// Dims everything outside a centred circle and outlines it.
private struct CropFrameOverlay: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            HoleShape(diameter: side)
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: side, height: side)
        }
    }
}

private struct HoleShape: Shape {
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter))
        return path
    }
}
