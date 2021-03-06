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

const std = @import("std");
const pr = @import("private.zig");

/// opengl library
pub const gl = @import("core/gl.zig");
/// file system library
pub const fs = @import("core/fs.zig");
/// utf8 library
pub const utf8 = @import("core/utf8.zig");
/// utils library
pub const utils = @import("core/utils.zig");
/// audio library
pub const audio = @import("core/audio/audio.zig");
/// ecs library
pub const ecs = @import("core/ecs.zig");
/// math library
pub const math = @import("core/math/math.zig");
/// glfw library
pub const glfw = @import("core/glfw.zig");
/// input library
pub const input = @import("core/input.zig");
/// std.log implementation
pub const log = @import("core/log.zig");
/// primitive renderer library
pub const renderer = @import("core/renderer.zig");
/// single window management library
pub const window = @import("core/window.zig");
/// GUI library
pub const gui = @import("gui.zig");

const m = math;

const alog = std.log.scoped(.alka);

/// Error set
pub const Error = pr.Error;

pub const max_quad = pr.max_quad;
pub const Vertex2D = pr.Vertex2D;
pub const Batch2DQuad = pr.Batch2DQuad;
pub const Colour = pr.Colour;

// error: inferring error set of return type valid only for function definitions
// var pupdateproc: ?fn (deltatime: f32) !void = null;
//                                       ^
pub const Callbacks = pr.Callbacks;
pub const Batch = pr.Batch;
pub const AssetManager = pr.AssetManager;

var pengineready: bool = false;
var p: *pr.Private = undefined;

/// Initializes the engine
pub fn init(alloc: *std.mem.Allocator, callbacks: Callbacks, width: i32, height: i32, title: []const u8, fpslimit: u32, resizable: bool) Error!void {
    if (pengineready) return Error.EngineIsInitialized;

    p = try alloc.create(pr.Private);
    p.* = pr.Private{};
    pr.setstruct(p);

    p.alloc = alloc;

    try glfw.init();
    try glfw.windowHint(glfw.WindowHint.Resizable, if (resizable) 1 else 0);
    gl.setProfile();

    p.input.clearBindings();

    p.win.size.width = width;
    p.win.size.height = height;
    p.win.minsize = if (resizable) .{ .width = 100, .height = 100 } else p.win.size;
    p.win.maxsize = if (resizable) .{ .width = 10000, .height = 10000 } else p.win.size;
    p.win.title = title;
    p.win.callbacks.close = pr.closeCallback;
    p.win.callbacks.resize = pr.resizeCallback;
    p.win.callbacks.keyinp = pr.keyboardCallback;
    p.win.callbacks.mouseinp = pr.mousebuttonCallback;
    p.win.callbacks.mousepos = pr.mousePosCallback;
    setCallbacks(callbacks);

    if (fpslimit != 0) p.targetfps = 1.0 / @intToFloat(f32, fpslimit);

    try p.win.create(false, true);
    try glfw.makeContextCurrent(p.win.handle);
    gl.init();
    gl.setBlending(true);

    if (fpslimit == 0) {
        try glfw.swapInterval(1);
    } else {
        try glfw.swapInterval(0);
    }

    //p.layers = try utils.UniqueList(pr.Private.Layer).init(p.alloc, 1);

    p.defaults.cam2d = m.Camera2D{};
    p.defaults.cam2d.ortho = m.Mat4x4f.ortho(0, @intToFloat(f32, p.win.size.width), @intToFloat(f32, p.win.size.height), 0, -1, 1);

    p.assetmanager.alloc = p.alloc;
    try p.assetmanager.init();

    try p.assetmanager.loadShader(pr.embed.default_shader.id, pr.embed.default_shader.vertex_shader, pr.embed.default_shader.fragment_shader);

    {
        var c = [_]renderer.UColour{
            .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        };
        const wtexture = renderer.Texture.createFromColour(&c, 1, 1);
        try p.assetmanager.loadTexturePro(pr.embed.white_texture_id, wtexture);
    }

    popCamera2D();

    pengineready = true;
    alog.info("fully initialized!", .{});
}

