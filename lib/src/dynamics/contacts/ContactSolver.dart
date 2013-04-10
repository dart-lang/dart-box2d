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

part of box2d;

class ContactSolver {
  /**
   * For each solver, this is the initial number of constraints
   * in the array, which expands as needed.
   */
  static const int INITIAL_NUM_CONSTRAINTS = 256;

  /**
   * Ensure a reasonable condition number. For the block solver
   */
  static const num K_MAX_CONDITION_NUMBER = 100.0;

  List<ContactConstraint> constraints;
  int constraintCount;

  /** Pooling */
  //TODO(gregbglw): What do many of these names mean? What is rA, for example?
  final WorldManifold worldManifold;
  final vec2 tangent;
  final vec2 temp1;
  final vec2 temp2;
  final vec2 P;
  final vec2 dv;
  final vec2 dv1;
  final vec2 dv2;
  final vec2 x;
  final vec2 d;
  final vec2 P1;
  final vec2 P2;
  final PositionSolverManifold psolver;
  final vec2 rA;
  final vec2 rB;

  /** Constructs a new ContactSolver. */
  ContactSolver() :
    constraints = new List<ContactConstraint>.generate(
        INITIAL_NUM_CONSTRAINTS, (i) => new ContactConstraint()),

    // Setup pool variables.
    worldManifold = new WorldManifold(),
    tangent = new vec2.zero(),
    temp1 = new vec2.zero(),
    temp2 = new vec2.zero(),
    P = new vec2.zero(),
    dv = new vec2.zero(),
    dv1 = new vec2.zero(),
    dv2 = new vec2.zero(),
    x = new vec2.zero(),
    d = new vec2.zero(),
    P1 = new vec2.zero(),
    P2 = new vec2.zero(),
    psolver = new PositionSolverManifold(),
    rA = new vec2.zero(),
    rB = new vec2.zero();

