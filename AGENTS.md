# AGENTS.md

This document describes the project for developers and AI agents working on this codebase.

## Project Overview

**Гласот на езерото** ("The Voice of the Lake", formerly Lihnid/Лихнид — internal ids and storage keys still use `lihnid`) is a GPS-triggered audio guide for boat tours on Lake Ohrid (North Macedonia). A phone or tablet on the boat tracks its position; when the boat enters a stop's geofence (Ohrid harbour, St. John at Kaneo, Villa Biljana (Tito's villa), open lake, Mount Galičica, Peštani, Bay of Bones, Trpejca, Zaum, St. Naum) the story for that stop is spoken automatically with the browser's Web Speech API, in one or more languages in a chosen order (Macedonian, English, Serbian/Croatian, Polish, Turkish, German) so mixed groups on one boat each hear their language. Zones have no fixed order: the tour can start anywhere, each zone tells its story once when the boat enters it, and "next stop" is the nearest zone not heard yet. There is no demo/simulation mode and no route line on the maps: the tour runs only on the device's GPS, and the maps show only the stop zones and the boat.

It is a mobile-first web app / installable PWA with no user accounts. Tour content is bundled; only stop positions/radii can be overridden from the password-protected `/admin` page (stored in Netlify Database). **The interface is Macedonian only**; only the narration languages are selectable.

### Product-specific architecture

