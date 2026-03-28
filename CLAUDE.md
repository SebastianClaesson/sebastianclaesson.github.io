# CLAUDE.md

## Project
Static blog hosted on GitHub Pages at blog.sebastianclaesson.se. Pure HTML/CSS/JS, no framework, no build step.

## Structure
- `index.html` - Home page with post listing, search, category filter
- `about.html` - About page
- `posts/` - Blog posts as individual HTML files
- `drafts/` - Draft posts (shown on index with `?drafts=true`)
- `css/style.css` - All styling, dark/light mode
- `js/main.js` - Search, filtering, theme toggle, draft visibility
- `assets/images/` - All images and avatars

## Adding a new post
1. Create HTML file in `posts/` (or `drafts/` for drafts)
2. Copy header/nav/footer structure from an existing post
3. Add a card to `index.html` in date order (newest first)
4. For drafts: add `class="draft-post"` and `style="display:none;"` to the card, with a DRAFT badge
5. Update `sitemap.xml` with the new URL

## Nav bar consistency
Every page must have the same nav icons: GitHub, LinkedIn, Twitter/X, Uppsala Azure User Group, theme toggle. When adding new pages, copy the full nav from an existing page.

## Style rules
- No em-dashes in blog content. Use periods, commas, or colons instead.
- No dashes in post descriptions on index.html.
- Dark mode should be soft dark (#181a24 range), not near-black.
- All hover states use accent blue consistently.
- Light mode: nav icons, links, and category buttons should be black (#1a1d2e), not grey.
- All pages must have `<meta name="viewport" content="width=device-width, initial-scale=1.0">`.
- All pages must include Google Analytics (G-LQDR23C4VN).
- Footer year: 2026. No taglines.
- Swedish characters must be correct UTF-8 (Bjorn -> Bjorn, Vasteras -> Vasteras, etc.).
- Avatar in nav bar and about page only, not hero sections.

## Commits
- Do not include Claude as co-author in commit messages.

## Deployment
- Push to `main` triggers GitHub Actions workflow (`.github/workflows/pages-deploy.yml`)
- Workflow uploads static files directly, no build step
- `.nojekyll` file prevents GitHub Pages from processing with Jekyll
- Pages source must be set to "GitHub Actions" in repo settings
