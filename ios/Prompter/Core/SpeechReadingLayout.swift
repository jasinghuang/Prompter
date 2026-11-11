import CoreGraphics

/// Portrait has an invisible upper reading zone. Landscape follows the camera
/// capsule's vertical center. A bounded lead counters recognition/render delay;
/// it never scrolls on its own while the speech gate is paused.
enum SpeechReadingLayout {
    static func anchor(in size: CGSize, voice: Bool) -> CGFloat {
        size.height * (voice && size.height >= size.width ? 1.0 / 3 : 0.5)
    }

    static func lead(in size: CGSize, lineHeight: CGFloat, safeTop: CGFloat) -> CGFloat {
        let anchor = anchor(in: size, voice: true)
        return min(lineHeight, max(0, anchor - (safeTop + 68) - lineHeight / 2))
    }
}