- `src/data/tour.ts` — **all tour content**: languages (with speech voice fallbacks), stops (lat/lng, geofence radius, localized name/subtitle/story). Zone centres are placed on the water along the route so the boat passes through them. To add a language: extend the `Lang` union, add to `LANGUAGES`, add the key to every `Localized` record and to `src/lib/i18n.ts` (TypeScript enforces completeness via `satisfies`).
- **Stop position overrides** — `/admin` (`src/routes/admin.tsx`, map in `src/components/admin-stops-map.tsx`) edits each stop's lat/lng/radius (drag/resize circle, typed values, or device GPS). Saved via server functions in `src/lib/stops.functions.ts` (shared password from the `ADMIN_PASSWORD` env var) into the `stop_positions` table. (The `tour_route` table from an earlier migration is unused, kept because applied migrations are immutable) (`db/schema.ts`, Drizzle; migrations in `netlify/database/migrations/`, generate with `npx drizzle-kit generate --name <name>`). The root loader fetches them and `StopsProvider` (`src/lib/stops-context.tsx`) merges them over `STOPS` and caches them in localStorage for offline use. **Components must read stops with `useStops()`, not the static `STOPS`** (story text can still come from `STOPS`). Stops without a row use the bundled defaults.
- **Boat extra zones** — a boat's admin (`/b/<code>/admin`, "Локации и радиуси") can add up to 5 own zones (`MAX_EXTRA_STOPS`). They use the reserved ids `extra-1`…`extra-5` (`src/lib/stop-positions.ts`): a zone exists when the boat has a `boat_stop_positions` row for that id; its name/subtitle/stories are ordinary `boat_texts` keys (`stop:extra-N:…`), edited in "Текстови на точките". Server fns `addBoatStop`/`deleteBoatStop`; boat reset keeps extras; the shared layer ignores extra ids. `mergeStops` appends them after the bundled stops. Empty stories are skipped by the narrator.
- **Music player** — `src/components/music-player.tsx` on the live tour: an online-radio link or audio files from the device. While the narrator is busy the music fades out completely and is muted (on iOS, where page volume is read-only, it pauses and resumes). Before the first language of each zone the narrator waits ~1 s for the fade, then plays an attention chime (`src/lib/chime.ts`, Web Audio, three bell tones, unlocked in `unlock()`), then speaks; further languages of the same zone follow without a chime. Users normally paste the radio's **web page** address: links that don't look like a stream (`looksLikeStream` in `src/lib/stream-hints.ts`) are resolved first by `resolveStreamUrl` (`src/lib/music.functions.ts` → `src/lib/stream-resolver.ts`): scans the page, its embedded player iframes and .pls/.m3u links, keeps URLs that really answer with audio, else looks the station up in the free Radio Browser directory (country from the TLD, matched on homepage host or name). Candidates are tried in order; http-only streams play through the edge function `netlify/edge-functions/radio-proxy.ts` (`/radio-proxy?url=`, http audio from public hosts only). Link and volume are saved in localStorage.
- `src/lib/i18n.ts` + `src/lib/ui-lang.tsx` — Macedonian interface strings, read via `useUiLang().t(key)`. Stop `name`/`subtitle` are plain Macedonian strings; only `story` is localized per narration language. The `sr` language is labelled "Срп/Хрв": its stories are written in Croatian (Latin) and spoken with a Croatian voice (`hr-HR`, fallbacks bs/sr); the code stays `sr` so saved choices keep working.
- **Microsoft neural voices on every device** — the narrator plays each sentence as an MP3 of the language's Microsoft neural voice (`cloudVoice` in `LANGUAGES`, e.g. `mk-MK-MarijaNeural`; the same voices as Edge's "Read aloud"), so Chrome/Safari/Android/iPhone sound like Edge. `GET /api/tts?v=1&lang=&text=` (`src/routes/api.tts.ts` → `src/lib/tts.server.ts`) synthesises with the unofficial Edge Read Aloud service via `msedge-tts` and stores the MP3 in Netlify Blobs (store `tts-audio`, key = voice + sha256 of the exact text), so an edited story automatically gets new audio for changed sentences only; responses are cached forever by CDN/browser (URL contains the text). Only sentences that occur in some story (bundled, `content_texts`, `boat_texts` with boat names filled in) are synthesised, others get 422. Client: `src/lib/cloud-voice.ts` (Cache Storage `lihnid-tts-v1` for offline; `narrator.prepare(langs)` downloads all stories of the chosen languages at tour start; one `<audio>` element unlocked with a silent WAV in `unlock()`). If a sentence can't be loaded the device Web Speech voice reads it, else text-only. Bump `TTS_VERSION` (server and client) to re-record everything after changing voices/rate. The admin "listen" buttons use the same voice (unsaved drafts fall back to the device voice).
- After the last language of a zone the narrator plays a closing chime (`playChime('end')`, the same bells falling) and only then reports not busy, so the music fades back in after it.
- `src/lib/use-narrator.ts` — sequential narration queue (device-voice backup path described here). Stories are split into sentences and spoken one utterance at a time (works around Chrome's ~15 s utterance cut-off and makes pause/resume reliable — pause = cancel + resume from current sentence). Among matching voices the most natural-sounding (neural/online/enhanced/Google/Microsoft) is preferred. If a device has no voice for a language it tries fallbacks (Macedonian → Serbian/Bulgarian/Croatian/Bosnian, never Russian; browsers/phones ship no Macedonian TTS voice and the AI Gateway has no TTS model, so a true Macedonian voice would need an external TTS service such as Azure Speech `mk-MK`), else shows text-only with a reading-time timer. `unlock()` must be called from a user gesture (iOS).
- `src/lib/use-tour-engine.ts` — position source (`navigator.geolocation.watchPosition`), geofence detection (each stop triggers once per tour), screen wake lock.
- `src/components/passenger-map.tsx` + `google-tour-map.tsx` — passenger display: Google Maps (hybrid, Macedonian labels) with live boat marker (heading arrow), zones, follow-the-boat, all-stops overview and fullscreen mode, plus nearest stop and coordinates. The browser key is read server-side from `VITE_GOOGLE_MAPS_API_KEY` and served at runtime by `src/routes/api.maps-key.ts` (never reference it via `import.meta.env` — inlining it fails Netlify secret scanning). Loader: `src/lib/google-maps.ts`.
- `src/components/tour-conditions.tsx` — two panels under the map on the live tour: current weather at the boat (temperature, sky, wind speed/direction/gusts from Open-Meteo, keyless, refreshed every 10 min or after ~3 km) and boat speed in km/h (and knots) from GPS `coords.speed`, or computed from successive fixes when the device doesn't report it; smoothed. `Position` carries `speed` and `at` for this.
- `src/components/leaflet-tour-map.tsx` (passenger) and `leaflet-admin-map.tsx` (admin, drag the numbered marker; radius via slider) — keyless interactive Leaflet maps (Esri satellite + labels, OSM street layer) used automatically when Google Maps can't load. `api.maps-key.ts` only returns keys matching Google's `AIza…` format, so an invalid key skips straight to Leaflet without a Google error.
- `src/components/tour-map.tsx` — last-resort static fallback if Leaflet also fails; dependency-free map: OpenStreetMap tiles at fixed zoom 12 rendered as `<image>` inside one SVG in Web-Mercator world-pixel coordinates, with zones and boat overlaid. Attribution must stay visible.
- **Login first**: `src/routes/index.tsx` (`/`) renders `HomeLogin` (`src/components/home-login.tsx`). Username = boat code + boat password → `/b/<code>` (the boat's tour; its password is put in the boat's admin session so `/b/<code>/admin` is already unlocked). Username `admin` + `ADMIN_PASSWORD` → `/tour` (the shared tour, `src/routes/tour.tsx`, only with the main admin session, otherwise redirects to `/`), which has an "Админ страна" button to `/admin` (main admin; edits there are the shared layer for every boat; its header has "Кон турата" back). Server fn `login` in `src/lib/stops.functions.ts`; the code `admin` is reserved and can't be used for a boat. On boat pages the "edit" link and the header logo stay inside `/b/<code>`, never `/admin`.
- **Device limit per boat** — `boats.max_devices` (set by the main admin when creating/editing a boat, "Број на уреди") caps how many devices can use a boat account. A boat login (`login` in `src/lib/stops.functions.ts`) registers the browser in `boat_devices` (random token in the httpOnly cookie `lihnid_dev_<code>`, only its sha256 stored, label from the User-Agent) or refuses with `device-limit` when all slots are taken; logging in again on a registered device reuses its slot. `/b/<code>/` (`src/routes/b.$boat.index.tsx`) `beforeLoad` calls `checkBoatDevice` and sends unregistered/logged-out devices to `/?boat=<code>&reason=…`; the main admin's tab password bypasses it; a network failure skips the check (offline on the lake). The main admin sees devices per boat ("Најавени уреди", `removeBoatDevices`) and can log out one or all; lowering the limit logs out the least recently used devices. `/b/<code>/admin` itself is not device-limited (password only). Every logged-in page has "Одјави се" at the top (`src/components/logout-button.tsx`, in `SiteHeader` and on the tour setup screen): on boat pages it calls `logoutBoatDevice` (deletes this device's row + cookie, freeing the slot) and clears the tab sessions, then reloads to `/`. The boat's own admin has a "Уреди" tab (`src/components/admin-own-devices.tsx`, `listOwnBoatDevices`; `removeBoatDevices` accepts the boat password too) to log out any of its devices, with "Овој уред" marked.
- `/b/<code>/` renders `TourApp` from `src/components/tour-app.tsx`: there is no separate landing page — the home page is directly the setup screen (hero photo background, large centred logo + "Гласот на езерото" + slogan "Езерото што ги раскажува своите приказни" as the h1, language selection + order, GPS readiness card) and then the live GPS tour. `src/lib/use-gps-check.ts` checks GPS before the tour (auto when permission already granted, otherwise a "Вклучи GPS" tap); the "Тргни" button stays disabled until it reports `ready` and its fresh fix is passed to `tour.start(initial)` so the map has the boat immediately.
- Images in `public/img/` were AI-generated; always reference them through the Netlify Image CDN (`/.netlify/images?url=/img/...&w=...&fm=webp`).
- Brand colours (`--lake-deep`, `--lake`, `--lake-light`, `--terracotta`, `--cream`, `--ink`) and fonts (Cormorant Garamond headings, Manrope body — both Cyrillic-capable) are in `src/styles.css`, exposed as Tailwind classes like `bg-lake-deep`, `text-terracotta`.