  void init(List<Contact> contacts, int contactCount, num impulseRatio){
    constraintCount = contactCount;

    // dynamic array
    if(constraints.length < contactCount){
      List<ContactConstraint> old = constraints;
      int newLen = math.max(old.length * 2, constraintCount);
      constraints = new List<ContactConstraint>(newLen);
      constraints.setRange(0, old.length, old);

      for(int i=old.length; i < constraints.length; i++){
        constraints[i] = new ContactConstraint();
      }
    }

    for (int i = 0; i < constraintCount; ++i){
      Contact contact = contacts[i];

      Fixture fixtureA = contact.fixtureA;
      Fixture fixtureB = contact.fixtureB;
      Shape shapeA = fixtureA.shape;
      Shape shapeB = fixtureB.shape;
      num radiusA = shapeA.radius;
      num radiusB = shapeB.radius;
      Body bodyA = fixtureA.body;
      Body bodyB = fixtureB.body;
      Manifold manifold = contact.manifold;

      num friction = Settings.mixFriction(fixtureA.friction,
          fixtureB.friction);
      num restitution = Settings.mixRestitution(fixtureA.restitution,
          fixtureB.restitution);

      vec2 vA = bodyA.linearVelocity;
      vec2 vB = bodyB.linearVelocity;
      num wA = bodyA.angularVelocity;
      num wB = bodyB.angularVelocity;

      assert(manifold.pointCount > 0);

      worldManifold.initialize(manifold, bodyA.originTransform, radiusA,
          bodyB.originTransform, radiusB);

      ContactConstraint cc = constraints[i];
      cc.bodyA = bodyA;
      cc.bodyB = bodyB;
      cc.manifold = manifold;
      cc.normal.x = worldManifold.normal.x;
      cc.normal.y = worldManifold.normal.y; // have to set actual manifold
      cc.pointCount = manifold.pointCount;
      cc.friction = friction;
      cc.restitution = restitution;
      cc.localNormal.x = manifold.localNormal.x;
      cc.localNormal.y = manifold.localNormal.y;
      cc.localPoint.x = manifold.localPoint.x;
      cc.localPoint.y = manifold.localPoint.y;
      cc.radius = radiusA + radiusB;
      cc.type = manifold.type;

      for (int j = 0; j < cc.pointCount; ++j){
        ManifoldPoint cp = manifold.points[j];
        ContactConstraintPoint ccp = cc.points[j];

        ccp.normalImpulse = impulseRatio * cp.normalImpulse;
        ccp.tangentImpulse = impulseRatio * cp.tangentImpulse;
        ccp.localPoint.x = cp.localPoint.x;
        ccp.localPoint.y = cp.localPoint.y;

        ccp.rA.x = worldManifold.points[j].x - bodyA.sweep.center.x;
        ccp.rA.y = worldManifold.points[j].y - bodyA.sweep.center.y;

        ccp.rB.x = worldManifold.points[j].x - bodyB.sweep.center.x;
        ccp.rB.y = worldManifold.points[j].y - bodyB.sweep.center.y;
        num rnA = ccp.rA.x * cc.normal.y - ccp.rA.y * cc.normal.x;
        num rnB = ccp.rB.x * cc.normal.y - ccp.rB.y * cc.normal.x;
        rnA *= rnA;
        rnB *= rnB;

        num kNormal = bodyA.invMass + bodyB.invMass + bodyA.invInertia *
            rnA + bodyB.invInertia * rnB;

        assert(kNormal > Settings.EPSILON);
        ccp.normalMass = 1.0 / kNormal;

        tangent.x = 1.0 * cc.normal.y;
        tangent.y = -1.0 * cc.normal.x;

        num rtA = ccp.rA.x * tangent.y - ccp.rA.y * tangent.x;
        num rtB = ccp.rB.x * tangent.y - ccp.rB.y * tangent.x;
        rtA *= rtA;
        rtB *= rtB;

        num kTangent = bodyA.invMass + bodyB.invMass + bodyA.invInertia * rtA
            + bodyB.invInertia * rtB;

        assert(kTangent > Settings.EPSILON);
        ccp.tangentMass = 1.0 /  kTangent;

        // Setup a velocity bias for restitution.
        ccp.velocityBias = 0.0;
        temp2.x = -wA * ccp.rA.y;
        temp2.y = wA * ccp.rA.x;
        temp1.x = -wB * ccp.rB.y + vB.x - vA.x - temp2.x;
        temp1.y = wB * ccp.rB.x + vB.y - vA.y - temp2.y;

        vec2 a = cc.normal;

        num vRel = a.x * temp1.x + a.y * temp1.y;

        if (vRel < -Settings.VELOCITY_THRESHOLD){
          ccp.velocityBias = -restitution * vRel;
        }
      }

      // If we have two points, then prepare the block solver.
      if (cc.pointCount == 2){
        ContactConstraintPoint ccp1 = cc.points[0];
        ContactConstraintPoint ccp2 = cc.points[1];

        num invMassA = bodyA.invMass;
        num invIA = bodyA.invInertia;
        num invMassB = bodyB.invMass;
        num invIB = bodyB.invInertia;

        num rn1A = cross(ccp1.rA, cc.normal);
        num rn1B = cross(ccp1.rB, cc.normal);
        num rn2A = cross(ccp2.rA, cc.normal);
        num rn2B = cross(ccp2.rB, cc.normal);

        num k11 = invMassA + invMassB + invIA * rn1A * rn1A + invIB * rn1B
            * rn1B;
        num k22 = invMassA + invMassB + invIA * rn2A * rn2A + invIB * rn2B
            * rn2B;
        num k12 = invMassA + invMassB + invIA * rn1A * rn2A + invIB * rn1B
            * rn2B;

        // Ensure a reasonable condition number.
        if (k11 * k11 < K_MAX_CONDITION_NUMBER * (k11 * k22 - k12 * k12)) {
          // K is safe to invert.
          cc.K.col0.x = k11;
          cc.K.col0.y = k12;
          cc.K.col1.x = k12;
          cc.K.col1.y = k22;
          cc.normalMass.col0.x = cc.K.col0.x;
          cc.normalMass.col0.y = cc.K.col0.y;
          cc.normalMass.col1.x = cc.K.col1.x;
          cc.normalMass.col1.y = cc.K.col1.y;
          cc.normalMass.invert();
        } else{
          // The constraints are redundant, just use one.
          cc.pointCount = 1;
        }
      }
    }
  }

