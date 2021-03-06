//Copyright © 2020-2021 Mehmet Kaan Uluç <kaanuluc@protonmail.com>
//
//This software is provided 'as-is', without any express or implied
//warranty. In no event will the authors be held liable for any damages
//arising from the use of this software.
//
//Permission is granted to anyone to use this software for any purpose,
//including commercial applications, and to alter it and redistribute it
//freely, subject to the following restrictions:
//
//1. The origin of this software must not be misrepresented; you must not
//   claim that you wrote the original software. If you use this software
//   in a product, an acknowledgment in the product documentation would
//   be appreciated but is not required.
//
//2. Altered source versions must be plainly marked as such, and must not
//   be misrepresented as being the original software.
//
//3. This notice may not be removed or altered from any source
//   distribution.

pub usingnamespace @import("common.zig");
const p = @import("common.zig");
pub const vec2 = @import("vec2.zig");
pub const vec3 = @import("vec3.zig");
pub const mat4x4 = @import("mat4x4.zig");

pub const Mat4x4f = mat4x4.Generic(f32);
pub const Vec2f = vec2.Generic(f32);
pub const Vec3f = vec3.Generic(f32);

/// Helper type for using MVP's
pub const ModelMatrix = struct {
    model: Mat4x4f = Mat4x4f.identity(),
    trans: Mat4x4f = Mat4x4f.identity(),
    rot: Mat4x4f = Mat4x4f.identity(),
    sc: Mat4x4f = Mat4x4f.identity(),

    /// Apply the changes were made
    pub fn update(self: *ModelMatrix) void {
        self.model = Mat4x4f.mul(self.sc, Mat4x4f.mul(self.trans, self.rot));
    }

    /// Translate the matrix
    pub fn translate(self: *ModelMatrix, x: f32, y: f32, z: f32) void {
        self.trans = Mat4x4f.translate(x, y, z);
        self.update();
    }

    /// Rotate the matrix
    pub fn rotate(self: *ModelMatrix, x: f32, y: f32, z: f32, angle: f32) void {
        self.rot = Mat4x4f.rotate(x, y, z, angle);
        self.update();
    }

    /// Scale the matrix
    pub fn scale(self: *ModelMatrix, x: f32, y: f32, z: f32) void {
        self.sc = Mat4x4f.scale(x, y, z);
        self.update();
    }
};

pub const Rectangle = struct {
    position: Vec2f = .{ .x = 0, .y = 0 },
    size: Vec2f = .{ .x = 0, .y = 0 },

    /// Get the originated position of the rectangle
    pub fn getOriginated(self: Rectangle) Vec2f {
        return .{
            .x = self.position.x + (self.size.x * 0.5),
            .y = self.position.y + (self.size.y * 0.5),
        };
    }

    /// Get origin of the rectangle
    pub fn getOrigin(self: Rectangle) Vec2f {
        return .{
            .x = self.size.x * 0.5,
            .y = self.size.y * 0.5,
        };
    }

    /// AABB collision detection
    /// between to rectangles
    pub fn aabb(self: Rectangle, other: Rectangle) bool {
        return p.aabb(self.position.x, self.position.y, self.size.x, self.size.y, other.position.x, other.position.y, other.size.x, other.size.y);
    }

    /// AABB collision detection
    /// between to rectangles
    pub fn aabbMeeting(self: Rectangle, other: Rectangle, meeting: Vec2f) bool {
        return p.aabbMeeting(meeting.x, meeting.y, self.position.x, self.position.y, self.size.x, self.size.y, other.position.x, other.position.y, other.size.x, other.size.y);
    }
};

/// Transform 2D
pub const Transform2D = struct {
    position: Vec2f = undefined,
    size: Vec2f = undefined,
    origin: Vec2f = undefined,
    /// in degrees
    rotation: f32 = undefined,

    /// Get the originated position
    pub fn getOriginated(self: Transform2D) Vec2f {
        return Vec2f{
            .x = self.position.x - self.origin.x,
            .y = self.position.y - self.origin.y,
        };
    }

    pub fn getRectangle(self: Transform2D) Rectangle {
        return Rectangle{ .position = self.getOriginated(), .size = self.size };
    }

    pub fn getRectangleNoOrigin(self: Transform2D) Rectangle {
        return Rectangle{ .position = self.position, .size = self.size };
    }

    /// AABB collision detection
    /// between to transform(rotation does not count)
    pub fn aabb(self: Transform2D, other: Transform2D) bool {
        return self.getRectangle().aabb(other.getRectangle());
    }

    /// AABB collision detection
    /// between to transform(rotation does not count)
    /// origin does not count  
    pub fn aabbNoOrigin(self: Transform2D, other: Transform2D) bool {
        return Rectangle.aabb(self.getRectangleNoOrigin(), other.getRectangleNoOrigin());
    }

    /// AABB collision detection
    /// between to transform(rotation does not count)
    pub fn aabbMeeting(self: Transform2D, other: Transform2D, meeting: Vec2f) bool {
        return self.getRectangle().aabbMeeting(other.getRectangle(), meeting);
    }

    /// AABB collision detection
    /// between to transform(rotation does not count)
    /// origin does not count  
    pub fn aabbMeetingNoOrigin(self: Transform2D, other: Transform2D, meeting: Vec2f) bool {
        return Rectangle.aabbMeeting(self.getRectangleNoOrigin(), other.getRectangleNoOrigin(), meeting);
    }
};

/// 2D Camera
pub const Camera2D = struct {
    position: Vec2f = Vec2f{ .x = 0, .y = 0 },
    offset: Vec2f = Vec2f{ .x = 0, .y = 0 },
    zoom: Vec2f = Vec2f{ .x = 1, .y = 1 },

    /// In radians
    rotation: f32 = 0,

    ortho: Mat4x4f = comptime Mat4x4f.identity(),
    view: Mat4x4f = comptime Mat4x4f.identity(),

    /// Returns the camera matrix
    pub fn matrix(self: Camera2D) Mat4x4f {
        const origin = Mat4x4f.translate(self.position.x, self.position.y, 0);
        const rot = Mat4x4f.rotate(0, 0, 1, self.rotation);
        const scale = Mat4x4f.scale(self.zoom.x, self.zoom.y, 0);
        const offset = Mat4x4f.translate(self.offset.x, self.offset.y, 0);

        return Mat4x4f.mul(Mat4x4f.mul(origin, Mat4x4f.mul(scale, rot)), offset);
    }

    /// Attaches the camera
    pub fn attach(self: *Camera2D) void {
        self.view = Mat4x4f.mul(self.matrix(), self.ortho);
    }

    /// Detaches the camera
    pub fn detach(self: *Camera2D) void {
        self.view = Mat4x4f.identity();
    }

    /// Returns the screen space position for a 2d camera world space position
    pub fn worldToScreen(self: Camera2D, position: Vec2f) Vec2f {
        const m = self.matrix();
        const v = Vec3f.transform(Vec3f{ .x = position.x, .y = position.y, .z = 0.0 }, m);
        return .{ .x = v.x, .y = v.y };
    }

    /// Returns the world space position for a 2d camera screen space position
    pub fn screenToWorld(self: Camera2D, position: Vec2f) Vec2f {
        const m = Mat4x4f.invert(self.matrix());
        const v = Vec3f.transform(Vec3f{ .x = position.x, .y = position.y, .z = 0.0 }, m);
        return .{ .x = v.x, .y = v.y };
    }
};
