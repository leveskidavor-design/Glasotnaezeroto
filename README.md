# Гласот на езерото — GPS аудио водич за Охридско Езеро

**Гласот на езерото** (The Voice of the Lake) is a mobile web app that turns any phone or tablet on a tour boat into an automatic, multilingual tour guide for Lake Ohrid.

When the tour starts, the device follows the boat's GPS position. Each landmark on the route (Ohrid harbour, St. John at Kaneo, the open lake, the Bay of Bones, Trpejca, Holy Mother of God Zaum and the Monastery of St. Naum) has a marked zone on the map. As soon as the boat sails into a zone, the story of that place is read aloud, without anyone touching the phone.

The crew can pick one or more narration languages (Macedonian, English, Polish) and set their order, so mixed groups on the same boat all hear the story in their own language, one after another. The text is shown on screen at the same time, with the current sentence highlighted.

## Features

- Automatic narration triggered by GPS geofences, once per stop, plus manual play or replay for every stop
- Several narration languages in a set order, separate from the interface language (MK / EN / PL)
- Pause, resume and skip, a live map with the route, zones and boat position, and the distance to the next stop
- Demo cruise mode that simulates the boat sailing the route at ×20–×100 speed, with an option to wait at each stop while its story plays
- The screen stays on during the tour (Wake Lock), and the app can be installed on a phone's home screen
- Voice fallbacks: if a device has no Macedonian voice it uses a Serbian or Bulgarian one, and if it has no suitable voice at all the story is shown as text only

## Tech

TanStack Start (React 19) and Tailwind CSS 4, deployed on Netlify. Narration uses the browser's Web Speech API and the map uses OpenStreetMap tiles. All tour content is in `src/data/tour.ts`, and there is no backend.

## Run locally

```bash
pnpm install
netlify dev   # or: pnpm dev
```

Geolocation needs HTTPS or `localhost`. Use **Demo cruise** on `/tour?mode=demo` to try the full flow from land.

## Editing the tour

Open `src/data/tour.ts`:

- `STOPS`: the coordinates, zone radius in metres, and the name, subtitle and story of each stop in every language
- `ROUTE`: the waypoints the demo boat follows

The zone coordinates are approximate positions on the water. Check them on a real cruise and adjust the radii before going live.

## Ideas for later

- Pre-recorded or neural-voice audio files, so every device sounds the same and Macedonian always has a native voice
- Offline caching (service worker) for areas of the lake with weak signal
- A web admin screen for operators to edit stops, stories and languages, plus more routes (Struga, the Albanian shore)
