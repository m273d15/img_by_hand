#!/bin/bash -e
server_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$server_dir"
env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o serve