  void warmStart(){
    // Warm start.
    for (int i = 0; i < constraintCount; ++i){
      ContactConstraint c = constraints[i];

      final Body bodyA = c.bodyA;
      final Body bodyB = c.bodyB;
      final num invMassA = bodyA.invMass;
      final num invIA = bodyA.invInertia;
      final num invMassB = bodyB.invMass;
      final num invIB = bodyB.invInertia;
      final vec2 normal = c.normal;
      cross(normal, 1, tangent);

      for (int j = 0; j < c.pointCount; ++j){
        ContactConstraintPoint ccp = c.points[j];

        num Px = ccp.normalImpulse * normal.x + ccp.tangentImpulse *
            tangent.x;
        num Py = ccp.normalImpulse * normal.y + ccp.tangentImpulse
            * tangent.y;

        bodyA.angularVelocity -= invIA * (ccp.rA.x * Py - ccp.rA.y * Px);
        bodyA.linearVelocity.x -= Px * invMassA;
        bodyA.linearVelocity.y -= Py * invMassA;

        bodyB.angularVelocity += invIB * (ccp.rB.x * Py - ccp.rB.y * Px);
        bodyB.linearVelocity.x += Px * invMassB;
        bodyB.linearVelocity.y += Py * invMassB;
      }
    }
  }