### Tech Stack

| Layer         | Technology                                          |
| ------------- | --------------------------------------------------- |
| Framework     | TanStack Start                                      |
| Frontend      | React 19, TanStack Router                           |
| Build         | Vite 8                                              |
| Styling       | Tailwind CSS 4, theme variables in `src/styles.css` |
| UI Components | shadcn/ui (Radix UI + Tailwind)                     |
| Toasts        | sonner                                              |
| Icons         | lucide-react                                        |
| Language      | TypeScript 6.0 (strict mode)                        |
| Deployment    | Netlify, via `@netlify/vite-plugin-tanstack-start`  |

## Directory Structure

```
├── public
│   ├── img/             # AI-generated photos (hero, boat, St. Naum)
│   ├── icon.svg / manifest.webmanifest  # PWA icon + manifest
│   └── favicon.ico
├── src
│   ├── components
│   │   ├── error-pages.tsx # Themed 404 and route error pages with home/retry actions.
│   │   └── ui          # shadcn/ui controls, overlays, feedback, forms, and tables.
│   ├── examples
│   │   └── validated-form.tsx # Unmounted form pattern with validation, pending, error, and success states.
│   ├── lib
│   │   └── utils.ts    # cn() helper for merging Tailwind classes.
│   ├── routes
│   │   ├── __root.tsx  # HTML shell, <head> metadata (siteName, siteDescription), the tooltip provider, and the toast container.
│   │   ├── index.tsx   # Landing page (/)
│   │   └── tour.tsx    # Tour setup + live GPS narration (/tour)
│   ├── router.tsx      # Creates the router from the generated route tree.
│   └── styles.css      # Tailwind import, theme variables for light and dark mode, base styles.
├── components.json     # shadcn/ui config, used by `npx shadcn add`.
├── netlify.toml        # Build command, publish directory, dev server ports.
├── package.json
├── tsconfig.json
└── vite.config.ts      # Vite path aliases and Tailwind, Netlify, TanStack Start, React plugins.
```

