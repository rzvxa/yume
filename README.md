##### Early Development Notice  
###### This project is in the early stages of development (pre-v0.1), and at this point, it's not recommended for any real-world use case. The goal is to achieve a working version with feature parity with older versions of Unity3D (e.g. Unity 4.6 or Unity 5) before 1.0. However, no matter how close we get to a minimum viable feature set for being production-ready, while we're pre-v0.1, everything—including the fundamental components—is experimental and possibly subject to drastic changes. After that, changes become more migration-friendly, but remain common until we hit 1.0!

![demo](https://github.com/user-attachments/assets/7a45e1d6-7bec-4b77-adf1-080e9e457efd)

# Yume

Yume is a 3D game engine focused on ease of use over modularity. The goal is to provide a battery-included engine with a focus on tooling and a user-friendly editor over hackability.

Yume is a self-contained, highly portable game engine that doesn't rely on extensive third-party dependencies. Designed in Zig, it offers low-level control and high performance while maintaining an intuitive workflow for rapid prototyping and development.

Yume comes with tools that both artists and developers need to maximize their productivity. Things like live previews, built-in animation systems, first-class scripting support, terrain, foliage, and node-based BSDF shading should be part of the core engine, not an afterthought.

## Key Features

- **Ease of Use:** A streamlined experience designed for both beginners and experienced developers, allowing you to focus on game creation rather than dealing with unnecessary boilerplate.
- **Battery-Included:** Out-of-the-box tools such as a built-in editor, asset management system, and debugging utilities.
- **High Portability:** Built with Zig for close-to-the-metal performance, Yume compiles across multiple operating systems and hardware configurations.
- **Editor First:** Emphasis on a user-friendly interface to help you design levels, manage assets, and fine-tune gameplay without getting bogged down in complex configurations.
- **Experimental Flexibility:** The engine is evolving. New ideas and radical changes are part of the journey, ensuring that Yume remains a playground for innovation.

## Getting Started

### Prerequisites

- **Zig Compiler:** Ensure you have the Zig `v0.13.0` installed in your `PATH`.
- **A modern C++ Compiler:** Visual Studio 2019+, Clang 10+ or GCC 9+. Some third-party libraries require C++17.
- **CMake:** (>= v3.16) This is a temporary dependency to avoid porting some third-party build configurations to Zig.
- **Graphics Capabilities:** A modern graphics card capable of supporting Vulkan or Metal (for now through MoltenVK, with native Metal and DX12 on the way).
- **Development Environment:** Familiarity with basic game development concepts is recommended.

### Installation

Clone the repository and navigate into the project directory:

```bash
git clone https://github.com/rzvxa/yume.git
cd yume
# build and run the editor
zig build run
```

For advanced build options and platform-specific configuration, please refer to our [Build Guide](docs/BUILD.md).

## Roadmap

Yume is under active development. Our near-term goals include:

- **Core Rendering Pipeline:** Refining the graphics engine to handle modern rendering techniques.
- **Enhanced Editor Tools:** Developing a rich, integrated editor with level design, asset management, and scripting capabilities.
- **Scripting & API Integration:** Building a flexible scripting layer to empower rapid game logic development.
- **Animation:** Support for skinned meshes, IK, and Animation Graph (state machine).
- **Performance & Debugging Tools:** Creating comprehensive tools for profiling, debugging, and performance optimization.
- **Support for more platforms:** Linux, Android, iOS, and WebGPU support.

In the long run, we envision Yume to grow into a robust solution capable of supporting projects from indie prototypes to more ambitious productions.

## FAQ

### Why Zig over C++?

There is already a plethora of amazing open-source and proprietary engines written in C++. C++ is a mature, well-established language with a vast ecosystem. However, this maturity also means that many engines adhere strictly to industry conventions, which can sometimes restrict creative innovation. Zig offers modern memory safety and performance benefits while allowing low-level control. This means we can experiment with innovative design patterns and build an engine that breaks from conventional molds—ensuring that every game has its own unique feel instead of following a cookie-cutter formula.

### Why Zig over C?

Zig brings modern facilities to the table while keeping a minimalistic approach that closely resembles C. Key advantages include:
- **Enhanced Compile-Time Features:** With compile-time execution (comptime), you can generate code dynamically and perform checks before runtime.
- **Simplicity and Explicitness:** Unlike C, Zig avoids hidden control flow and implicit conversions, leading to clearer, more maintainable code.
- **Improved Cross-Compilation:** Zig’s build system is designed to streamline cross-compilation, reducing the hassle of targeting multiple platforms.

These improvements provide developers with powerful tools while avoiding some of the pitfalls and undefined behaviors common in C.

### Why Zig over Rust?

While Rust is celebrated for its strong emphasis on memory safety and concurrency, it also breaks so easily when interacting with an unsafe API, and as soon as you break the borrow checker, the whole program becomes unsound. Unfortunately, it is a very common occurrence in game development where you have to rely on existing libraries written in C++, which can easily cause aliasing issues and break the borrow checker. It's also true the other way around, it's really hard to provide a stable ABI(even for Rust-Rust calls), which makes scripting hard to implement.

This, and the fact that game logic can become overly entangled with each other, makes it really hard to prototype in a language such as Rust. Yes, for a highly optimized game world where you want to support, let's say, an MMO for 10+ years, it might be feasible to invest in the extra development time required; however, it isn't a silver bullet. For a general-purpose game engine, flexibility is more favorable compared to absolute safety. As long as user-generated content is running in a sandboxed scripting language, nobody cares if the game crashes after 48 hours of uptime if it means you get to play the game 3 years sooner.

- **No Borrow Checker:** Zig foregoes the sometimes-complex borrow checking system, offering a more straightforward approach to memory management that many find easier for iterative and experimental projects.
- **Lower-Level Control:** Zig provides direct, uncompromised access to low-level operations similar to C but with modern conveniences and safety nets.
- **Simpler Toolchain Integration:** Zig’s minimal runtime and self-contained tooling often result in faster compile times and easier cross-platform support.

These aspects make Zig an appealing alternative for projects that demand simplicity without sacrificing performance.

### Is Yume production-ready?

Not yet. Yume is in its experimental phase, and while our goal is to achieve feature parity with earlier iterations of mainstream engines like Unity, you should consider current builds for prototyping and experimentation rather than for critical production use.

### How can I contribute?

We welcome community contributions! If you're interested in helping shape Yume, please review our [Contribution Guidelines](CONTRIBUTING.md) to learn more about reporting bugs, submitting feature requests, or contributing code. Every bit of feedback helps us grow.

## License

Yume is licensed under the [MIT License](LICENSE). You are free to use, modify, and distribute this software as long as you adhere to the license terms.

---

We hope Yume inspires you to build something amazing. Whether you're an indie developer, student, or professional, your feedback and contributions will help us shape Yume into a powerful tool for creative game development. Let's explore the future of game engines together!

*Happy coding and keep innovating!*
