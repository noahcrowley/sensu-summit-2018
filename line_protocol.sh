#!/bin/sh

printf "randoms value=$(cat /dev/urandom | tr -dc '0-9' | fold -w 2 | head -n 1) $(date +%s)000000000\n"