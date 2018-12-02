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

Being a part of an organization like [allegro](http://allegro.tech)
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

The state is separate for each node of course.

![raft sate machine](/assets/images/2018-11-25-rafting-for-fun-and-profit/state-machine.png)
<figcaption class="caption">Raft state changes - from raft paper</figcaption>

&nbsp;

The state changes based on input from other nodes and time passing by.
Here is the summary of rules:

1. Every node starts in a follower state.
2. If it doesn't receive heartbeat from a leader then it transitions into candidate
and bumps current term.
3. A candidate requests votes from it's peers and votes for himself.
4. If a node gets majority of the votes it becomes a leader.
5. A leader must send heartbeat to other nodes to make sure they are alive.
6. If a node receives heartbeat with higher term it changes it's state to follower and
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

Let's see an example function from the 200-ish lines of monstrosity behind this:

```javascript
async function sendHeartBeat() {
    if (role === roles.leader) {
        const peersWithoutMe = getPeersWithoutMe(peers, nodeId);
        const responses = await Promise.all(peersWithoutMe.map(p => request.post({
            url: `http://${p}/raft/append-entries`,
            json: {
                term: currentTerm, // (1)
            },
            timeout: REQUEST_TIMEOUT,
            resolveWithFullResponse: true
        })).map(p => p.catch(e => e)));

        // am I still the leader? (2)
        const stillLeader = responses.every(r => {
            if (r.statusCode === 200) {
                return r.body.term === currentTerm;
            } else if (r.statusCode !== 200) {
                return true;
            } else { // (3)
                return false;
            }
        });

        if (stillLeader) {
            setTimeout(sendHeartBeat, HEARTBEAT_INTERVAL);
        } else {
            console.log(nodeId, 'lost leadership');
        }
    }
}
```

As you can see, there is HTTP code mixed with algorithm logic (1)
a check counting votes that for some reason checks the term (2)
and some dead code (3).

You can see the full code of this at
[spaghetti-raft.js](https://gist.github.com/slonka/1f02a9b403891f624dffa2a121927d1c)

There are definitely some unnecessary if statements, checks that don't make sense.
Making changes in this code meant I had to re-check every path I thought about manually.
After making a change I did not know the consequences, I was clueless.

Now I know the problem, let's make it better.

## TDD to the rescue

A state machine like that should be fairly easy to test, right?
I've got a bunch of input states,
bunch of transition functions
and expected output after transitions.
It's as easy as it can get.

Let's go one by one over the list of steps I outlined in the introduction.
I started with a simple test:

```javascript
it('should start with initial state', function() {
});
```

Easy - create a state machine,
set initial state in constructor
and check it's state is the same as the default state defined in the paper.

Next:

```javascript
it('should transition to candidate role when it did not receive a heartbeat', async function() {
});
```

Hmm - this one is more tricky, we need some timeouts
and keep track of the last heartbeat.
I added a `setTimeout` coupled with `clearTimeout`,
a function that will check if leader timed out - `leaderTimedOut()`
and voila: it works...

```javascript
async transitionToCandidate() {
    if (this.leaderTimedOut() && this.state.role !== roles.leader) {
        this.state.role = roles.candidate;
        this.state.currentTerm += 1;
        this.state.alreadyVotedInThisTerm = true;

        const votes = await this.getVotes();
        const positive = this.countPositiveVotes(votes);
        logger.log('received positive votes', positive);
        this.state.votesGranted = positive;

        if (positive > (this.state.peers.size / 2)) {
            clearTimeout(this.leaderTimeout);
            this.transitionToLeader();
        } else {
            this.resetLeaderTimeout(); // (1)
        }
    }
}

resetLeaderTimeout() {
    clearTimeout(this.leaderTimeout);
    this.leaderTimeout = setTimeout(this.transitionToCandidate.bind(this), config.leaderTimeout);
}
```

But it's kind of "janky"[*](http://jankfree.org/) and unstable...
Sometimes it stops immediately,
sometimes the test runs for a couple of seconds.
To understand why I had to refresh my memory about event loop
and conditions for a node process to exit.

Every asynchronous *thing* is going to be queued up in the event loop
to be processed at the later time.
A node process will not exit if it has anything left to do in the event loop.
I made sure that the event loop was constantly occupied
by clearing a timeout an starting a new one every time I called `resetLeaderTimeout()`.

The situation looks like this when `transitionToCandidate()` is called:

```
Stack: [transitionToCandidate()]
Event loop: []
```

And by the time it exits it's on the event loop (1)

```
Stack: []
Event loop: [transitionToCandidate()]
```

Ok, so how to fix it?
There is a function that can be called on a
`timeout`,
`immediate`
and `subprocess`
called [unref](https://nodejs.org/api/timers.html#timers_timeout_unref)
which makes "object not require the Node.js event loop to remain active".

Alright, we fixed that one - the rest of them is pretty much rinse & repeat.
In couple of places we need `testdouble` to mock responses to force positive / negative votes,
but that is pretty standard.

One thing that is quite cool is that I've abstracted a `LocalRaftStateMachine`
and `RemoteRaftStateMachine`.
The local version keeps everything in memory and is great for testing.
Nodes interact by directly calling functions on each other.
The remote version works with a hooked up server and communicates via HTTP RPC.

## Summary

During this exercise I've learned a lot, mostly:
- distributed consensus is hard
- tdd can make your life easier but it's hard to pull off when you don't know what you're doing
- making small things that do not work and won't be deployed anywhere can still be valuable

You can see the full source code [in this repository](https://github.com/slonka/rafting-for-fun-and-profit).
