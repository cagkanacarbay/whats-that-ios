import CoreGraphics
import SwiftUI
import UIKit
import WhatsThatDomain

struct DiscoveryDetailContext: Identifiable {
    let sessionId: UUID
    let discovery: DiscoverySummary
    let imageURL: URL?
    let startFrame: CGRect
    let placeholderImage: UIImage?
    let cardAspectRatio: CGFloat

    var id: UUID { sessionId }
}
