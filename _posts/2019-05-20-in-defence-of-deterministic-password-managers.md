---
title: "In defence of deterministic password managers"
layout: post
date: 2019-05-20 13:00
tag:
- password
- passwords
- password manager
- deterministic password manager
- stateless password manager
star: true
category: blog
author: slonka
description: I'll take a look at the 4 fatal flaws in deterministic password managers as highlighted by Tony Arcieri and try to mount some defense against it.
published: false
---

## Intro

This is a response to Tony Arcieri's blog post
https://tonyarcieri.com/4-fatal-flaws-in-deterministic-password-managers

### My assumptions

The password manager must have the following features:
1. Ability to define arbitrary website / application name
1. Counter to be able to have multiple passwords for one entity
1. A "login" field which can be any string
1. The generated password is based on: `website name` + `counter` + `login`

### 1. Deterministic password generators cannot accommodate varying password policies without keeping state

This is true but I have ~250 passwords saved
and only a handful of them impose limitations
that prevent using the default (strongest) password generated from the manager.
This is a bad practice
and should be fix at the level of the application / website.
If I do not remember that this website requires a different type of password
it will take me 1-2 tries to go down the list of password types and pick the right one
if I'm not using my device that has that state saved.

### 2. Deterministic password generators cannot handle revocation of exposed passwords without keeping state

That one is also true,
when the password is revoked I bump the "counter" and move on.
When I lose the state I have go increment the counter
until I discover that this one is the right one.
It's not a big problem.

If the system you are using requires periodical changes you can make up a pattern to
track counters.
If it is on a monthly basis it can be 1**2019**
meaning that this is a password for January 2019.

"There are many ways we could accidentally expose the password for a specific site: accidentally copying and pasting it into an email, IM, or social media. This is a fairly routine occurrence that happens to the best of us." - I've never done that so I can't relate.
If you're sending things into the open without checking first
you have larger problems than password managers.

### 3. Deterministic password managers can’t store existing secrets
``` image showing a cat and a popup saying "my name is <complex password> ```

That is partially true but for things like "randomly selected answers to security questions" you can use the "login" feature.
Let's say `website.com` asks you the name of your childhood pet,
you can be like me and put in your password manager:

webiste: `website.com`
login: `pet_name`

I know that the security questions differ from website to website
so I discourage using them and use a different form of two factor authentication.

### 4. Exposure of the master password alone exposes all of your site passwords

Not necessarily.
Let's look at it from a perspective of a password manager like the one in Google Chrome.
If someone gains access to your account it's game over,
because the passwords **have** to be stored with the site name / app name
for the **autocomplete** function to work.
If you ditch the autocomplete function
you can define your own scheme for storing the site name.

For example a password for `subdomain.website.com` can become `com_website_subdomain`.
This state is not stored on any device - simply in your head.

If the attacker gains access to your master password,
now he has to also brute force the mechanism.

## Isn't this all a bit complicated?
