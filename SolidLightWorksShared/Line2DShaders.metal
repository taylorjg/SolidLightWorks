//
//  Line2DShaders.metal
//  SolidLightWorksShared
//
//  Created by Administrator on 10/04/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

vertex float4 vertexLine2DShader(uint vertexID [[vertex_id]],
                                 constant Line2DVertex *vertices [[buffer(0)]],
                                 constant CommonUniforms &commonUniforms [[buffer(1)]])
{
    constant Line2DVertex &line2DVertex = vertices[vertexID];
    float4 position = float4(line2DVertex.position, 1.0);
    float4x4 mvp = commonUniforms.projectionMatrix * commonUniforms.viewMatrix * commonUniforms.modelMatrix;
    return mvp * position;
}

fragment float4 fragmentLine2DShader(constant Line2DUniforms &line2DUniforms [[buffer(1)]])
{
    return line2DUniforms.color;
}