/// Deinitializes the engine
pub fn deinit() Error!void {
    if (!pengineready) return Error.EngineIsNotInitialized;
    // Destroy all the batchs
    if (p.batch_counter > 0) {
        var i: usize = 0;
        while (i < p.batch_counter) : (i += 1) {
            if (p.batchs[i].state != pr.PrivateBatchState.unknown) {
                pr.destroyPrivateBatch(i);
                alog.notice("batch(id: {}) destroyed!", .{i});
            }
        }
        p.alloc.free(p.batchs);
    }

    //p.layers.deinit();

    p.assetmanager.deinit();

    try p.win.destroy();
    gl.deinit();

    try glfw.terminate();

    p.alloc.destroy(p);

    pengineready = false;
    alog.info("fully deinitialized!", .{});
}

/// Opens the window
pub fn open() Error!void {
    if (!pengineready) return Error.EngineIsNotInitialized;
    p.winrun = true;
}

/// Closes the window
pub fn close() Error!void {
    if (!pengineready) return Error.EngineIsNotInitialized;
    p.winrun = false;
}

/// Updates the engine
/// can return `anyerror`
pub fn update() !void {
    if (!pengineready) return Error.EngineIsNotInitialized;

    // Source: https://gafferongames.com/post/fix_your_timestep/
    var last: f64 = try glfw.getTime();
    var accumulator: f64 = 0;
    var dt: f64 = 0.01;

    while (p.winrun) {
        if (p.callbacks.update) |fun| {
            try fun(@floatCast(f32, p.frametime.delta));
        }

        try p.frametime.start();
        var ftime: f64 = p.frametime.current - last;
        if (ftime > 0.25) {
            ftime = 0.25;
        }
        last = p.frametime.current;
        accumulator += ftime;

        if (p.callbacks.fixed) |fun| {
            while (accumulator >= dt) : (accumulator -= dt) {
                try fun(@floatCast(f32, dt));
            }
        }
        p.input.handle();

        gl.clearBuffers(gl.BufferBit.colour);
        if (p.callbacks.draw) |fun| {
            try fun();
        }

        popCamera2D();

        // Render all the batches
        try renderAllBatchs();

        try glfw.swapBuffers(p.win.handle);
        try glfw.pollEvents();

        // Clean all the batches
        cleanAllBatchs();

        try p.frametime.stop();
        try p.frametime.sleep(p.targetfps);

        p.fps = p.fps.calculate(p.frametime);
    }
    if (p.win.callbacks.close != null)
        pr.closeCallback(p.win.handle);
}

/// Returns the p.alloc
pub fn getAllocator() *std.mem.Allocator {
    return p.alloc;
}

/// Returns the fps
pub fn getFps() u32 {
    return p.fps.fps;
}

/// Returns the debug information
/// Warning: you have to manually free the buffer
pub fn getDebug() ![]u8 {
    if (!pengineready) return Error.EngineIsNotInitialized;
    var buffer: []u8 = try p.alloc.alloc(u8, 255);

    buffer = try std.fmt.bufPrintZ(buffer, "update: {d:.4}\tdraw: {d:.4}\tdelta: {d:.4}\tfps: {}", .{ p.frametime.update, p.frametime.draw, p.frametime.delta, p.fps.fps });
    return buffer;
}

/// Returns the window
pub fn getWindow() *window.Info {
    return &p.win;
}

/// Returns the input
pub fn getInput() *input.Info {
    return &p.input;
}

/// Returns the mouse pos
pub fn getMousePosition() m.Vec2f {
    return p.mousep;
}

/// Returns the ptr to assetmanager
pub fn getAssetManager() *AssetManager {
    return &p.assetmanager;
}

/// Returns the ptr to default camera2d
pub fn getCamera2DPtr() *m.Camera2D {
    return &p.defaults.cam2d;
}

/// Returns the read-only default camera2d
pub fn getCamera2D() m.Camera2D {
    return p.defaults.cam2d;
}

/// Returns the ptr to pushed camera2d
pub fn getCamera2DPushedPtr() *m.Camera2D {
    return &p.force_camera2d;
}

/// Returns the read-only pushed camera2d
pub fn getCamera2DPushed() m.Camera2D {
    return p.force_camera2d;
}

