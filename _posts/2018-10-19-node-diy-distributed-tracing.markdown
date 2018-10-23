---
title: "Node DIY part 1 - Distributed tracing"
layout: post
date: 2018-10-19 20:00
image: /assets/images/markdown.jpg
headerImage: false
tag:
- node
- nodejs
- node.js
- javascript
- distributed
- distributed tracing
- x-correlation-id
- x-request-id
- diy
- node-diy
star: true
category: blog
author: slonka
description: Markdown summary with different options
---


## Intro

This is a first post of the series called **Node DIY** - a guide that
will explain how seemingly complex tools/frameworks/ideas work under the hood
and what is at the core of them.
I will try to introduce the topic and implement a bare-bones, no dependecies solution.
It will be far from production ready, but that's the point.

Today's topic is distributed tracing.
Distributed tracing is a process of identifying the path that a request (or other forms of activity, but in this article I'll focus on HTTP)
travels through every part of your system.

When I first tried out [newrelic](https://docs.newrelic.com/docs/apm/distributed-tracing/getting-started/introduction-distributed-tracing)
I was curious how they were able to trace all of the interactions between my services
and all they needed was one function call in the application entry point.

## Communication

I knew that the tracing information must be kept somewhere in the HTTP request.
There is no side channel, because the library works across closed environments (different machines, vms, containers).

![Markdowm Image](/assets/images/2018-10-19-node-diy-distributed-tracing/distributed-tracing.png)
