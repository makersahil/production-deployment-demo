# Monitoring

## Purpose

This deployment uses lightweight operational checks suitable for a small application.

The goal is to answer four questions:

1. Is it reachable?
2. Is it healthy?
3. Is it degrading?
4. If it failed, can I diagnose why?

---

## HTTP Uptime

Check the public application endpoint:

```bash
curl -I http://localhost/
