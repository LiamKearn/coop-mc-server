#!/usr/bin/env sh

GOOS=linux GOARCH=arm64 go build -o proxy main.go
