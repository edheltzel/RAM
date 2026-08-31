# RAM

A tiny macOS menu extra that shows memory pressure and who is holding pages.

[Stats](https://github.com/exelban/stats) already solved the menu-bar monitor. It is also a suite: CPU, GPU, disks, network, sensors, batteries, and a settings window for each module. That is the right product when you want the whole machine. It is heavy when all you needed was the RAM chip.

This extra is that chip. `RAM 67%` stays in the menu bar. Click it for a Stats-style RAM popup — pressure gauge, usage ring, a short history, App / Wired / Compressed / Free, and a ranked process list with a handful of grouping views. There is no preferences window. Launch at login, view mode, Activity Monitor, and Quit live in the popup.

It is not a RAM cleaner. macOS is already compressing, swapping, and reclaiming. A “free memory” button would only lie about that. The job is to see pressure, see the split, and Force Quit a single process when you mean it.

Anyone with Xcode can build and run it. See [Getting started](docs/getting-started.md).
