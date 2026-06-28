---
name: code-optimizer
version: 1.0.0
description: |
  Analyze and optimize code performance. Use proactively when the user asks to
  speed up code, reduce memory usage, fix slow queries, find bottlenecks, or
  improve bundle size. Also trigger when the user mentions "this is slow",
  "performance issues", "takes too long", "out of memory", "N+1 queries",
  "optimize", or shares code asking "how can I make this faster". Covers
  algorithmic complexity, memory leaks, I/O patterns, and database queries.
allowed-tools: Read, Grep, Glob, Bash, Edit
---

# Code optimizer

Analyze code for performance issues and suggest concrete fixes.

## Analysis categories

Each category targets a different bottleneck type. Check all of them, but focus
on whichever is most likely given the code's domain (data processing = complexity,
web API = I/O, ORM-heavy = database).

### Complexity (CPU-bound)
O(n^2) loops, unnecessary iterations, redundant operations. A nested loop over
1000 items does 1M operations. Look for `.includes()` inside `.filter()`,
nested `for` loops over the same data, or repeated array scans.

**Fix pattern:** Replace array lookups with Set/Map, precompute indexes, use
sorting + binary search for repeated lookups.

### Memory (GC pressure, OOM)
Large allocations, memory leaks, unbounded arrays/maps. Closures holding
references, event listeners never removed, growing caches without eviction.

**Fix pattern:** Use WeakMap/WeakRef, add TTL to caches, stream large files
instead of loading into memory, use generators for large datasets.

### I/O (latency-bound)
Blocking calls, missing caching, sequential fetches that could be parallel.
I/O is 100-1000x slower than computation. This is usually the biggest real-world
win.

**Fix pattern:** `Promise.all()` for independent fetches, add response caching,
use connection pooling, batch API calls.

### Bundle size (frontend)
Unused imports, heavy dependencies where lighter alternatives exist.

**Fix pattern:** Tree-shake imports (`import { map } from 'lodash-es'` not
`import _ from 'lodash'`), use native APIs when available, lazy-load heavy
modules.

### Database (query-bound)
N+1 queries, missing indexes, full table scans, `SELECT *` when only 2
columns are needed.

**Fix pattern:** Use eager loading/joins, add indexes on WHERE/ORDER BY
columns, select only needed columns, use EXPLAIN ANALYZE.

## Output format

For each finding:
1. What the problem is and why it matters (with rough magnitude)
2. Before/after code showing the fix
3. Expected impact (e.g., "O(n^2) -> O(n), ~100x faster for 1000 items")

Wait for user approval before applying changes.
