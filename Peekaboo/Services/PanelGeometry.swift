import CoreGraphics

enum PanelGeometry {
    static let triggerSize: CGFloat = 16
    static let panelWidth: CGFloat = 332
    static let minimumHeight: CGFloat = 380
    static let maximumHeight: CGFloat = 700
    static let screenInset: CGFloat = 12

    static func hotspot(in screenFrame: CGRect, corner: ScreenCorner, size: CGFloat = triggerSize) -> CGRect {
        let origin: CGPoint
        switch corner {
        case .topLeft:
            origin = CGPoint(x: screenFrame.minX, y: screenFrame.maxY - size)
        case .topRight:
            origin = CGPoint(x: screenFrame.maxX - size, y: screenFrame.maxY - size)
        case .bottomLeft:
            origin = CGPoint(x: screenFrame.minX, y: screenFrame.minY)
        case .bottomRight:
            origin = CGPoint(x: screenFrame.maxX - size, y: screenFrame.minY)
        }
        return CGRect(origin: origin, size: CGSize(width: size, height: size))
    }

    static func panelFrame(
        in visibleFrame: CGRect,
        size: CGSize,
        corner: ScreenCorner,
        inset: CGFloat = screenInset
    ) -> CGRect {
        let x: CGFloat
        let y: CGFloat

        switch corner {
        case .topLeft, .bottomLeft:
            x = visibleFrame.minX + inset
        case .topRight, .bottomRight:
            x = visibleFrame.maxX - size.width - inset
        }

        switch corner {
        case .topLeft, .topRight:
            y = visibleFrame.maxY - size.height - inset
        case .bottomLeft, .bottomRight:
            y = visibleFrame.minY + inset
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func hiddenFrame(from visibleFrame: CGRect, corner: ScreenCorner, distance: CGFloat = 18) -> CGRect {
        let xOffset: CGFloat
        let yOffset: CGFloat
        switch corner {
        case .topLeft:
            xOffset = -distance
            yOffset = distance
        case .topRight:
            xOffset = distance
            yOffset = distance
        case .bottomLeft:
            xOffset = -distance
            yOffset = -distance
        case .bottomRight:
            xOffset = distance
            yOffset = -distance
        }
        return visibleFrame.offsetBy(dx: xOffset, dy: yOffset)
    }

    static func preferredHeight(taskCount: Int, sectionCount: Int, isComposing: Bool) -> CGFloat {
        let header: CGFloat = 76
        let composer: CGFloat = isComposing ? 70 : 0
        let taskGaps = max(taskCount - sectionCount, 0)
        let content: CGFloat = taskCount == 0
            ? 90
            : CGFloat(taskCount) * PeekabooStyle.rowHeight
                + CGFloat(taskGaps) * PeekabooStyle.taskSpacing
                + CGFloat(sectionCount) * 24
                + 10
        return min(max(header + composer + content + 16, minimumHeight), maximumHeight)
    }
}