`src/routeTree.gen.ts` is generated by the router plugin when the dev server or build runs. Don't edit it.

Shared framework skill source lives in `frameworks/tanstack-start-react/.claude/skills` in this repository, separate from the standalone starter. Consult the matching framework/Netlify skills when available in a generated app; don't assume the starter contains a `.claude` directory.

## Key Concepts

### File-Based Routing

Route files in `src/routes/` define pages and endpoints:

- `__root.tsx` wraps every page.
- `index.tsx` is `/`.
- `about.tsx` would be `/about`.
- `api.*.ts` files are server API endpoints. See the `tanstack-start-api-routes` skill.

### Theme Variables

Colors and corner radius are CSS variables in `src/styles.css` (`--background`, `--foreground`, `--primary`, `--secondary`, `--muted`, `--accent`, `--destructive`, `--border`, `--radius`, and more), with a second set under `.dark`. Tailwind exposes them as classes such as `bg-primary`, `text-muted-foreground`, and `border-border`.

Set these variables for the product before you build any page. In components, use the variable classes instead of raw colors like `bg-white` or `text-gray-600`, so the whole site changes when a variable changes.

### UI Components

Ready-made components are in `src/components/ui/`. Use them before writing your own, and restyle them through the theme variables or their variants. Add more with `npx shadcn add <name>`. Show a toast by calling `toast()` from `sonner`; the container is already mounted in `__root.tsx`. `TooltipProvider` is mounted there too, so `Tooltip` works anywhere without its own provider.

| Need               | Components                                                         |
| ------------------ | ------------------------------------------------------------------ |
| Actions and status | Button, Badge, Progress, Skeleton, Alert, Sonner                   |
| Forms              | Input, Textarea, Label, Checkbox, RadioGroup, Switch, Select, Form |
| Overlays and menus | Dialog, Sheet, Popover, DropdownMenu, Tooltip                      |
| Content and layout | Card, Tabs, Accordion, Separator, Table                            |

