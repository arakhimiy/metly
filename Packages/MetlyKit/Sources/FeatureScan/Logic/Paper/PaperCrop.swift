import CoreGraphics

/// Where the on-screen card guide falls in the captured photo, so only the card is read (not the
/// laptop or desk around it). The preview fills its view (aspect fill): the photo is scaled to cover
/// it and centred, and the guide maps back through that. A margin forgives a card held a bit off.
nonisolated enum PaperCrop {
    /// - Parameters:
    ///   - guide: the card guide, in the same coordinate space as `preview`.
    ///   - photoSize: the upright photo's size.
    /// - Returns: the region of the photo to read, or nil when it can't be worked out.
    static func region(guide: CGRect, preview: CGRect, photoSize: CGSize, margin: CGFloat = 0.08) -> CGRect? {
        guard guide.width > 0, guide.height > 0, preview.width > 0, preview.height > 0,
              photoSize.width > 0, photoSize.height > 0 else { return nil }
        let scale = max(preview.width / photoSize.width, preview.height / photoSize.height)
        let origin = CGPoint(x: preview.midX - photoSize.width * scale / 2, y: preview.midY - photoSize.height * scale / 2)
        let padded = guide.insetBy(dx: -guide.width * margin, dy: -guide.height * margin)
        let inPhoto = CGRect(x: (padded.minX - origin.x) / scale, y: (padded.minY - origin.y) / scale,
                             width: padded.width / scale, height: padded.height / scale)
        let clipped = inPhoto.intersection(CGRect(origin: .zero, size: photoSize)).integral
        return clipped.isNull || clipped.width < 1 || clipped.height < 1 ? nil : clipped
    }
}
