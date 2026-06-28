---
name: text-humanizer
version: 1.0.0
description: |
  Remove signs of AI-generated writing from text. Use proactively whenever
  reviewing or editing text that may contain AI patterns, even if the user
  doesn't explicitly ask for humanization. Trigger when: text uses words like
  "delve", "crucial", "landscape", "tapestry", "testament", "foster",
  "enhance", "pivotal", "showcase", "underscore", "vibrant"; text has em dash
  overuse; text uses "Not only...but...", "serves as", "stands as"; text has
  mechanical boldface lists or Title Case headings; or the user says "make this
  sound natural", "remove AI patterns", "humanize this", "this sounds robotic".
allowed-tools: Read, Grep, Bash
---

# Text humanizer

Make text sound like a real person wrote it. The goal is not to dumb it down
but to remove the algorithmic patterns that make AI-generated text recognizable.

## Why this matters

AI-written text has identifiable patterns that erode trust. Readers (and
increasingly, automated detectors) notice these patterns. The fix is simple:
use natural language instead of inflated constructions.

## Detection checklist

Read the text and flag any of these patterns:

1. **Banned vocabulary**: delve, crucial, enhance, foster, garner, interplay,
   intricate, landscape (abstract), pivotal, showcase, tapestry (abstract),
   testament, underscore (verb), vibrant
2. **Significance inflation**: "serves as", "stands as", "vital role",
   "marking a pivotal moment", "setting the stage for"
3. **Promotional language**: "boasts a", "groundbreaking", "breathtaking",
   "commitment to"
4. **Superficial -ing clauses**: "highlighting...", "underscoring...",
   "ensuring...", "reflecting..."
5. **Em dashes**: replace with commas or periods
6. **Forced rule of three**: don't group ideas in threes artificially
7. **Negative parallelisms**: "Not only...but...", "It's not just about..."
8. **Copula avoidance**: replace "serves as", "stands as" with "is"/"are"
9. **Filler**: "In order to", "It is important to note that"
10. **Sycophancy**: "Great question!", "Certainly!"

## Rewrite principles

- Use simple words: "fix" not "remediate", "check" not "ascertain"
- Use "is"/"are"/"has" directly, don't avoid copulas
- Vary sentence length, mix short and medium
- Use contractions where natural (we've, it's, don't)
- Have a voice, opinions, mixed feelings
- Let some imperfection in. Perfect structure feels algorithmic.
- Sentence case headings, not Title Case
- Straight quotes, not curly
- No emojis in headings or bullet points

## After rewriting

Show the final version directly, then copy to clipboard:
```bash
/home/tomakl/projects/scripts/clip "<final text>"
```
