---
title: "Rafting for fun and profit"
layout: post
date: 2018-11-25 20:00
tag:
- node
- nodejs
- node.js
- JavaScript
- ECMAScript
- distributed
- distributed consensus
- consensus
- raft
- algorithm
- consensus algorithm
star: true
category: blog
author: slonka
description: A javascript implementation of Raft - an understandable consensus algorithm
published: true
---


## Intro

Being a part of an organization like [allegro.tech](http://allegro.tech)
I can participate in something that's called "Skylab training days" which is
a day dedicated to working on something cool and interesting, not related to current sprint.
Something similar to Google's "20% time".
During last training days my colleagues and I implemented a Raft consensus algorithm,
that can form a cluster, elect a leader and survive failures.
You can read the paper on Raft [here](https://raft.github.io/raft.pdf),
but I'll highlight the important bits in this post.

We did not implement all of Raft's features.
In the paper you can read that:
"Raft is a consensus algorithm for managing a replicated log" -
our implementation was limited to leader election.
The API and subset of features are described in [pbetkier/rafting](https://github.com/pbetkier/rafting)
and the repository includes a slick front-end visualization.

## Raft summary

The way I picture the algorithm is a state machine with 3 states:
- follower
- candidate
- leader

![raft sate machine](/assets/images/2018-11-25-rafting-for-fun-and-profit/state-machine.png)
<figcaption class="caption">Raft state changes - from raft paper</figcaption>

&nbsp;

The state changes based on input from other nodes and time passing by.
Every node starts in a follower state.
If it doesn't receive heartbeat from a leader then it transitions into candidate
and bumps current term.
A candidate requests votes from it's peers and votes for himself.
If a node gets majority of the votes it becomes a leader.
A leader must send heartbeat to other nodes to make sure they are alive.
If a node receives heartbeat with higher term it changes it's state to follower and
updates it's term.

## Implementation

I actually wrote the algorithm twice, first time was kind of a spaghetti flavoured hack.
I did not understand the paper well enough to write tests and I just wanted to see something on the screen.
So I started with a simple object called `state`.
I hooked up controllers to every endpoint and began mutating that object based on input.
Then I added timeouts to make followers transition into candidates.
A couple of HTTP calls and it kind of worked.
I run the server in 5 tmux panes and observed the behavior.
After a couple of hours of tinkering I eventually got it right and here is the result.

<iframe width="810" height="455" src="https://www.youtube.com/embed/nRrJZjvlEbk" frameborder="0" allowfullscreen></iframe>


