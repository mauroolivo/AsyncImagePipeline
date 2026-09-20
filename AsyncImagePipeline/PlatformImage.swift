import SwiftUI
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage

struct PlatformImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = image
    }
}
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

extension DecodedImage {
    var platformImage: PlatformImage? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: imageData) else {
            print("[PlatformImage] Failed to create UIImage from \(byteCount) bytes for \(filename)")
            return nil
        }
        print("[PlatformImage] ✓ Created UIImage from \(byteCount) bytes for \(filename)")
        return uiImage
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: imageData) else {
            print("[PlatformImage] Failed to create NSImage from \(byteCount) bytes for \(filename)")
            return nil
        }
        print("[PlatformImage] ✓ Created NSImage from \(byteCount) bytes for \(filename)")
        return nsImage
        #else
        print("[PlatformImage] No platform image support")
        return nil
        #endif
    }

    var swiftUIImage: Image? {
        #if canImport(UIKit)
        guard let uiImage = platformImage else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = platformImage else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
}
