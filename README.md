# Tootify 🦋→🐘

An experimental Bluesky-to-Mastodon cross-poster


## What does it do

Tootify will allow you to do a selective one-way sync of Bluesky posts to your Mastodon account.

The way it works lets you easily pick which skeets you want to turn into toots: it scans your recent posts and checks which of them you have liked yourself, and only those posts are reposted. The self-like is automatically removed afterwards.

Note: this is an early version so it might be a bit unstable and rough – but I've been using it for a few months and some other people have tried it too and it generally works.


## Installation

At the moment:

    git clone https://github.com/mackuba/tootify.git
    cd tootify
    bundle install

## Usage

First, log in to the two accounts:

    ./tootify login johnmastodon@example.com
    ./tootify login @alf.bsky.team

Press like on the post(s) on Bluesky that you want to be synced to Mastodon.

Then, you can either run the sync once:

    ./tootify check

Or run it continuously in a loop:

    ./tootify watch

By default it checks for new skeets every 60 seconds - use the `interval` parameter to customize the interval:

    ./tootify watch --interval=15


## Credits

Copyright © 2024 Kuba Suder ([@mackuba.eu](https://bsky.app/profile/mackuba.eu)).

The code is available under the terms of the [zlib license](https://choosealicense.com/licenses/zlib/) (permissive, similar to MIT).
