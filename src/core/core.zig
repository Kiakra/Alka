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

pub const c = @import("c.zig");
pub const gl = @import("gl.zig");
pub const fs = @import("fs.zig");
pub const utf8 = @import("utf8.zig");
pub const utils = @import("utils.zig");
pub const audio = @import("audio/audio.zig");
pub const ecs = @import("ecs.zig");
pub const math = @import("math/math.zig");
pub const glfw = @import("glfw.zig");
pub const input = @import("input.zig");
pub const log = @import("log.zig");
pub const renderer = @import("renderer.zig");
pub const window = @import("window.zig");

pub const Error = gl.Error || fs.Error || utils.Error || audio.Error || ecs.Error || glfw.GLFWError || input.Error || renderer.Error || window.Error;
