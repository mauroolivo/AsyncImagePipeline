import SwiftUI
import UIKit

extension DecodedImage {
    var decodedImage: UIImage? {
        guard let decodedImage = UIImage(data: imageData) else {
            print("[PlatformImage] Failed to decode image bytes (\(byteCount)) for \(filename)")
            return nil
        }
        print("[PlatformImage] ✓ Decoded image bytes (\(byteCount)) for \(filename)")
        return decodedImage
    }

    var displayImage: Image? {
        guard let decodedImage = decodedImage else { return nil }
        return Image(uiImage: decodedImage)
    }
}
