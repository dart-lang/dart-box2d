// Copyright 2012 Google Inc. All Rights Reserved.
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
/**
 * A distance proxy is used by the GJK algorithm. It encapsulates any shape.
 */

part of box2d;

class DistanceProxy {
  final List<vec2> vertices;
  int count;
  num radius;

  /**
   * Constructs a new DistanceProxy.
   */
  DistanceProxy() :
    vertices = new List<vec2>.generate(
        Settings.MAX_POLYGON_VERTICES, (i) => new vec2.zero()),
    count = 0,
    radius = 0;

  /**
   * Initialize the proxy using the given shape. The shape
   * must remain in scope while the proxy is in use.
   */
  void setFromShape(shape) {
    // If the shape is a circle...
    switch (shape.type) {
      case ShapeType.CIRCLE:
        vertices[0].copyFrom(shape.position);
        count = 1;
        radius = shape.radius;
        break;
      case ShapeType.POLYGON:
        count = shape.vertexCount;
        radius = shape.radius;
        for(int i = 0; i < count; i++) {
          vertices[i].copyFrom(shape.vertices[i]);
        }
        break;
      default:
        assert(false);
        break;
    }
  }

  /**
   * Get the supporting vertex index in the given direction.
   */
  int getSupport(vec2 direction) {
    int bestIndex = 0;
    double bestValue = dot(vertices[0], direction);
    for (int i = 1; i < count; ++i) {
      double value = dot(vertices[i], direction);
      if(value > bestValue) {
        bestIndex = i;
        bestValue = value;
      }
    }

    return bestIndex;
  }

  /**
   * Get the supporting vertex in the given direction.
   */
  vec2 getSupportVertex(vec2 direction) => vertices[getSupport(direction)];
}
