//
//  DoublingBackForm.swift
//  SolidLightWorksShared
//
//  Created by Administrator on 14/04/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Foundation

class DoublingBackForm {
    
    private let MAX_TICKS = 8900
    private let DELAY_TICKS = 120
    private let TRAVELLING_WAVE_POINT_COUNT = 200
    private let width: Float
    private let height: Float
    private let waveLength: Float
    private var tick = 0
    private var direction = 1
    private var delaying = false
    private var delayTick = 0
    private var firstTime = true
    
    init(width: Float, height: Float) {
        self.width = width
        self.height = height
        self.waveLength = width * 4 / 3
    }
    
    private func getTravellingWavePoints1() -> [simd_float2] {
        let k = 2 * Float.pi / waveLength
        let frequency = Float(1)
        let omega = 2 * Float.pi * frequency
        let speed = Float(0.0001)
        let phase = radians_from_degrees(160)
        let dx = width / Float(TRAVELLING_WAVE_POINT_COUNT)
        return (0...TRAVELLING_WAVE_POINT_COUNT).map { n -> simd_float2 in
            let x = dx * Float(n)
            let y = height / 2 * sin(k * x - omega * Float(tick) * speed + phase)
            return simd_float2(x - width / 2, y)
        }
    }
    
    private func getTravellingWavePoints2() -> [simd_float2] {
        let k = 2 * Float.pi / waveLength
        let frequency = Float(1)
        let omega = 2 * Float.pi * frequency
        let speed = Float(0.0001)
        let phase = radians_from_degrees(70)
        let dy = height / Float(TRAVELLING_WAVE_POINT_COUNT)
        let midpoint = width / 2 - height / 2
        return (0...TRAVELLING_WAVE_POINT_COUNT).map { n -> simd_float2 in
            let y = dy * Float(n)
            let x = height / 2 * sin(k * y - omega * Float(tick) * speed + phase)
            return simd_float2(midpoint - x, y - height / 2)
        }
    }
    
    func getLines() -> [Line] {
        
        if tick == MAX_TICKS || (tick == 0 && !firstTime) {
            if (delaying) {
                delayTick -= 1
                if (delayTick == 0) {
                    delaying = false
                    firstTime = false
                    direction *= -1
                }
            } else {
                delaying = true
                delayTick = DELAY_TICKS
            }
        }
        
        let points1 = getTravellingWavePoints1()
        let points2 = getTravellingWavePoints2()
        let points = [points1, points2]
        let lines = points.map { points in Line(points: points) }

        if (!delaying) {
            tick += direction
        }
        
        return lines
    }
}
