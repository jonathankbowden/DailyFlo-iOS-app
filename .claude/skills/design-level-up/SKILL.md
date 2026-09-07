---
name: design-level-up
description: "Level up any UI, landing page, prototype, mockup, or visual design Claude produces or reviews, using Anshu Chimala's Discover → Define → Deliver method (seed-string variety, ambitious direction-finding, an independent design-critic subagent scoring against studio quality, image/video enrichment, a restraint pass, and an AI-tell sweep). Use whenever the user asks to design, mock up, prototype, redesign, polish, or 'make it look better/premium/less AI' for a screen, page, artifact, canvas, or component — even if they don't say 'design'."
---

# Design Level-Up

Adapted from Anshu Chimala's "How to turn your AI into a world-class designer" (Lenny's Newsletter, Sep 2026; Chimala led AI R&D design/engineering teams at Apple for 12 years).

## Why this exists

You are a next-token predictor. Left alone, you make the safest, most probable choice at every step — the purple gradient, the text-left/image-right hero, the three-column feature grid, the glowing card. That is the *opposite* of great design, which needs emotional resonance and selective rule-breaking. Nobody asked for the median. This skill is a set of procedures that pull you off the median deliberately: inject variety you can't produce on your own, get critique from a separate agent that hasn't rationalized your choices, add texture code can't fake, then subtract until it's tasteful.

Run the three stages in order. Skip a technique only when it doesn't fit the medium (e.g. no video in a static Word doc), and say so.

---

## Stage 1 — DISCOVER: explore the space before you build

### 1a. Brainstorm directions, then let the human's taste steer

Before writing any markup, propose **8–12 one-line creative directions** — short and high-level, not detailed specs. Make at least a third of them sound like they shouldn't work ("radically asymmetric, dissonant type, uncomfortable negative space — break every rule but make it look good"; "each section is a still from a video game"; "an isometric living city where features are buildings"). Chimala's rule: *if you think "there's no way this will work," you're on the right track.* The bad-sounding ones are where the unique work lives.

If the user is present, use AskUserQuestion to have them pick 1–3 and describe their **emotional reaction** ("tactile, clicky, satisfying — but not cartoony or skeuomorphic, that feels tacky; needs more texture"). Refine with them once or twice, then convert the winner into a single ambitious build prompt and echo it back before building. When the user isn't around, pick the most distinctive direction that still fits the brief and state that choice up top.

Why: pasting AI-generated ideas straight back into AI converges. The human's reaction is the only source of genuine novelty in the loop — you supply execution, they supply taste.

### 1b. Seed-string variety

When you need several distinct options, or the brief is vague and you'd otherwise default to the template, run this procedure **per variant**:

1. Generate a long random alphanumeric string in the shell (`openssl rand -hex 24` or `head -c 32 /dev/urandom | base64`).
2. Derive the creative direction from it — palette, layout grammar, typography, motion, mood. Look past the surface: repeated characters, digit runs, letter clusters, anything that suggests a texture, an era, a material, a rhythm.
3. Write the derived direction down in one paragraph *before* coding, then execute it well.
4. Never reveal the string or the derivation in the design itself.

Why: asking yourself to "be random" doesn't work — you can only predict the likeliest token. An external random input forces different decisions at the branching points where you would otherwise always pick the same thing.

### 1c. Write ambitious prompts

Whether for yourself or a subagent, the build prompt should name a *specific, wild* aesthetic plus the constraint that it must still function. Weak: "modern, clean landing page." Strong: "a control-panel aesthetic — machined aluminum, embossed labels, clicky toggles with real travel and shadow — but every section is still readable as a landing page."

Keep a `design-prompts.md` in the project (create it if absent) and log prompts that **didn't** work too, with a note on why. Re-test them when a newer model arrives; what failed last quarter often works now.

---

## Stage 2 — DEFINE: deepen the direction

### 2a. Independent design critic (the core loop)

You cannot critique your own work objectively — you defend past decisions and can't zoom out. So spawn a **separate critic subagent** (Agent tool, general-purpose) that sees *only rendered screenshots*, never the code or your reasoning.

Render first: for HTML, screenshot with Playwright (`/opt/pw-browsers/chromium` is preinstalled in the cloud container) at desktop and mobile widths; for a design canvas or slide, export/screenshot each artboard. Save PNGs, then hand paths to the critic.

Critic prompt (paste, adapt the aesthetic line):

```
You are a design critic at a top-tier studio. You are seeing only screenshots; you have no access to code and no stake in prior decisions.

The design is going for: <one-line aesthetic from Stage 1>.

1. Name the aesthetic you actually perceive. If it differs from the intent, say so.
2. Imagine how the best studio in the world would execute this exact aesthetic. Outline the biggest gaps between that and what you see — both overall structure (hierarchy, rhythm, composition, negative space) and fine detail (type pairing, spacing consistency, alignment, color relationships, edge cases like long text).
3. Hunt for patterns that feel overdone, excessive, or obviously AI-generated (see the tells list) and penalize them hard.
4. Score /10 for distance from studio-level quality. Be opinionated, bold, and specific — no vague prose, no praise sandwiches. Each gap should be an actionable instruction a builder can execute.
5. End with: the three highest-leverage changes, in order.
```