/// Returns the requested batch with given attribs
/// Note: updating every frame is the way to go
pub fn getBatch(mode: gl.DrawMode, sh_id: u64, texture_id: u64) Error!Batch {
    const sh = try p.assetmanager.getShader(sh_id);
    const texture = try p.assetmanager.getTexture(texture_id);

    var i: usize = 0;
    while (i < p.batch_counter) : (i += 1) {
        if (p.batchs[i].state == pr.PrivateBatchState.active and p.batchs[i].mode == mode and p.batchs[i].shader == sh and p.batchs[i].texture.id == texture.id) return Batch{
            .id = @intCast(i32, i),
            .mode = p.batchs[i].mode,
            .shader = p.batchs[i].shader,
            .texture = p.batchs[i].texture,
            .cam2d = &p.batchs[i].cam2d,
            .subcounter = &p.batchs[i].data.submission_counter,
        };
    }
    return Error.InvalidBatch;
}

/// Returns the requested batch with given attribs
/// Note: updating every frame is the way to go
/// usefull when using non-assetmanager loaded shaders and textures
pub fn getBatchNoID(mode: gl.DrawMode, sh: u32, texture: renderer.Texture) Error!Batch {
    var i: usize = 0;
    while (i < p.batch_counter) : (i += 1) {
        if (p.batchs[i].state == pr.PrivateBatchState.active and p.batchs[i].mode == mode and p.batchs[i].shader == sh and p.batchs[i].texture.id == texture.id) return Batch{
            .id = @intCast(i32, i),
            .mode = p.batchs[i].mode,
            .shader = p.batchs[i].shader,
            .texture = p.batchs[i].texture,
            .cam2d = &p.batchs[i].cam2d,
            .subcounter = &p.batchs[i].data.submission_counter,
        };
    }
    return Error.InvalidBatch;
}

/// Creates a batch with given attribs
/// Note: updating every frame is the way to go
pub fn createBatch(mode: gl.DrawMode, sh_id: u64, texture_id: u64) Error!Batch {
    const i = pr.findPrivateBatch() catch |err| {
        if (err == Error.FailedToFindPrivateBatch) {
            try pr.createPrivateBatch();
            return createBatch(mode, sh_id, texture_id);
        } else return err;
    };

    var b = &p.batchs[i];
    b.state = pr.PrivateBatchState.active;
    b.mode = mode;
    b.shader = try p.assetmanager.getShader(sh_id);
    b.texture = try p.assetmanager.getTexture(texture_id);
    b.cam2d = p.force_camera2d;

    return Batch{
        .id = @intCast(i32, i),
        .mode = b.mode,
        .shader = b.shader,
        .texture = b.texture,
        .cam2d = &b.cam2d,
        .subcounter = &b.data.submission_counter,
    };
}

/// Creates a batch with given attribs
/// Note: updating every frame is the way to go
/// usefull when using non-assetmanager loaded shaders and textures
pub fn createBatchNoID(mode: gl.DrawMode, sh: u32, texture: renderer.Texture) Error!Batch {
    const i = pr.findPrivateBatch() catch |err| {
        if (err == Error.FailedToFindPrivateBatch) {
            try pr.createPrivateBatch();
            return createBatchNoID(mode, sh, texture);
        } else return err;
    };

    var b = &p.batchs[i];
    b.state = pr.PrivateBatchState.active;
    b.mode = mode;
    b.shader = sh;
    b.texture = texture;
    b.cam2d = p.force_camera2d;

    return Batch{
        .id = @intCast(i32, i),
        .mode = b.mode,
        .shader = b.shader,
        .texture = b.texture,
        .cam2d = &b.cam2d,
        .subcounter = &b.data.submission_counter,
    };
}

/// Sets the batch drawfun
/// use this after `batch.drawfun = fun`
pub fn setBatchFun(batch: Batch) void {
    var b = &p.batchs[@intCast(usize, batch.id)];
    b.drawfun = batch.drawfun;
}

/// Sets the batch layer 
pub fn setBatchLayer(layer: i64) void {
    @compileError("This functionality does not implemented.");
}

/// Sets the callbacks
pub fn setCallbacks(calls: Callbacks) void {
    p.callbacks = calls;
}

