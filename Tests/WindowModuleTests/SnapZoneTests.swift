import CoreGraphics
import Testing
@testable import WindowModule

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

@Test func edgesAndCorners() {
    #expect(SnapZone.at(CGPoint(x: 0, y: 450), screen: screen) == .left)
    #expect(SnapZone.at(CGPoint(x: 1439, y: 450), screen: screen) == .right)
    #expect(SnapZone.at(CGPoint(x: 700, y: 899), screen: screen) == .maximize)
    #expect(SnapZone.at(CGPoint(x: 0, y: 880), screen: screen) == .topLeft)
    #expect(SnapZone.at(CGPoint(x: 1420, y: 0), screen: screen) == .bottomRight)
    #expect(SnapZone.at(CGPoint(x: 700, y: 0), screen: screen) == nil) // 아래 가운데는 Dock 자리
    #expect(SnapZone.at(CGPoint(x: 700, y: 450), screen: screen) == nil)
}

@Test func secondScreenOffset() {
    let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    #expect(SnapZone.at(CGPoint(x: 1440, y: 500), screen: right) == .left)
}

@Test func targetFrames() {
    let area = CGRect(x: 0, y: 80, width: 1440, height: 795)
    #expect(SnapZone.left.frame(in: area) == CGRect(x: 0, y: 80, width: 720, height: 795))
    #expect(SnapZone.topRight.frame(in: area) == CGRect(x: 720, y: 477.5, width: 720, height: 397.5))
    #expect(SnapZone.maximize.frame(in: area) == area)
}
