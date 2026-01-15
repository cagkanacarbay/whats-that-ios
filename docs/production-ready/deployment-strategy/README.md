# Deployment Strategy Guide

This folder contains documentation for safely deploying changes to the What's That app in production.

## Documents

| Document | Description |
|----------|-------------|
| [environments.md](./environments.md) | Development vs Production environment setup (Hybrid Approach) |
| [database-changes.md](./database-changes.md) | Safe database schema migration patterns |
| [edge-functions.md](./edge-functions.md) | Edge function change strategy (backwards compatible updates) |
| [deployment-checklist.md](./deployment-checklist.md) | Step-by-step safe deployment process |

## Core Principles

1. **Backend changes go first, app changes go second** - Never deploy an app that requires a backend change that hasn't happened yet.

2. **All changes must be backwards compatible** - Users on old app versions must continue to work after you deploy backend changes.

3. **Dev environment is for building confidence** - It can't replicate production perfectly, but it catches most issues.

4. **Monitor after every deploy** - Watch logs for errors from old/new clients.

## Quick Reference

```
Development Flow:
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Develop   │ --> │    Test     │ --> │   Deploy    │
│   on Dev    │     │  on Dev DB  │     │  to Prod    │
└─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              v
                                    ┌─────────────────┐
                                    │ Backend first,  │
                                    │ then app update │
                                    └─────────────────┘
```