/// Sets the background colour
pub fn setBackgroundColour(r: f32, g: f32, b: f32) void {
    gl.clearColour(r, g, b, 1);
}

/// Automatically resizes/strecthes the view/camera
/// Recommended to use after initializing the engine and `resize` callback
pub fn autoResize(virtualwidth: i32, virtualheight: i32, screenwidth: i32, screenheight: i32) void {
    var cam = &p.force_camera2d;

    const aspect: f32 = @intToFloat(f32, virtualwidth) / @intToFloat(f32, virtualheight);
    var width = screenwidth;
    var height = @floatToInt(i32, @intToFloat(f32, screenheight) / aspect + 0.5);

    if (height > screenheight) {
        height = screenheight;

        width = @floatToInt(i32, @intToFloat(f32, screenheight) * aspect + 0.5);
    }

    const vx = @divTrunc(screenwidth, 2) - @divTrunc(width, 2);
    const vy = @divTrunc(screenheight, 2) - @divTrunc(height, 2);

    const scalex = @intToFloat(f32, screenwidth) / @intToFloat(f32, virtualwidth);
    const scaley = @intToFloat(f32, screenheight) / @intToFloat(f32, virtualheight);

    gl.viewport(vx, vy, width, height);
    gl.ortho(0, @intToFloat(f32, screenwidth), @intToFloat(f32, screenheight), 0, -1, 1);

    cam.ortho = m.Mat4x4f.ortho(0, @intToFloat(f32, screenwidth), @intToFloat(f32, screenheight), 0, -1, 1);
    cam.zoom.x = scalex;
    cam.zoom.y = scaley;
}

/// Renders the given batch 
pub fn renderBatch(batch: Batch) Error!void {
    const i = @intCast(usize, batch.id);
    return pr.drawPrivateBatch(i);
}

/// Cleans the batch
pub fn cleanBatch(batch: Batch) void {
    const i = @intCast(usize, batch.id);
    return pr.cleanPrivateBatch(i);
}

/// Renders all the batchs 
pub fn renderAllBatchs() Error!void {
    var i: usize = 0;
    while (i < p.batch_counter) : (i += 1) {
        try pr.renderPrivateBatch(i);
    }
}

/// Cleans all the batchs 
pub fn cleanAllBatchs() void {
    var i: usize = 0;
    while (i < p.batch_counter) : (i += 1) {
        pr.cleanPrivateBatch(i);
    }
}

/// Pushes the given camera2D
pub fn pushCamera2D(cam: m.Camera2D) void {
    p.force_camera2d = cam;
}

/// Pops the camera2D
pub fn popCamera2D() void {
    p.force_camera2d = getCamera2D();
}

/// Forces to use the given shader
/// in draw calls
pub fn pushShader(sh: u64) Error!void {
    if (p.force_batch != null) return Error.CustomBatchInUse;
    p.force_shader = sh;
}

/// Pops the force use shader 
pub fn popShader() void {
    p.force_shader = null;
}

/// Forces to use the given batch
/// in draw calls
pub fn pushBatch(batch: Batch) Error!void {
    if (p.force_shader != null) return Error.CustomShaderInUse;
    p.force_batch = @intCast(usize, batch.id);
}

/// Pops the force use batch 
pub fn popBatch() void {
    p.force_batch = null;
}

