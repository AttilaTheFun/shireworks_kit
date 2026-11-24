// The one place IssueComposer reaches for a platform's image type.
#if canImport(UIKit)
import SwiftUI
import UIKit

extension Image {
    init?(attachmentData data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
    }
}
#elseif canImport(AppKit)
import AppKit
import SwiftUI

extension Image {
    init?(attachmentData data: Data) {
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
    }
}
#elseif canImport(SwiftUI)
import Foundation
import SwiftUI

extension Image {
    init?(attachmentData data: Data) { nil }
}
#endif
