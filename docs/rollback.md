# Rollback Procedure

## Purpose

This runbook describes how to return the application to a previous known-good release when a deployment introduces a failure.

Application rollback and database rollback must be treated separately.

---

## Trigger

Consider rollback when a newly deployed release causes one or more of the following:

- `/health/` fails
- application returns repeated HTTP 5xx responses
- application containers repeatedly crash
- critical application functionality stops working
- migrations fail
- logs show a release-specific fatal error
- deployment introduces unacceptable instability

Rollback should not be the first reaction to every minor issue.

If the problem can be corrected safely and quickly without increasing risk, a forward fix may be preferable.

---

## Pre-checks

Before rolling back:

1. Identify the currently deployed commit.

```bash
git rev-parse --short HEAD