/// Draws a pixel
/// Draw mode: points
pub fn drawPixel(pos: m.Vec2f, colour: Colour) Error!void {
    const i = try identifyBatchID(.points, pr.embed.default_shader.id, pr.embed.white_texture_id);

    const vx = [Batch2DQuad.max_vertex_count]Vertex2D{
        .{ .position = pos, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
    };

    p.batchs[i].data.submitDrawable(vx) catch |err| {
        if (err == Error.ObjectOverflow) {
            try pr.drawPrivateBatch(i);
            pr.cleanPrivateBatch(i);
            //alog.notice("batch(id: {}) flushed!", .{i});

            return p.batchs[i].data.submitDrawable(vx);
        } else return err;
    };
}

/// Draws a line
/// Draw mode: lines
pub fn drawLine(start: m.Vec2f, end: m.Vec2f, thickness: f32, colour: Colour) Error!void {
    const i = try identifyBatchID(.lines, pr.embed.default_shader.id, pr.embed.white_texture_id);

    const pos0 = m.Vec2f{ .x = start.x, .y = start.y };
    const pos1 = m.Vec2f{ .x = end.x, .y = end.y };
    const pos2 = m.Vec2f{ .x = start.x + thickness, .y = start.y + thickness };
    const pos3 = m.Vec2f{ .x = end.x + thickness, .y = end.y + thickness };

    const vx = [Batch2DQuad.max_vertex_count]Vertex2D{
        .{ .position = pos0, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos1, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos2, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos3, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
    };

    p.batchs[i].data.submitDrawable(vx) catch |err| {
        if (err == Error.ObjectOverflow) {
            try pr.drawPrivateBatch(i);
            pr.cleanPrivateBatch(i);
            //alog.notice("batch(id: {}) flushed!", .{i});

            return p.batchs[i].data.submitDrawable(vx);
        } else return err;
    };
}

/// Draws a circle lines, 16 segments by default
/// Draw mode: triangles
pub fn drawCircle(position: m.Vec2f, radius: f32, colour: Colour) Error!void {
    return drawCircleAdv(position, radius, 0, 360, 16, colour);
}

// Source: https://github.com/raysan5/raylib/blob/f1ed8be5d7e2d966d577a3fd28e53447a398b3b6/src/shapes.c#L209
/// Draws a circle
/// Draw mode: triangles
pub fn drawCircleAdv(center: m.Vec2f, radius: f32, segments: i32, startangle: i32, endangle: i32, colour: Colour) Error!void {
    const batch_id = try identifyBatchID(.triangles, pr.embed.default_shader.id, pr.embed.white_texture_id);

    const SMOOTH_CIRCLE_ERROR_RATE = comptime 0.5;

    var iradius = radius;
    var istartangle = startangle;
    var iendangle = endangle;
    var isegments = segments;

    if (iradius <= 0.0) iradius = 0.1; // Avoid div by zero
    // Function expects (endangle > startangle)
    if (iendangle < istartangle) {
        // Swap values
        const tmp = istartangle;
        istartangle = iendangle;
        iendangle = tmp;
    }

    if (isegments < 4) {
        // Calculate the maximum angle between segments based on the error rate (usually 0.5f)
        const th: f32 = std.math.acos(2 * std.math.pow(f32, 1 - SMOOTH_CIRCLE_ERROR_RATE / iradius, 2) - 1);
        isegments = @floatToInt(i32, (@intToFloat(f32, (iendangle - istartangle)) * @ceil(2 * m.PI / th) / 360));

        if (isegments <= 0) isegments = 4;
    }
    const steplen: f32 = @intToFloat(f32, iendangle - istartangle) / @intToFloat(f32, isegments);
    var angle: f32 = @intToFloat(f32, istartangle);

    // NOTE: Every QUAD actually represents two segments
    var i: i32 = 0;
    while (i < @divTrunc(isegments, 2)) : (i += 1) {
        const pos0 = m.Vec2f{ .x = center.x, .y = center.y };
        const pos1 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle)) * iradius,
        };
        const pos2 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle + steplen)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle + steplen)) * iradius,
        };
        const pos3 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle + steplen * 2)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle + steplen * 2)) * iradius,
        };

        angle += steplen * 2;

        const vx = [Batch2DQuad.max_vertex_count]Vertex2D{
            .{ .position = pos0, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
            .{ .position = pos1, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
            .{ .position = pos2, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
            .{ .position = pos3, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        };

        p.batchs[batch_id].data.submitDrawable(vx) catch |err| {
            if (err == Error.ObjectOverflow) {
                try pr.drawPrivateBatch(batch_id);
                pr.cleanPrivateBatch(batch_id);
                //alog.notice("batch(id: {}) flushed!", .{i});

                return p.batchs[batch_id].data.submitDrawable(vx);
            } else return err;
        };
    }
    // NOTE: In case number of segments is odd, we add one last piece to the cake
    if (@mod(isegments, 2) != 0) {
        const pos0 = m.Vec2f{ .x = center.x, .y = center.y };
        const pos1 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle)) * iradius,
        };
        const pos2 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle + steplen)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle + steplen)) * iradius,
        };
        const pos3 = m.Vec2f{ .x = center.x, .y = center.y };

        const vx = [Batch2DQuad.max_vertex_count]Vertex2D{
            .{ .position = pos0, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
            .{ .position = pos1, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
            .{ .position = pos2, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
            .{ .position = pos3, .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        };

        p.batchs[batch_id].data.submitDrawable(vx) catch |err| {
            if (err == Error.ObjectOverflow) {
                try pr.drawPrivateBatch(batch_id);
                pr.cleanPrivateBatch(batch_id);
                //alog.notice("batch(id: {}) flushed!", .{i});

                return p.batchs[batch_id].data.submitDrawable(vx);
            } else return err;
        };
    }
}

/// Draws a circle lines, 16 segments by default
/// Draw mode: lines
pub fn drawCircleLines(position: m.Vec2f, radius: f32, colour: Colour) Error!void {
    return drawCircleLinesAdv(position, radius, 16, 0, 360, colour);
}

// source: https://github.com/raysan5/raylib/blob/f1ed8be5d7e2d966d577a3fd28e53447a398b3b6/src/shapes.c#L298
/// Draws a circle lines
/// Draw mode: lines
pub fn drawCircleLinesAdv(center: m.Vec2f, radius: f32, segments: i32, startangle: i32, endangle: i32, colour: Colour) Error!void {
    const SMOOTH_CIRCLE_ERROR_RATE = comptime 0.5;

    var isegments: i32 = segments;

    var istartangle: i32 = startangle;
    var iendangle: i32 = endangle;
    var iradius = radius;

    if (iradius <= 0.0) iradius = 0.1; // Avoid div by zero

    // Function expects (endangle > startangle)
    if (iendangle < istartangle) {
        // Swap values
        const tmp = istartangle;
        istartangle = iendangle;
        iendangle = tmp;
    }

    if (isegments < 4) {
        // Calculate the maximum angle between segments based on the error rate (usually 0.5f)
        const th: f32 = std.math.acos(2 * std.math.pow(f32, 1 - SMOOTH_CIRCLE_ERROR_RATE / iradius, 2) - 1);
        isegments = @floatToInt(i32, (@intToFloat(f32, (iendangle - istartangle)) * @ceil(2 * m.PI / th) / 360));

        if (isegments <= 0) isegments = 4;
    }

    const steplen: f32 = @intToFloat(f32, iendangle - istartangle) / @intToFloat(f32, isegments);
    var angle: f32 = @intToFloat(f32, istartangle);

    // Hide the cap lines when the circle is full
    var showcaplines: bool = true;

    if (@mod(iendangle - istartangle, 360) == 0) {
        showcaplines = false;
    }

    if (showcaplines) {
        const pos0 = m.Vec2f{ .x = center.x, .y = center.y };
        const pos1 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle)) * iradius,
        };

        try drawLine(pos0, pos1, 1, colour);
    }

    var i: i32 = 0;
    while (i < isegments) : (i += 1) {
        const pos1 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle)) * iradius,
        };
        const pos2 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle + steplen)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle + steplen)) * iradius,
        };

        try drawLine(pos1, pos2, 1, colour);
        angle += steplen;
    }

    if (showcaplines) {
        const pos0 = m.Vec2f{ .x = center.x, .y = center.y };
        const pos1 = m.Vec2f{
            .x = center.x + @sin(m.deg2radf(angle)) * iradius,
            .y = center.y + @cos(m.deg2radf(angle)) * iradius,
        };

        try drawLine(pos0, pos1, 1, colour);
    }
}

