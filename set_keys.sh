#!/usr/bin/bash
dos2unix.exe .env
set -o allexport
source .env
set +o allexport