  void solveVelocityConstraints(){
    for (int i = 0; i < constraintCount; ++i){
      final ContactConstraint c = constraints[i];
      final Body bodyA = c.bodyA;
      final Body bodyB = c.bodyB;
      num wA = bodyA.angularVelocity;
      num wB = bodyB.angularVelocity;
      final vec2 vA = bodyA.linearVelocity;
      final vec2 vB = bodyB.linearVelocity;
      final num invMassA = bodyA.invMass;
      final num invIA = bodyA.invInertia;
      final num invMassB = bodyB.invMass;
      final num invIB = bodyB.invInertia;
      tangent.x = 1.0 * c.normal.y;
      tangent.y = -1.0 * c.normal.x;
      final num friction = c.friction;

      assert(c.pointCount == 1 || c.pointCount == 2);

      // Solve tangent constraints
      for (int j = 0; j < c.pointCount; ++j){
        ContactConstraintPoint ccp = c.points[j];
        vec2 a = ccp.rA;

        dv.x = -wB * ccp.rB.y + vB.x - vA.x + wA * a.y;
        dv.y = wB * ccp.rB.x + vB.y - vA.y - wA * a.x;

        // Compute tangent force
        num vt = dv.x * tangent.x + dv.y * tangent.y;
        num lambda = ccp.tangentMass * (-vt);

        // Clamp the accumulated force
        num maxFriction = friction * ccp.normalImpulse;
        num newImpulse = clamp(ccp.tangentImpulse + lambda,
                               -maxFriction, maxFriction);
        lambda = newImpulse - ccp.tangentImpulse;

        // Apply contact impulse
        num Px = tangent.x * lambda;
        num Py = tangent.y * lambda;

        //vA -= invMassA * P;
        vA.x -= Px * invMassA;
        vA.y -= Py * invMassA;
        wA -= invIA * (ccp.rA.x * Py - ccp.rA.y * Px);

        //vB += invMassB * P;
        vB.x += Px * invMassB;
        vB.y += Py * invMassB;
        wB += invIB * (ccp.rB.x * Py - ccp.rB.y * Px);

        ccp.tangentImpulse = newImpulse;
      }

      // Solve normal constraints
      if (c.pointCount == 1){
        ContactConstraintPoint ccp = c.points[0];
        vec2 a1 = ccp.rA;

        dv.x = -wB * ccp.rB.y + vB.x - vA.x + wA * a1.y;
        dv.y = wB * ccp.rB.x + vB.y - vA.y - wA * a1.x;
        vec2 b = c.normal;

        // Compute normal impulse
        num vn = dv.x * b.x + dv.y * b.y;
        num lambda = -ccp.normalMass * (vn - ccp.velocityBias);

        // Clamp the accumulated impulse
        num a = ccp.normalImpulse + lambda;
        num newImpulse = (a > 0.0 ? a : 0.0);
        lambda = newImpulse - ccp.normalImpulse;

        // Apply contact impulse
        num Px = c.normal.x * lambda;
        num Py = c.normal.y * lambda;

        //vA -= invMassA * P;
        vA.x -= Px * invMassA;
        vA.y -= Py * invMassA;
        wA -= invIA * (ccp.rA.x * Py - ccp.rA.y * Px);

        //vB += invMassB * P;
        vB.x += Px * invMassB;
        vB.y += Py * invMassB;
        wB += invIB * (ccp.rB.x * Py - ccp.rB.y * Px);

        ccp.normalImpulse = newImpulse;
      } else {
        ContactConstraintPoint cp1 = c.points[0];
        ContactConstraintPoint cp2 = c.points[1];
        vec2 a = new vec2(cp1.normalImpulse, cp2.normalImpulse);

        assert(a.x >= 0.0 && a.y >= 0.0);
        // Relative velocity at contact
        //vec2 dv1 = vB + Cross(wB, cp1.rB) - vA - Cross(wA, cp1.rA);
        dv1.x = -wB * cp1.rB.y + vB.x - vA.x + wA * cp1.rA.y;
        dv1.y = wB * cp1.rB.x + vB.y - vA.y - wA * cp1.rA.x;

        //vec2 dv2 = vB + Cross(wB, cp2.rB) - vA - Cross(wA, cp2.rA);
        dv2.x = -wB * cp2.rB.y + vB.x - vA.x + wA * cp2.rA.y;
        dv2.y = wB * cp2.rB.x + vB.y - vA.y - wA * cp2.rA.x;

        // Compute normal velocity
        num vn1 = dv1.x * c.normal.x + dv1.y * c.normal.y;
        num vn2 = dv2.x * c.normal.x + dv2.y * c.normal.y;

        vec2 b = new vec2(vn1 - cp1.velocityBias, vn2 - cp2.velocityBias);
        temp2.x = c.K.col0.x * a.x + c.K.col1.x * a.y;
        temp2.y = c.K.col0.y * a.x + c.K.col1.y * a.y;
        b.x -= temp2.x;
        b.y -= temp2.y;

        while (true) {
          c.normalMass.transformed(b, x);
          x.negate();

          if (x.x >= 0.0 && x.y >= 0.0){
            // Resubstitute for the incremental impulse
            //vec2 d = x - a;
            d.copyFrom(x).sub(a);

            // Apply incremental impulse
            // vec2 P1 = d.x * normal;
            // vec2 P2 = d.y * normal;
            P1.copyFrom(c.normal).scale(d.x);
            P2.copyFrom(c.normal).scale(d.y);

            temp1.copyFrom(P1).add(P2);
            temp2.copyFrom(temp1).scale(invMassA);
            vA.sub(temp2);
            temp2.copyFrom(temp1).scale(invMassB);
            vB.add(temp2);

            wA -= invIA * (cross(cp1.rA, P1) + cross(cp2.rA, P2));
            wB += invIB * (cross(cp1.rB, P1) + cross(cp2.rB, P2));

            // Accumulate
            cp1.normalImpulse = x.x;
            cp2.normalImpulse = x.y;

            break;
          }

          x.x = - cp1.normalMass * b.x;
          x.y = 0.0;
          vn1 = 0.0;
          vn2 = c.K.col0.y * x.x + b.y;

          if (x.x >= 0.0 && vn2 >= 0.0) {
            // Resubstitute for the incremental impulse
            d.copyFrom(x).sub(a);

            // Apply incremental impulse
            P1.copyFrom(c.normal).scale(d.x);
            P2.copyFrom(c.normal).scale(d.y);

            temp1.copyFrom(P1).add(P2);
            temp2.copyFrom(temp1).scale(invMassA);
            vA.sub(temp2);
            temp2.copyFrom(temp1).scale(invMassB);
            vB.add(temp2);

            wA -= invIA * (cross(cp1.rA, P1) + cross(cp2.rA, P2));
            wB += invIB * (cross(cp1.rB, P1) + cross(cp2.rB, P2));

            // Accumulate
            cp1.normalImpulse = x.x;
            cp2.normalImpulse = x.y;

            break;
          }

          x.x = 0.0;
          x.y = - cp2.normalMass * b.y;
          vn1 = c.K.col1.x * x.y + b.x;
          vn2 = 0.0;

          if (x.y >= 0.0 && vn1 >= 0.0) {
            // Resubstitute for the incremental impulse
            d.copyFrom(x).sub(a);

            // Apply incremental impulse
            P1.copyFrom(c.normal).scale(d.x);
            P2.copyFrom(c.normal).scale(d.y);

            temp1.copyFrom(P1).add(P2);
            temp2.copyFrom(temp1).scale(invMassA);
            vA.sub(temp2);
            temp2.copyFrom(temp1).scale(invMassB);
            vB.add(temp2);

            wA -= invIA * (cross(cp1.rA, P1) + cross(cp2.rA, P2));
            wB += invIB * (cross(cp1.rB, P1) + cross(cp2.rB, P2));

            // Accumulate
            cp1.normalImpulse = x.x;
            cp2.normalImpulse = x.y;

            break;
          }

          x.x = 0.0;
          x.y = 0.0;
          vn1 = b.x;
          vn2 = b.y;

          if (vn1 >= 0.0 && vn2 >= 0.0 ) {
            // Resubstitute for the incremental impulse
            d.copyFrom(x).sub(a);

            // Apply incremental impulse
            P1.copyFrom(c.normal).scale(d.x);
            P2.copyFrom(c.normal).scale(d.y);

            temp1.copyFrom(P1).add(P2);
            temp2.copyFrom(temp1).scale(invMassA);
            vA.sub(temp2);
            temp2.copyFrom(temp1).scale(invMassB);
            vB.add(temp2);

            wA -= invIA * (cross(cp1.rA, P1) + cross(cp2.rA, P2));
            wB += invIB * (cross(cp1.rB, P1) + cross(cp2.rB, P2));

            // Accumulate
            cp1.normalImpulse = x.x;
            cp2.normalImpulse = x.y;

            break;
          }

          // No solution, give up. This is hit sometimes,
          // but it doesn't seem to matter.
          break;
        }
      }

      bodyA.linearVelocity.copyFrom(vA);
      bodyA.angularVelocity = wA;
      bodyB.linearVelocity.copyFrom(vB);
      bodyB.angularVelocity = wB;
    }
  }

