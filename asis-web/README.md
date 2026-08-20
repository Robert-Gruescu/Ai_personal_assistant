# ASIS — site de prezentare

Site de prezentare (o singură pagină) pentru aplicația mobilă **ASIS — Asistent Personal AI**
din folderul `ai_personal_assistant`.

## Rulare

```bash
npm install
npm run dev      # server de dezvoltare
npm run build    # build de producție în dist/
npm run preview  # previzualizează build-ul
```

## Stack

- React 19 + Vite
- Tailwind CSS 4 (prin pluginul `@tailwindcss/vite`, fără `tailwind.config.js`)
- Fără librării de UI sau de iconițe — totul e scris în proiect

## Structură

| Fișier | Rol |
|---|---|
| `src/data.js` | Tot conținutul (funcții, flux, arhitectură, intenții, stack). Se editează aici textele. |
| `src/App.jsx` | Secțiunile paginii: hero, funcții, demo, cum funcționează, arhitectură, confidențialitate, tehnologii, CTA. |
| `src/components/VoiceOrb.jsx` | Inelul animat din ecranul vocal al aplicației, cu ciclul stărilor. |
| `src/components/PhoneMock.jsx` | Telefon stilizat în care se scrie conversația demo. |
| `src/components/Reveal.jsx` | Animație la intrarea în ecran (IntersectionObserver). |
| `src/components/Icons.jsx` | Set minimal de iconițe SVG. |
| `src/index.css` | Paleta (navy `#141C33` + accent `#8E7BFF`, ca în aplicație) și animațiile. |

Siglele din `public/` sunt copiate din `ai_personal_assistant/assets/icon/`.

## Publicare

Build-ul e static, deci merge pe orice găzduire (Vercel, Netlify, GitHub Pages):
încarcă folderul `dist/` sau conectează repo-ul cu comanda `npm run build` și folderul
de ieșire `dist`.
