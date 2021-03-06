//
//  CouplingInstallation.swift
//  SolidLightWorksShared
//
//  Created by Administrator on 18/04/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Foundation

class CouplingInstallation: Installation {
    
    private let form = CouplingForm(outerRadius: 2, innerRadius: 1)
    
    func getInstallationData2D() -> InstallationData2D {
        let lines = form.getLines()
        let transform = matrix_identity_float4x4
        let screenForm = ScreenForm(lines: lines, transform: transform)
        let screenForms = [screenForm]
        let cameraPose = CameraPose(position: simd_float3(0, 0, 5), target: simd_float3())
        return InstallationData2D(screenForms: screenForms, cameraPose: cameraPose)
    }
    
    func getInstallationData3D() -> InstallationData3D {
        let lines = form.getLines()
        let rotationX = matrix4x4_rotation(radians: -Float.pi / 2, axis: simd_float3(1, 0, 0))
        let transform = matrix4x4_translation(0, 0, 4) * rotationX
        let screenForm = ScreenForm(lines: lines, transform: transform)
        let screenForms = [screenForm]
        let projectorPosition = simd_float3(0, 0, 10)
        let projectedForm = ProjectedForm(lines: lines,
                                          transform: transform,
                                          projectorPosition: projectorPosition)
        let projectedForms = [projectedForm]
        let cameraPoses = [
            CameraPose(position: simd_float3(0, 1, 8.5), target: simd_float3(0, 0, 0))
        ]
        return InstallationData3D(screenForms: screenForms,
                                  projectedForms: projectedForms,
                                  cameraPoses: cameraPoses,
                                  screen: nil,
                                  floor: Floor(width: 12, depth: 8),
                                  leftWall: nil)
    }
}
