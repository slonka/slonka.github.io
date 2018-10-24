---
title: "Node DIY part 1 - Distributed tracing"
layout: post
date: 2018-10-19 20:00
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
takes traveling through every part of your system.

![request tracing](/assets/images/2018-10-19-node-diy-distributed-tracing/distributed-tracing.png)

When I first tried out [newrelic](https://docs.newrelic.com/docs/apm/distributed-tracing/getting-started/introduction-distributed-tracing)
I was curious how they were able to trace all of the interactions between my services
and all it took was one function call in the application entry point.

## Communication

I knew that the tracing information must be kept somewhere in the HTTP request.
There is no side channel, because the library works across closed environments (different machines, vms, containers).
So I've setup a small two app example with newrelic running on it.
Made a request from one service to another and checked out the output.

![newrelic transaction headers](/assets/images/2018-10-19-node-diy-distributed-tracing/newrelic-transaction-headers.png)

And there it is: `x-newrelic-id` and `x-newrelic-transaction`.
Ok, that means that we need some way to propagate those headers and make sure we do not mix them up.

## Part 1 - Shimming

Node.js has a method that is called every time there is an event associated with a server (for example a request comes in)
and there is another method that is called when we create an outgoing connection.
They are `http.Server.emit` and `http.request` respectively.
Our goal is to change them so that we can add our own custom headers there.

JavaScript being a language that is easily extensible,
you can replace built-in functions by simply assigning a new function to them.
This is quite awesome but you have to be extremely careful not to screw things up.

The term to describe such modifications is [shimming](https://en.wikipedia.org/wiki/Shim_(computing)).

Ok so let's try and implement a basic shimmer:

```js
function wrap(nodule, name, wrapper) {
  const original = nodule[name];
  const wrapped = wrapper(original);
  nodule[name] = wrapped;
}
```

Just 3 lines, we get the original function, wrap it in a wrapper, and replace it.
That simple.

## Part 2 - unique identifiers

We need some way to distinguish between requests - this is a short implementation of uuid v4
taken from [stackoverflow](https://stackoverflow.com/a/2117523):

```js
const crypto = require('crypto');
const pattern = `${1e7}-${1e3}-${4e3}-${8e3}-${1e11}`;

function uuidv4() {
  return pattern.replace(
    /[018]/g,
    c => (c ^ crypto.randomBytes(1)[0] & 15 >> c / 4).toString(16)
  );
}
```

Nothing fancy, just random bits.

## Part 3 - naive approach

So far we know how to inject our custom headers with some unique identifier,
but how do we know keep track of the headers when we have multiple requests comming through?

A naive implementation might look something like this:

```js
let uuid;

wrap(http.Server.prototype, 'emit', function (original) {
  return function (event, incomingMessage, serverResponse) {
    let returned;
    if (event === 'request') {
      if (incomingMessage.headers[PROPAGATE_HEADER_NAME]) {
        uuid = incomingMessage.headers[PROPAGATE_HEADER_NAME];
      } else {
        uuid = uuidv4();
      }
      serverResponse.setHeader(PROPAGATE_HEADER_NAME, uuid);
      returned = original.apply(this, arguments);
    } else {
      returned = original.apply(this, arguments);
    }
    return returned;
  };
});

wrap(http, 'request', function (original) {
  return function (options) {
    options.headers = options.headers || {};
    options.headers[PROPAGATE_HEADER_NAME] = uuid;
    return original.apply(this, arguments);
  };
});
```

What's wrong with this? We wrap the `emit` function, assign a uuid or propagate the header.
When we create an outgoing connection we assign the uuid we created before to the new request.
And there is the bug, if we create a request before the response from the previous one comes in
we overwrite the value.

How can we solve this?

We need some mechanism that is aware of the execution context.

## Part 4 - async hooks