  void storeImpulses(){
    for( int i=0; i<constraintCount; i++){
      ContactConstraint c = constraints[i];
      Manifold m = c.manifold;

      for(int j=0; j< c.pointCount; j++){
        m.points[j].normalImpulse = c.points[j].normalImpulse;
        m.points[j].tangentImpulse = c.points[j].tangentImpulse;
      }
    }
  }

  /**
   * Sequential solver.
   */
  bool solvePositionConstraints(num baumgarte){
    num minSeparation = 0.0;

    for (int i = 0; i < constraintCount; ++i){
      final ContactConstraint c = constraints[i];
      final Body bodyA = c.bodyA;
      final Body bodyB = c.bodyB;

      final num invMassA = bodyA.mass * bodyA.invMass;
      final num invIA = bodyA.mass * bodyA.invInertia;
      final num invMassB = bodyB.mass * bodyB.invMass;
      final num invIB = bodyB.mass * bodyB.invInertia;

      // Solve normal constraints
      for (int j = 0; j < c.pointCount; ++j){
        PositionSolverManifold psm = psolver;
        psm.initialize(c, j);
        vec2 normal = psm.normal;

        vec2 point = psm.point;
        num separation = psm.separation;

        rA.copyFrom(point).sub(bodyA.sweep.center);
        rB.copyFrom(point).sub(bodyB.sweep.center);

        // Track max constraint error.
        minSeparation = math.min(minSeparation, separation);

        // Prevent large corrections and allow slop.
        num C = clamp(baumgarte * (separation + Settings.LINEAR_SLOP),
                      -Settings.MAX_LINEAR_CORRECTION, 0.0);

        // Compute the effective mass.
        num rnA = cross(rA, normal);
        num rnB = cross(rB, normal);
        num K = invMassA + invMassB + invIA * rnA * rnA + invIB * rnB * rnB;

        // Compute normal impulse
        num impulse = K > 0.0 ? - C / K : 0.0;

        P.copyFrom(normal).scale(impulse);

        temp1.copyFrom(P).scale(invMassA);
        bodyA.sweep.center.sub(temp1);;
        bodyA.sweep.angle -= invIA * cross(rA, P);
        bodyA.synchronizeTransform();

        temp1.copyFrom(P).scale(invMassB);
        bodyB.sweep.center.add(temp1);
        bodyB.sweep.angle += invIB * cross(rB, P);
        bodyB.synchronizeTransform();
      }
    }

    // We can't expect minSpeparation >= -LINEAR_SLOP because we don't
    // push the separation above -LINEAR_SLOP.
    return minSeparation >= -1.5 * Settings.LINEAR_SLOP;
  }
}

