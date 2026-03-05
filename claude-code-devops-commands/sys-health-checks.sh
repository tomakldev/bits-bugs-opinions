#!/usr/bin/env bash
# Quick system health check (all run in parallel)

df -h /                                          # disk
free -h                                          # memory
uptime                                           # load average
docker ps | grep trigger                         # containers
docker ps --filter "health=unhealthy"            # anything broken
ss -tlnp | grep -E ':(80|443|3000|5432|8080)'   # key ports
