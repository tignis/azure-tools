# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A collection of utility scripts for Azure and Microsoft Graph administration tasks.

## Structure

- `scripts/bash/` — Bash scripts for Azure/Graph operations (require `az` CLI, `jq`)

## Conventions

- Bash scripts use `set -euo pipefail` and include usage/help text in a header comment
- Scripts resolve Microsoft Graph identifiers dynamically rather than hardcoding role IDs
- Error handling tracks failures per-item and exits non-zero if any operation failed
