# Alka
Game engine written in zig, compatible with **zig version 0.8.0**.

This engine does provide a toolset for you but generally you have to implement how they work and how should be.

For example if you want to use `GUI`, well you can and engine provides a tool for you but you have to implement how 
`elements` behave, draw, etc. There is no `ButtonElement` or `TextBox`, only `Element`. Same goes for the `ECS` too.

-----
You may need these packages to compile the engine(tested on ubuntu 21.04)
`libx11-dev libxcursor-dev libxrandr-dev libxinerama-dev libxi-dev libgl-dev`

Get started [now](https://github.com/Kiakra/Alka/blob/master/get-started.md)

[Documentation]()

-----
## Project goals
- [x] Single window operations
- [x] Input management
- [x] Asset manager
- [x] Custom batch system 
- [x] 2D Camera
- [X] 2D Shape drawing
- [x] 2D Texture drawing
- [x] 2D Text drawing 
- [x] Simple ecs
- [ ] Simple 2D lightning
- [ ] Simple 2D physics
- [x] GUI system
- [ ] Audio
- [ ] Optional: Data packer 
- [ ] Optional: Scripting language 
- [ ] Optional: Vulkan implementation
- [ ] Optional: Android support

----
## About release cycle
* Versioning: major.minor.patch
* Every x.x.3 creates a new minor, which becomes x.(x + 1).0
* Again every x.3.x creates a new major, which becomes (x + 1).0.x
* When a new version comes, it'll comitted as x.x.x source update
