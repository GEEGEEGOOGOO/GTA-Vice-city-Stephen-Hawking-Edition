# Verification

The local build was tested on Apple Silicon with macOS 27.2.1. The app's declared deployment floor is macOS 26. Intel Macs and older macOS builds have no tested package.

- The installer checks the source game's SHA-256 checksums, verifies the reconstructed files, and verifies the resulting code signature.
- Native tests cover wheelchair movement and boost, vehicle seating, Ambassador spawning, four autorickshaws, bicycle loading, commercial traffic, Tumbler loading and all seven replacement vehicles.
- Blender 5.2.2 LTS reopened 71 project files and two linked donor snapshots. The two historical Fortuner scenes keep placeholders for nine absent source textures. The final game-ready Fortuner scene resolves its file dependencies.
