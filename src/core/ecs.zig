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
const utils = @import("utils.zig");
const UniqueList = utils.UniqueList;
const UniqueFixedList = utils.UniqueFixedList;

pub const Error = error{ InvalidComponent, FailedtoAllocate, InvalidRegister } || utils.Error;

/// Stores the component struct in a convenient way
pub fn StoreComponent(comptime name: []const u8, comptime Component: type, comptime MaxEntity: usize) type {
    return struct {
        const Self = @This();
        pub const T = Component;
        pub const TMax = MaxEntity;
        pub const Name = name;

        alloc: *std.mem.Allocator = undefined,
        
        // the reason why this cannot be fixed list is bc
        // the registered components adress in the memory is fixed
        components: *UniqueFixedList(T, TMax) = undefined,

        /// Initializes the storage component
        pub fn init(alloc: *std.mem.Allocator) Error!Self {
            var self = Self{
                .alloc = alloc,
                .components = alloc.create(UniqueFixedList(T, TMax)) catch return Error.FailedtoAllocate,
            };
            self.components.clear();
            return self;
        }

        /// Adds a component
        pub fn add(self: *Self, id: u64, data: T) Error!void {
            return self.components.append(id, data);
        }

        /// Returns a component
        /// NOTE: READ ONLY
        pub fn get(self: Self, id: u64) Error!T {
            return self.components.get(id);
        }

        /// Returns a component
        /// NOTE: MUTABLE
        pub fn getPtr(self: *Self, id: u64) Error!*T {
            return self.components.getPtr(id);
        }

        /// Has the component? 
        pub fn has(self: Self, id: u64) bool {
            return !self.components.isUnique(id);
        }

        /// Removes the component 
        pub fn remove(self: *Self, id: u64) bool {
            return self.components.remove(id);
        }

        /// Deinitializes the storage component
        pub fn deinit(self: Self) void {
            self.alloc.destroy(self.components);
        }
    };
}