Use `Form` with React Hook Form and the Zod resolver. Start from `src/examples/validated-form.tsx`; it isn't mounted or connected to a backend. Its required `onSubmit` callback must reject on failure. See [the form pattern](docs/forms.md) for HTTP submission and error handling.

Use Sheet for a mobile menu and DropdownMenu for short action lists. Give Dialog and Sheet an accessible title and description. Pair Checkbox, RadioGroup, Switch, and inputs with visible labels. Reserve tables for tabular data and wrap them in their provided scroll container.

### Design Choices

Set the product's palette, heading/body fonts, and layout before building its screens. Use an explicit user design when supplied; otherwise choose defaults that fit the product. Keep Basic's placeholder until you replace it with the requested product.

- Set `--font-body` and `--font-heading` in `src/styles.css`. Use `font-display` for headings when the product needs a separate heading font.
- Use `max-w-content` for a page container and `max-w-reading` for long text. Keep consistent horizontal padding, such as `px-4 sm:px-6`, and a small repeated spacing scale, such as `gap-4`, `gap-6`, and `py-12`.
- Keep one main heading per page and a clear heading order. Use muted text for supporting copy, not essential low-contrast labels.
- Preserve focus rings. Give icon-only buttons an accessible name. Ensure actions work with a keyboard and on narrow screens.
- Use short color/opacity transitions. Add `motion-reduce:transition-none` or `motion-reduce:animate-none` when adding motion; don't make essential content depend on animation.
- Provide loading, empty, error, and success states for each data-driven screen. Skeletons should follow the shape of the content they replace.

### Routing and Server Data

Router types are registered in `src/router.tsx`, so use typed `Link` destinations and route parameters. The root route supplies the themed 404 page; the router's default error component supplies the safe retry/home page, including child-route SSR failures. Use `throw notFound()` for absent records; keep unexpected failures on the error path. See [routing conventions](src/routes/README.md).

Start with route loaders and server functions for server data. Validate server-function input with `.validator(...)`, keep secrets on the server, and handle HTTP failures before returning data. See [the data-fetching pattern](docs/data-fetching.md). Add TanStack Query only when client-side caching, mutations, or background refresh are needed.

### Browser Storage

Pages are rendered on the server first, where `window` and `localStorage` don't exist. Read `localStorage` inside `useEffect`, not during render or in a `useState` initializer, or the first render will differ from the server HTML and React will log a hydration error.

## Configuration Files

| File             | Purpose                                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------ |
| `vite.config.ts` | Vite path aliases and Tailwind, Netlify, TanStack Start, React plugins                           |
| `tsconfig.json`  | Strict TypeScript, with the `@/*` alias for `src/*`                                              |
| `netlify.toml`   | Builds with `vite build`, publishes `dist/client`, dev server on port 8888 proxying Vite on 3000 |

## Development Commands

Use Node 22.13+ on the Node 22 line, Node 24, or Node 26+. The installed lint and test tools set this minimum alongside the framework.

```bash
npm run dev        # Start the Vite dev server on port 3000
npm run build      # Production build
npm run typecheck  # Type-check with tsc; the build doesn't
npm run lint       # Check TypeScript and React Hooks rules
npm run format:check # Check formatting
npm run format     # Format project files
npm test           # Run local form, control, and error page tests
npm run preview    # Preview the production build
```

## Conventions

- Components: PascalCase. Utilities and hooks: camelCase. Route files: kebab-case.
- Import from `src` with the `@/` alias.
- TypeScript fails on unused locals and parameters, so remove what you don't use.
- Use React hooks for state.
- Run the dev server or build once to generate route types before type-checking a fresh copy.
- Run build, typecheck, lint, format:check, and tests before reporting completion. Verify changed user flows locally; a passing build doesn't prove an interaction works.

## Application Name

Set the product's name and description in `src/routes/__root.tsx`:

- `siteName` is the page title and the title shown when the link is shared.
- `siteDescription` is the meta description and the description shown when the link is shared.

Then replace the placeholder heading and text in `src/routes/index.tsx`.
