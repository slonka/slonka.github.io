#!/usr/bin/env bash

find ./ -type f -name '*.png' -exec sh -c 'cwebp -q 75 $1 -o "${1%.png}.webp"' _ {} \;
