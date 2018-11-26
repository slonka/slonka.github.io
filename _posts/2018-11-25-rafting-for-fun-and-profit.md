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

```javascript
const http = require('http');
const _ = require('koa-route');
const Koa = require('koa');
const bodyParser = require('koa-bodyparser');
const request = require('request-promise-native');

const environment = process.env.ENVIRONMENT;

const peersPath = environment === 'test' ? 'peers-test' : 'peers-prod';

const {
    peers,
    ipPortToName
} = require(`./${peersPath}`);

const {
    getPeersWithoutMe,
} = require('./peers-utils');

const app = new Koa();
app.use(bodyParser());

const HOST = process.env.HOST;
const PORT = process.env.PORT;
const nodeId = `${HOST}:${PORT}`;

const roles = {
    follower: 'follower',
    leader: 'leader',
    candidate: 'candidate',
};

const REQUEST_TIMEOUT = 500;
const HEARTBEAT_INTERVAL = 3000;
const LEADER_TIMEOUT = 4000;
const LEADER_TIMEOUT_SPRED = 200;

let role = 'follower';
let lastHeartbeat = null;
let votesGranted = 0;
let currentTerm = 0;
let votedFor = null;
let leaderTimeout;

async function requestVoteFromPeers() {

    console.log('requesting vote from peers');
    const peersWithoutMe = getPeersWithoutMe(peers, nodeId);
    votedFor = nodeId;

    const responses = await Promise.all(peersWithoutMe.map(p => request.post({
        url: `http://${p}/raft/request-vote`,
        json: {
            term: currentTerm,
            candidateId: nodeId
        },
        timeout: REQUEST_TIMEOUT,
        resolveWithFullResponse: true
    })).map(p => p.catch(e => e)));

    const positiveVotes = responses.map((r, index) => {
        if (r.statusCode === 200) {
            return r.body.voteGranted === true && r.body.term === currentTerm;
        } else {
            console.log('got not valid response from', ipPortToName[peers[index]]);
            return false;
        }
    }).reduce((prev, current) => prev + (current === true ? 1 : 0), 1);

    votesGranted = positiveVotes;

    return positiveVotes;
}

async function sendHeartBeat() {
    if (role === roles.leader) {
        const peersWithoutMe = getPeersWithoutMe(peers, nodeId);
        const responses = await Promise.all(peersWithoutMe.map(p => request.post({
            url: `http://${p}/raft/append-entries`,
            json: {
                term: currentTerm,
            },
            timeout: REQUEST_TIMEOUT,
            resolveWithFullResponse: true
        })).map(p => p.catch(e => e)));

        // am I still the leader?
        const stillLeader = responses.every(r => {
            if (r.statusCode === 200) {
                return r.body.term === currentTerm;
            } else if (r.statusCode !== 200) {
                return true;
            } else {
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

function checkLeaderTimedOut() {
    const now = new Date().getTime();
    const diff = Math.abs(now - lastHeartbeat);

    return diff > LEADER_TIMEOUT;
}

function resetLeaderTimeout() {
    clearTimeout(leaderTimeout);
    leaderTimeout = setTimeout(startLeaderTimeout, LEADER_TIMEOUT + (LEADER_TIMEOUT_SPRED * Math.random()));
}

async function startLeaderTimeout() {
    if ((role === roles.follower || role === roles.candidate) && votedFor === null && checkLeaderTimedOut()) {
        currentTerm += 1;

        role = roles.candidate;
        const positiveVotes = await requestVoteFromPeers();

        if (votedFor === nodeId && positiveVotes > peers.length / 2) {
            role = roles.leader;
            console.log(nodeId, 'became a leader');
            currentTerm += 1;
            await sendHeartBeat();
        } else {
            console.log('startLeaderTimeout: retrying');
            resetLeaderTimeout();
        }
        votedFor = null;
    }
}

leaderTimeout = setTimeout(startLeaderTimeout, LEADER_TIMEOUT + (LEADER_TIMEOUT_SPRED * Math.random()));

function state(ctx) {
    ctx.response.set('Access-Control-Allow-Origin', '*');

    ctx.body = {
        currentTerm,
        lastHeartbeat,
        peers: getPeersWithoutMe(peers, nodeId),
        role,
        nodeId,
        votedFor,
        votesGranted,
    }
}

function appendEntries(ctx) {
    lastHeartbeat = new Date().getTime();

    const messageTerm = parseInt(ctx.request.body.term, 10);
    console.log(new Date(), 'got heartbeat from', ipPortToName[ctx.ip] || ctx.ip, 'with term', messageTerm);

    if (messageTerm >= currentTerm) {
        currentTerm = messageTerm;
        role = roles.follower;
        votesGranted = null;
    }

    resetLeaderTimeout();

    votedFor = null;
    votesGranted = 0;

    ctx.body = {
        term: currentTerm,
        "success": true
    }
}

function requestVote(ctx) {
    const candidateId = ctx.request.body.candidateId;
    const term = ctx.request.body.term;
    console.log('got request to vote for', ipPortToName[candidateId] || candidateId, 'term', term, 'currentTerm', currentTerm, 'votedFor', votedFor);

    if (role === roles.leader) {
        ctx.response.body = {
            term: currentTerm,
            voteGranted: false
        };
    } else if (term === currentTerm && votedFor !== null) {
        ctx.response.body = {
            term: currentTerm,
            voteGranted: false
        };
    } else if (term > currentTerm) {
        console.log('voting for', ipPortToName[candidateId] || candidateId);
        votedFor = candidateId;
        currentTerm = term;
        role = roles.follower;
        votesGranted = null;
        resetLeaderTimeout();

        ctx.response.body = {
            term: currentTerm,
            voteGranted: true
        };
        currentTerm = term;
    } else {
        ctx.response.body = {
            term: currentTerm,
            voteGranted: false
        };
    }
}

app.use(_.get('/raft/state', state));
app.use(_.post('/raft/append-entries', appendEntries));
app.use(_.post('/raft/request-vote', requestVote));

http.createServer(app.callback())
    .listen(PORT, HOST);

console.log(`listening on port http://${HOST}:${PORT}`);
```