pub fn World(comptime Storage: type) type {
    return struct {
        const TNames = comptime std.meta.fieldNames(T);
        const _World = @This();
        pub const T = Storage;

        pub const Register = struct {
            pub const Entry = struct {
                id: u64 = undefined,
                name: []const u8 = undefined,
                ptr: ?u64 = null,
            };

            world: *_World = undefined,
            attached: UniqueList(Entry) = undefined,
            id: u64 = undefined,

            fn removeStorage(self: *Register, name: []const u8) Error!void {
                inline for (TNames) |tname| {
                    const typ = @TypeOf(@field(self.world.entries, tname));

                    if (std.mem.eql(u8, typ.Name, name)) {
                        if (!@field(self.world.entries, tname).remove(self.id)) return Error.InvalidComponent;
                        return;
                    }
                }
                return Error.InvalidComponent;
            }

            /// Creates the register
            pub fn create(self: *Register) Error!void {
                self.attached = try UniqueList(Entry).init(self.world.alloc, 0);
            }

            /// Attaches a component
            pub fn attach(self: *Register, name: []const u8, component: anytype) Error!void {
                inline for (TNames) |tname| {
                    const typ = @TypeOf(@field(self.world.entries, tname));
                    if (std.mem.eql(u8, typ.Name, name)) {
                        //std.log.debug("{s}", .{typ});
                        //std.log.debug("comp: {s} {s}", .{ typ.T, @TypeOf(component) });
                        if (typ.T == @TypeOf(component)) {
                            var storage = &@field(self.world.entries, tname);
                            //std.log.debug("component: {}", .{component});
                            try storage.add(self.id, component);

                            const entry = Entry{
                                .id = self.attached.findUnique(),
                                .name = typ.Name,
                                .ptr = @ptrToInt(try storage.getPtr(self.id)),
                            };

                            //std.log.debug("id: {}, {s}", .{ self.id, entry });
                            return self.attached.append(entry.id, entry);
                        }
                    }
                }
                return Error.InvalidComponent;
            }

            /// Detaches a component
            pub fn detach(self: *Register, name: []const u8) Error!void {
                var it = self.attached.iterator();
                while (it.next()) |entry| {
                    if (entry.data) |data| {
                        if (std.mem.eql(u8, data.name, name)) {
                            if (data.ptr) |ptr| {
                                try self.removeStorage(name);
                                if (!self.attached.remove(data.id)) return Error.InvalidComponent;
                                return;
                            }
                        }
                    }
                }
                return Error.InvalidComponent;
            }

            /// Returns the attached component
            /// NOTE: READ-ONLY
            pub fn get(self: Register, name: []const u8, comptime ctype: type) Error!ctype {
                var it = self.attached.iterator();
                while (it.next()) |entry| {
                    if (entry.data) |data| {
                        if (std.mem.eql(u8, data.name, name)) {
                            if (data.ptr) |ptr| {
                                var component = @intToPtr(*ctype, ptr);
                                return component.*;
                            }
                        }
                    }
                }
                return Error.InvalidComponent;
            }

            /// Returns the attached component
            /// NOTE: MUTABLE 
            pub fn getPtr(self: Register, name: []const u8, comptime ctype: type) Error!*ctype {
                var it = self.attached.iterator();
                while (it.next()) |entry| {
                    if (entry.data) |data| {
                        if (std.mem.eql(u8, data.name, name)) {
                            if (data.ptr) |ptr| {
                                var component = @intToPtr(*ctype, ptr);
                                return component;
                            }
                        }
                    }
                }
                return Error.InvalidComponent;
            }

            /// Has the component?
            pub fn has(self: Register, component: []const u8) bool {
                var it = self.attached.iterator();
                while (it.next()) |entry| {
                    if (entry.data) |data| {
                        if (std.mem.eql(u8, data.name, component)) {
                            return true;
                        }
                    }
                }
                return false;
            }

            /// Has these components?
            pub fn hasThese(self: Register, comptime len: usize, complist: [len][]const u8) bool {
                for (complist) |comp| {
                    var it = self.attached.iterator();
                    while (it.next()) |entry| {
                        if (entry.data) |data| {
                            if (!self.has(comp)) {
                                return false;
                            }
                        }
                    }
                }
                return true;
            }

            /// Destroys the register
            pub fn destroy(self: Register) void {
                self.attached.deinit();
            }
        };

        /// Iterator
        fn Iterator(comptime len: usize, comps: [len][]const u8) type {
            return struct {
                const _Iterator = @This();

                pub const Entry = struct {
                    value: ?*Register = 0,
                    index: usize = 0,
                };

                world: *_World = undefined,
                index: usize = 0,

                fn getRegister(it: *_Iterator) ?*Register {
                    if (it.world.registers.items[it.index].data != null) {
                        var data = &it.world.registers.items[it.index].data.?;
                        if (data.hasThese(len, comps)) {
                            return data;
                        }
                    }
                    return null;
                }

                pub fn next(it: *_Iterator) ?Entry {
                    if (it.index >= it.world.registers.items.len) return null;

                    const result = Entry{ .value = it.getRegister(), .index = it.index };
                    it.index += 1;

                    return result;
                }

                /// Reset the iterator
                pub fn reset(it: *_Iterator) void {
                    it.index = 0;
                }
            };
        }

        alloc: *std.mem.Allocator = undefined,
        entries: T = undefined,
        registers: UniqueList(Register) = undefined,

        /// Initializes the world
        pub fn init(alloc: *std.mem.Allocator) Error!_World {
            var self = _World{
                .alloc = alloc,
                .entries = undefined,
            };

            inline for (TNames) |name| {
                const typ = @TypeOf(@field(self.entries, name));
                @field(self.entries, name) = try typ.init(self.alloc);
            }

            self.registers = try UniqueList(Register).init(self.alloc, 10);

            return self;
        }

        /// Creates an iterator
        pub fn iterator(comptime len: usize, complist: [len][]const u8) type {
            return Iterator(len, complist);
        }

        /// Creates a register
        pub fn createRegister(self: *_World, id: u64) Error!*Register {
            var reg = Register{
                .world = self,
                .id = id,
            };
            try self.registers.append(reg.id, reg);

            return self.registers.getPtr(reg.id);
        }

        /// Finds a non-unique id
        pub fn findID(self: _World) u64 {
            return self.registers.findUnique();
        }

        /// Returns a register
        /// NOTE: READ-ONLY 
        pub fn getRegister(self: _World, id: u64) Error!Register {
            return self.registers.get(id);
        }

        /// Returns a register
        /// NOTE: MUTABLE 
        pub fn getRegisterPtr(self: *_World, id: u64) Error!*Register {
            return self.registers.getPtr(id);
        }

        /// Removes a register
        pub fn removeRegister(self: *_World, id: u64) Error!void {
            inline for (TNames) |name| {
                _ = @field(self.entries, name).remove(id);
            }

            if (!self.registers.remove(id)) return Error.InvalidRegister;
        }

        /// Deinitializes the world
        pub fn deinit(self: *_World) void {
            var it = self.registers.iterator();
            while (it.next()) |entry| {
                if (entry.data) |entity|
                    entity.destroy();
            }

            self.registers.deinit();
            inline for (TNames) |name| {
                @field(self.entries, name).deinit();
            }
        }
    };
}
