# ZagEngine — Vulkan Triangle Renderer

The starting foundation of **ZagEngine**, an experimental graphics and compute engine built with Zig.

This project establishes a low-level Vulkan rendering pipeline using **Zig 0.17, Vulkan and SDL3**, interfacing directly with the native Vulkan C API through Zig's C interoperability.

The goal is to build an engine from the ground up, understanding and implementing the underlying graphics and compute infrastructure rather than relying on high-level rendering abstractions or third-party Vulkan bindings.

## Current Features

- SDL3 window and Vulkan surface creation.
- Vulkan instance and validation layers.
- Physical GPU selection and logical device creation.
- Graphics and presentation queue management.
- Swapchain creation and image management.
- Image views, render passes and framebuffers.
- Graphics pipeline creation using compiled GLSL shaders.
- Command buffers and frame synchronisation.
- Swapchain recreation and presentation.

## Demonstration

Successfully renders a triangle using an NVIDIA RTX 2070 SUPER under Linux.

## Project Direction

This repository represents the initial graphics foundation of ZagEngine. Future development will explore:

- GPU memory management and buffer allocation.
- Vertex and index buffers.
- 3D rendering and camera systems.
- Graphics and compute pipelines.
- Headless Vulkan compute.
- Reusable engine architecture and resource management.

## Open Source

This project is shared openly for anyone interested in learning Zig, Vulkan, low-level graphics programming or GPU compute.

Feel free to explore the code, use it as a learning resource, or build upon it for your own projects.
