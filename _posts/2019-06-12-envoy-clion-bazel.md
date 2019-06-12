---
title: "How to develop envoy in CLion with bazel plugin"
layout: post
date: 2019-06-12 16:00
tag:
- envoy
- IDE
- envoy development
- envoy integraded development environment
- clion
- bazel
- jetbrains
- intellij
star: true
category: blog
author: slonka
description: Sane development environment for envoy.
published: true
---

## Install

You'll need:
- [CLion](https://www.jetbrains.com/clion/download/#section=mac)
- [Custom build](https://github.com/bazelbuild/intellij/issues/494#issuecomment-498814006) of [bazel plugin](https://plugins.jetbrains.com/plugin/9554-bazel)

## Debugging project
1. Launch CLion
1. Import `envoy` via bazel plugin
1. Select WORKSPACE file `envoy/WORKSPACE`
1. Next
1. Select BUILD file `envoy/BUILD`
1. Wait for project to synchronize
1. Add run configuration
```
Target expression: //source/exe:envoy-static
Bazel command: run
Bazel flags: -c dbg --spawn_strategy=standalone
Executable flags: --config-path PATH_TO_ENVOY_CONFIG -l debug
```
![run configuration](/assets/images/2019-06-12-envoy-clion-bazel/run_configuration.png)

1. Set symbolic breakpoints (only those work, but it's better than nothing)
![symbolic breakpoints clion](/assets/images/2019-06-12-envoy-clion-bazel/breakpoints.png)

1. Click debug
1. Debugger should stop on in the main function
![debugger](/assets/images/2019-06-12-envoy-clion-bazel/debugger.png)