/// Draws a basic rectangle
/// Draw mode: triangles
pub fn drawRectangle(rect: m.Rectangle, colour: Colour) Error!void {
    const i = try identifyBatchID(.triangles, pr.embed.default_shader.id, pr.embed.white_texture_id);

    const pos = createQuadPositions(rect);

    const vx = [Batch2DQuad.max_vertex_count]Vertex2D{
        .{ .position = pos[0], .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos[1], .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos[2], .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos[3], .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
    };

    p.batchs[i].data.submitDrawable(vx) catch |err| {
        if (err == Error.ObjectOverflow) {
            try pr.drawPrivateBatch(i);
            pr.cleanPrivateBatch(i);
            //alog.notice("batch(id: {}) flushed!", .{i});

            return p.batchs[i].data.submitDrawable(vx);
        } else return err;
    };
}

/// Draws a basic rectangle lines
/// Draw mode: lines
pub fn drawRectangleLines(rect: m.Rectangle, colour: Colour) Error!void {
    const pos = createQuadPositions(rect);

    try drawLine(pos[0], pos[1], 1, colour);
    try drawLine(pos[1], pos[2], 1, colour);
    try drawLine(pos[2], pos[3], 1, colour);
    try drawLine(pos[0], pos[3], 1, colour);
}

/// Draws a rectangle, angle should be in radians
/// Draw mode: triangles
pub fn drawRectangleAdv(rect: m.Rectangle, origin: m.Vec2f, angle: f32, colour: Colour) Error!void {
    const i = try identifyBatchID(.triangles, pr.embed.default_shader.id, pr.embed.white_texture_id);

    const pos = createQuadPositionsMVP(rect, origin, angle);

    const vx = [Batch2DQuad.max_vertex_count]Vertex2D{
        .{ .position = pos[0], .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos[1], .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos[2], .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
        .{ .position = pos[3], .texcoord = m.Vec2f{ .x = 0, .y = 0 }, .colour = colour },
    };

    p.batchs[i].data.submitDrawable(vx) catch |err| {
        if (err == Error.ObjectOverflow) {
            try pr.drawPrivateBatch(i);
            pr.cleanPrivateBatch(i);
            //alog.notice("batch(id: {}) flushed!", .{i});

            return p.batchs[i].data.submitDrawable(vx);
        } else return err;
    };
}

/// Draws a rectangle line, angle should be in radians
/// Draw mode: lines
pub fn drawRectangleLinesAdv(rect: m.Rectangle, origin: m.Vec2f, angle: f32, colour: Colour) Error!void {
    const pos = createQuadPositionsMVP(rect, origin, angle);

    try drawLine(pos[0], pos[1], 1, colour);
    try drawLine(pos[1], pos[2], 1, colour);
    try drawLine(pos[2], pos[3], 1, colour);
    try drawLine(pos[0], pos[3], 1, colour);
}

/// Draws a texture
/// Draw mode: triangles
pub fn drawTexture(texture_id: u64, rect: m.Rectangle, srect: m.Rectangle, colour: Colour) Error!void {
    const i: usize = try identifyBatchID(.triangles, pr.embed.default_shader.id, texture_id);
    const pos = createQuadPositions(rect);
    return pr.submitTextureQuad(i, pos[0], pos[1], pos[2], pos[3], srect, colour);
}

/// Draws a texture, angle should be in radians
/// Draw mode: triangles
pub fn drawTextureAdv(texture_id: u64, rect: m.Rectangle, srect: m.Rectangle, origin: m.Vec2f, angle: f32, colour: Colour) Error!void {
    const i = try identifyBatchID(.triangles, pr.embed.default_shader.id, texture_id);
    const pos = createQuadPositionsMVP(rect, origin, angle);
    return pr.submitTextureQuad(i, pos[0], pos[1], pos[2], pos[3], srect, colour);
}

/// Draws a given codepoint from the font
/// Draw mode: triangles
pub fn drawTextPoint(font_id: u64, codepoint: i32, position: m.Vec2f, psize: f32, colour: Colour) Error!void {
    const font = try p.assetmanager.getFont(font_id);
    const i = try identifyBatchIDWithNoID(.triangles, pr.embed.default_shader.id, font.texture);
    return pr.submitFontPointQuad(i, font_id, codepoint, position, psize, colour);
}

/// Draws the given string from the font
/// Draw mode: triangles
pub fn drawText(font_id: u64, string: []const u8, position: m.Vec2f, psize: f32, colour: Colour) Error!void {
    const spacing: f32 = 1;
    const font = try p.assetmanager.getFont(font_id);

    var offx: f32 = 0;
    var offy: f32 = 0;
    const scale_factor: f32 = psize / @intToFloat(f32, font.base_size);

    var i: usize = 0;
    while (i < string.len) {
        var codepointbytec: i32 = 0;
        var codepoint: i32 = utf8.nextCodepoint(string[i..], &codepointbytec);
        const index: usize = @intCast(usize, font.glyphIndex(codepoint));

        if (codepoint == 0x3f) codepointbytec = 1;

        if (codepoint == '\n') {
            offy += @intToFloat(f32, (font.base_size + @divTrunc(font.base_size, 2))) * scale_factor;
            offx = 0;
        } else {
            if ((codepoint != ' ') and (codepoint != '\t')) {
                try drawTextPoint(font_id, codepoint, m.Vec2f{ .x = position.x + offx, .y = position.y + offy }, psize, colour);
            }

            if (font.glyphs[index].advance == 0) {
                offx += font.rects[index].size.x * scale_factor + spacing;
            } else offx += @intToFloat(f32, font.glyphs[index].advance) * scale_factor + spacing;
        }

        i += @intCast(usize, codepointbytec);
    }
}

fn createQuadPositions(rect: m.Rectangle) [4]m.Vec2f {
    return [4]m.Vec2f{
        m.Vec2f{ .x = rect.position.x, .y = rect.position.y },
        m.Vec2f{ .x = rect.position.x + rect.size.x, .y = rect.position.y },
        m.Vec2f{ .x = rect.position.x + rect.size.x, .y = rect.position.y + rect.size.y },
        m.Vec2f{ .x = rect.position.x, .y = rect.position.y + rect.size.y },
    };
}

fn createQuadPositionsMVP(rect: m.Rectangle, origin: m.Vec2f, rad: f32) [4]m.Vec2f {
    var model = m.ModelMatrix{};
    model.translate(rect.position.x, rect.position.y, 0);
    model.translate(origin.x, origin.y, 0);
    model.rotate(0, 0, 1, rad);
    model.translate(-origin.x, -origin.y, 0);
    const mvp = model.model;

    const r0 = m.Vec3f.transform(.{ .x = 0, .y = 0 }, mvp);
    const r1 = m.Vec3f.transform(.{ .x = rect.size.x, .y = 0 }, mvp);
    const r2 = m.Vec3f.transform(.{ .x = rect.size.x, .y = rect.size.y }, mvp);
    const r3 = m.Vec3f.transform(.{ .x = 0, .y = rect.size.y }, mvp);

    return [4]m.Vec2f{
        m.Vec2f{ .x = rect.position.x + r0.x, .y = rect.position.y + r0.y },
        m.Vec2f{ .x = rect.position.x + r1.x, .y = rect.position.y + r1.y },
        m.Vec2f{ .x = rect.position.x + r2.x, .y = rect.position.y + r2.y },
        m.Vec2f{ .x = rect.position.x + r3.x, .y = rect.position.y + r3.y },
    };
}

fn identifyBatchID(mode: gl.DrawMode, sshader: u64, texture: u64) Error!usize {
    if (p.force_batch) |id| {
        return id;
    } else {
        var shader = sshader;
        if (p.force_shader) |shaa| {
            shader = shaa;
        }
        const batch = getBatch(mode, shader, texture) catch |err| {
            if (err == Error.InvalidBatch) {
                _ = try createBatch(mode, shader, texture);
                return identifyBatchID(mode, sshader, texture);
            } else return err;
        };

        return @intCast(usize, batch.id);
    }

    return Error.FailedToFindBatch;
}

fn identifyBatchIDWithNoID(mode: gl.DrawMode, sshader: u64, texture: renderer.Texture) Error!usize {
    if (p.force_batch) |id| {
        return id;
    } else {
        var shader = sshader;
        if (p.force_shader) |shaa| {
            shader = shaa;
        }
        const sh = try p.assetmanager.getShader(shader);

        const batch = getBatchNoID(mode, sh, texture) catch |err| {
            if (err == Error.InvalidBatch) {
                _ = try createBatchNoID(mode, sh, texture);
                return identifyBatchIDWithNoID(mode, sshader, texture);
            } else return err;
        };

        return @intCast(usize, batch.id);
    }
    return Error.FailedToFindBatch;
}
