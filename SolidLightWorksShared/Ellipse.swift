//
//  Ellipse.swift
//  SolidLightWorksShared
//
//  Created by Administrator on 16/04/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Foundation

class Ellipse {
    
    let cx: Float
    let cy: Float
    let rx: Float
    let ry: Float

    init(cx: Float, cy: Float, rx: Float, ry: Float) {
        self.cx = cx
        self.cy = cy
        self.rx = rx
        self.ry = ry
    }
    
    private func getPoint(angle: Float) -> simd_float2 {
        let x = cx - rx * cos(angle)
        let y = cy + ry * sin(angle)
        return simd_float2(x, y)
    }

    func getPoints(startAngle: Float, endAngle: Float, divisions: Int) -> [simd_float2] {
        let deltaAngle = endAngle - startAngle
        return (0...divisions).map { index -> simd_float2 in
            let t = Float(index) / Float(divisions)
            let angle = startAngle + deltaAngle * t
            return getPoint(angle: angle)
        }
    }
}