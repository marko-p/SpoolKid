//
//  FloatingBottomBarTests.swift
//  SpoolKidTests
//
//  The floating bottom bar lines its sides up with iOS 26's floating tab bar,
//  so its outermost buttons sit under the thumb, not at the screen edge.
//

import CoreGraphics
import Testing
@testable import SpoolKid

struct FloatingBottomBarTests {

    @Test func aFloatingTabBarSetsTheInsetOnEveryPhoneWidth() {
        // iPhone 17e, 17 and 17 Pro Max: the tab bar is 273 pt wide, centred.
        #expect(FloatingBottomBarMetrics.sideInset(containerWidth: 390, floatingTabBar: true) == 58.5)
        #expect(FloatingBottomBarMetrics.sideInset(containerWidth: 402, floatingTabBar: true) == 64.5)
        #expect(FloatingBottomBarMetrics.sideInset(containerWidth: 440, floatingTabBar: true) == 83.5)
    }

    @Test func aFullWidthTabBarKeepsTheStandardMargin() {
        #expect(FloatingBottomBarMetrics.sideInset(containerWidth: 402, floatingTabBar: false) == 16)
    }

    @Test func aNarrowScreenNeverGoesBelowTheStandardMargin() {
        #expect(FloatingBottomBarMetrics.sideInset(containerWidth: 290, floatingTabBar: true) == 16)
    }

    @Test func aZeroWideContainerGivesAZeroWideBarNotANegativeOne() {
        #expect(FloatingBottomBarMetrics.barWidth(containerWidth: 0, floatingTabBar: true) == 0)
        #expect(FloatingBottomBarMetrics.barWidth(containerWidth: 0, floatingTabBar: false) == 0)
        #expect(FloatingBottomBarMetrics.barWidth(containerWidth: 402, floatingTabBar: true) == 273)
    }
}