class PositionSolverManifold {
  vec2 normal;
  vec2 point;
  num separation;

  /** Pooling */
  vec2 pointA;
  vec2 pointB;
  vec2 temp;
  vec2 planePoint;
  vec2 clipPoint;

  PositionSolverManifold() :
    normal = new vec2.zero(),
    point = new vec2.zero(),
    separation = 0,

    // Initialize pool variables.
    pointA = new vec2.zero(),
    pointB = new vec2.zero(),
    temp = new vec2.zero(),
    planePoint = new vec2.zero(),
    clipPoint = new vec2.zero();

  void initialize(ContactConstraint cc, int index) {
    assert(cc.pointCount > 0);

    switch (cc.type) {
      case ManifoldType.CIRCLES:
        cc.bodyA.getWorldPointToOut(cc.localPoint, pointA);
        cc.bodyB.getWorldPointToOut(cc.points[0].localPoint, pointB);
        if (distance2(pointA, pointB) > Settings.EPSILON * Settings.EPSILON) {
          normal.copyFrom(pointB).sub(pointA);
          normal.normalize();
        } else {
          normal.splat(0.0);
        }

        point.copyFrom(pointA).add(pointB).scale(.5);
        temp.copyFrom(pointB).sub(pointA);
        separation = dot(temp, normal) - cc.radius;
        break;

      case ManifoldType.FACE_A:
        cc.bodyA.getWorldVectorToOut(cc.localNormal, normal);
        cc.bodyA.getWorldPointToOut(cc.localPoint, planePoint);

        cc.bodyB.getWorldPointToOut(cc.points[index].localPoint,
            clipPoint);
        temp.copyFrom(clipPoint).sub(planePoint);
        separation = dot(temp, normal) - cc.radius;
        point.copyFrom(clipPoint);
        break;

      case ManifoldType.FACE_B:
        cc.bodyB.getWorldVectorToOut(cc.localNormal, normal);
        cc.bodyB.getWorldPointToOut(cc.localPoint, planePoint);

        cc.bodyA.getWorldPointToOut(cc.points[index].localPoint, clipPoint);
        temp.copyFrom(clipPoint).sub(planePoint);
        separation = dot(temp, normal) - cc.radius;
        point.copyFrom(clipPoint);

        // Ensure normal points from A to B
        normal.negate();
        break;
    }
  }
}
