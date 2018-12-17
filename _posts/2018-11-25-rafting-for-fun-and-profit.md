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
- raft tutorial
- raft toy implementation
- algorithm
- consensus algorithm
- tdd
- test driven development
- testing time
- testing setTimeout
- testing setInterval
- mocking timers node.js
- mocking node.js
- testdouble
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

## API

We did not implement all of Raft's features.
In the paper you can read that:
"Raft is a consensus algorithm for managing a replicated log" -
our implementation was limited to leader election.
The API and subset of features are described in [pbetkier/rafting](https://github.com/pbetkier/rafting)
and the repository includes a slick front-end visualization.

There are 3 main endpoints:
```
POST	/raft/request-vote - starting a vote
POST	/raft/append-entries - sending heartbeats
GET	/raft/state - (dashboard only) dumping raft state
```

It uses JSON over HTTP.

The visualization looks like this:

![rafting dashboard](/assets/images/2018-11-25-rafting-for-fun-and-profit/rafting-dashboard.png)
<figcaption class="caption">Raft dashboard visualization</figcaption>

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
5. A leader must send heartbeat to other nodes to make sure they are alive
and let them know who is the leader.
6. If a node receives heartbeat with higher term it changes it's state to follower and
updates it's term.

## Implementation

I actually wrote the algorithm twice, first time was kind of a spaghetti flavoured hack.
I did not understand the paper well enough to write tests and I just wanted to see something on the screen.
So I started with a simple object called `state`.
I hooked up controllers to every endpoint and began mutating that object based on input.
Then I added timeouts to make followers transition into candidates.
After that I added A couple of HTTP calls to request votes and... it worked! (kind of)
I run the server in 5 [tmux](https://github.com/tmux/tmux) panes and observed the behavior.
After a couple of hours of tinkering I eventually got it right and here is the result:

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

```javascript
const emptyState = {
    currentTerm: 0,
    lastHeartbeat: null,
    role: 'follower',
    nodeId: null,
    votedFor: null,
    votesGranted: 0,
}

class RaftStateMachine {
    constructor({ nodeId }) {
        if (nodeId == undefined) {
            throw new Error('nodeId and peers must be defined, peers must be an array');
        }

        this.state = { ...emptyState, peers: new Set(), nodeId };
    }
}

/// ...

test('should start with initial state', function() {
    // given
    const raftStateMachine = new LocalRaftStateMachine({nodeId: 'host:port'});

    // when nothing

    // then
    assert.deepEqual(raftStateMachine.state, initialState);
});
```

Next:

```javascript
test('should transition from candidate to leader when received majority of votes', async function() {
});
```

This one is more complex.
We start a vote if a leader timed out,
bump current term, request votes from peers then count positive votes
and if there are more positive votes the node transitions to leader state.
The only tricky part in testing this is making sure the votes are positive,
every single time.
I'm going to use `testdouble` to mock `getVotes` and `sendAllHeartbeats` functions.

```javascript
test('should transition from candidate to leader when received majority of votes', async function() {
    // given
    const raftStateMachine = getStateMachineWithPeers();

    td.replace(raftStateMachine, 'getVotes', td.when(td.function()()).thenResolve([positiveVote, positiveVote, negativeVote]));
    td.replace(raftStateMachine, 'sendAllHeartbeats', td.function());

    // when
    await raftStateMachine.transitionToCandidate();

    // then
    assert.equal(raftStateMachine.state.role, roles.leader);
    assert.equal(raftStateMachine.state.currentTerm, 2);
});
```

And the implementation:
```javascript
   leaderTimedOut() {
        const now = new Date().getTime();
        const diff = Math.abs(now - this.state.lastHeartbeat);
        const result = diff > config.leaderTimeout

        return result;
    }

    async transitionToCandidate() {
        if (this.leaderTimedOut() && this.state.role !== roles.leader) {
            this.state.role = roles.candidate;
            this.state.currentTerm += 1;

            const votes = await this.getVotes();
            const positive = this.countPositiveVotes(votes);
            logger.log('received positive votes', positive);
            this.state.votesGranted = positive;

            if (positive > (this.state.peers.size / 2)) {
                this.transitionToLeader(); // (!)
            } else {
                this.resetLeaderTimeout(); // (!)
            }
        }
    }
```

I marked transition changes with (!) comment.

So far so good, now let's dig into something even more complex:


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

class RaftStateMachine {
    constructor({ nodeId }) {
        if (nodeId == undefined) {
            throw new Error('nodeId and peers must be defined, peers must be an array');
        }

        this.state = { ...emptyState, peers: new Set(), nodeId };
        this.alreadyVotedInThisTerm = false;
        this.resetLeaderTimeout();
    }
    // ...

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

    // ...
}
```

But it's kind of "janky"[*](http://jankfree.org/)...
Sometimes the test completes in milliseconds,
sometimes it runs for way longer...
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

Alright, we fixed that one, but it's not ideal.
Our tests take more time than they should and it's because we use real timers.

```
 PASS  state-machine/state-machine.test.js
  ✓ should start with initial state (4ms)
  ✓ should not transition to leader when can not get majority (38ms)
  ✓ should transition to candidate role when it did not receive a heartbeat (17ms)
  ✓ should send heartbeats when leader (1ms)
  ✓ should become follower when it gets heartbeat with higher term
  ✓ should become candidate when it does not get heartbeat from a leader for a long time (16ms)
  ✓ should start a second voting when first vote is unsuccessful (16ms)
  ✓ should cast a vote when not voted in this term (1ms)
  ✓ should not cast a vote when voted in this term
  ✓ should elect a leader (50ms)
  starting voting
    ✓ should transition from candidate to leader when recived majority of votes (1ms)
    ✓ should not transition from candidate to leader when recived less than majority of votes
```

Sum: ~144 ms

What can we do about it?
[Jest](https://jestjs.io/docs/en/timer-mocks) allows mocking timers and
we're going to use it.
The process is quite easy,
we have recursive timers so as documentation suggests,
so we're going to run `jest.runOnlyPendingTimers()`
to only advance the timers that are scheduled and not enter infinite loop.

In each test we replace calls to `sleep()` with `jest.runOnlyPendingTimers()`.
One tricky test is the last one that makes sure a leader is selected.
Simply running `runOnlyPendingTimers()` doesn't work
because `getVotes()` uses promises and
running timers is not enough because promises are handled by microtask queue in the event loop.

What we can do is run all pending timers,
that sets the nodes in candidate / voter phase,
replace mocked timers with real ones so we do not advance beyond that,
lastly we advance microtasks so that vote results come back to the leader.

After that cycle a leader should be selected.
We can run tests and see the results:

```
 PASS  state-machine/state-machine.test.js
  ✓ should start with initial state (3ms)
  ✓ should not transition to leader when can not get majority (1ms)
  ✓ should transition to candidate role when it did not receive a heartbeat (2ms)
  ✓ should transition from candidate to leader when recived majority of votes
  ✓ should not transition from candidate to leader when recived less than majority of votes (1ms)
  ✓ should send heartbeats when leader
  ✓ should become follower when it gets heartbeat with higher term
  ✓ should become candidate when it does not get heartbeat from a leader for a long time (1ms)
  ✓ should start a second voting when first vote is unsuccessful
  ✓ should cast a vote when not voted in this term (1ms)
  ✓ should not cast a vote when voted in this term
  ✓ should elect a leader (2ms)
```

Sum: ~11 ms

We improved our test time by a factor of 10 - that's pretty nice.

The rest of them is pretty much rinse & repeat.
One more thing that is quite cool is that I've abstracted a `LocalRaftStateMachine`
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