Loop rules:
- Apply the critic's top changes, re-render, re-critique. Iterate until the score is **≥ 9/10** or until **three rounds** produce no score movement — then stop and report where it plateaued rather than spinning.
- Give the critic objective criteria and, when the user has them, reference images of the target quality bar. "Beautiful" is not a criterion; "consistent 8-pt spacing grid, ≤ 2 type families, one accent color" is.
- Model economy: the critic makes few, high-value calls (typically < 10% of tokens) — give it the strongest model available and let a cheaper/faster agent or yourself do implementation.

### 2b. Enrich with generated imagery

Code-only visuals — CSS gradients, blob shapes, emoji icons, dotted grid backgrounds — are the loudest "AI made this" signal. When the design has flat regions that want personality, use image generation for hero art, textures, icons with a consistent hand, and illustration.

- Only use an image/video API key the user has explicitly provided in this conversation; never guess credentials. If none is available, ask once, and fall back to hand-built SVG or curated CSS texture (noise, grain, paper) — still better than a gradient blob.
- Combine generated images with shaders, masks, blend modes, or subtle 3D transforms for depth rather than pasting a rectangle.
- Verify frame-by-frame in the browser after adding assets; broken or mis-cropped imagery is worse than none.

### 2c. Motion via video generation (advanced, optional)

For genuinely premium motion, video models beat hand-tuned CSS. Two patterns:
- **Animated graphic:** generate a looping clip on a solid background, remove the background with a video-matting model, layer it into the page. For glass/refraction, render over the page's actual background colors first so the refraction bakes in, then matte.
- **Fluid state transitions:** generate keyframe images for each state, use a video model to interpolate between them, seed each transition from the previous clip's last frame, and scrub playback on scroll or user action.

Use an aggregator (e.g. fal.ai) with the user's key so you can pick a current physics-consistent model without separate integrations. Skip entirely for docs, dashboards, or anything where motion doesn't serve the brief.

---

## Stage 3 — DELIVER: subtract until it's premium

### 3a. Restraint pass

AI adds; it rarely takes away. Overexplaining and purposeless decoration are the biggest giveaways. Before shipping, go element by element and ask *what happens if this is gone?* Remove:
- glows, ambient blurs, gradient backgrounds and borders that carry no meaning
- random colored highlights on words, gratuitous accent colors
- redundant labels, captions that restate the visual, "helper" text nobody asked for
- wrapper containers, cards-inside-cards, dividers doing nothing
- custom components that are worse than the platform-native one (use native controls on iOS/Android/macOS; respect platform conventions)

Putting less on screen communicates more — you hold attention instead of scattering it. A design that exercises restraint reads as premium immediately.

### 3b. AI-tell sweep

(Chimala's own list is paywalled; this is a compiled checklist — extend it in `design-prompts.md` as you find more.) Fix any of these before calling it done:

- Purple/indigo-to-pink gradient anything; glassmorphism cards with 1px white borders
- Hero: headline left, screenshot/mockup right, two pill buttons (one solid, one ghost)
- Three equal feature cards each with a rounded icon square in the corner
- Emoji or generic line icons used as "illustration"; sparkle ✨ motifs
- Inter/Poppins on everything; centered everything; identical section rhythm (heading → subhead → grid) repeated 5×
- Fake social proof: logo rows of unnamed companies, "Trusted by 10,000+ teams," round-number stats ("99.9%", "10x")
- Placeholder copy energy: "Unlock," "Seamlessly," "Supercharge," "Elevate," "in one place," em-dash-heavy taglines
- Dotted-grid or radial-gradient backgrounds; floating blurred blobs
- Uniform 16px border-radius on every element; shadows that don't match a light source
- Dark mode with #0f172a slate and neon accents; "AI" gradient text
- Everything animates on scroll with the same fade-up
- Perfectly symmetric, nothing overlaps, no element ever breaks the grid — no evidence a human made a choice

### 3c. Final check

- Real content, real edge cases (long names, empty states, wrapping) — not lorem ipsum
- Keyboard focus, contrast, and touch targets still hold after all the aesthetics
- Both light and dark themes if the surface supports them
- Re-screenshot and give it one last look at arm's length: does it look like *this* product, made by *this* person, or like the median of the internet?

---

## Reporting back

When you hand over, include in two or three sentences: the direction chosen (and why the others lost), the critic's starting and ending score, and what you removed in the restraint pass. Offer the runner-up direction as a one-line alternative if the user wants to see it built. Do not narrate every iteration.

## Quick mode

If the user just wants a fast polish of something that already exists ("make this look less AI"): skip Stage 1, render, run one critic round, do 3a + 3b, ship. Say that's what you did.
