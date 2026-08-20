import { useEffect, useState } from "react";

const states = [
  { key: "idle", label: "Apasă pe microfon", ring: "#5c6bff" },
  { key: "listening", label: "Te ascult...", ring: "#8e7bff" },
  { key: "processing", label: "Mă gândesc...", ring: "#4fd1c5" },
  { key: "speaking", label: "Vorbesc...", ring: "#f0a020" },
];

/** Reproduce inelul animat din ecranul vocal al aplicației, cu ciclul stărilor. */
export default function VoiceOrb() {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(
      () => setIndex((i) => (i + 1) % states.length),
      2600,
    );
    return () => clearInterval(timer);
  }, []);

  const state = states[index];

  return (
    <div className="flex flex-col items-center gap-6">
      <div className="relative grid h-64 w-64 place-items-center sm:h-72 sm:w-72">
        <div
          className="absolute inset-0 animate-pulse-ring rounded-full blur-2xl transition-colors duration-700"
          style={{ background: `radial-gradient(circle, ${state.ring}55, transparent 65%)` }}
        />
        <svg viewBox="0 0 200 200" className="absolute inset-0 animate-spin-slow">
          <defs>
            <linearGradient id="orb-ring" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor={state.ring} stopOpacity="0.95" />
              <stop offset="55%" stopColor={state.ring} stopOpacity="0.15" />
              <stop offset="100%" stopColor={state.ring} stopOpacity="0.9" />
            </linearGradient>
          </defs>
          <circle
            cx="100"
            cy="100"
            r="86"
            fill="none"
            stroke="url(#orb-ring)"
            strokeWidth="3"
            strokeLinecap="round"
            strokeDasharray="330 210"
            className="transition-all duration-700"
          />
        </svg>
        <div className="relative grid h-40 w-40 place-items-center rounded-full border border-white/10 bg-navy-900/80 shadow-[0_0_60px_-15px_var(--color-accent)] backdrop-blur sm:h-44 sm:w-44">
          <img
            src="/asis-mark.png"
            alt="Sigla ASIS"
            className="h-20 w-20 object-contain sm:h-24 sm:w-24"
          />
        </div>
      </div>

      <div className="flex flex-col items-center gap-3">
        <p
          className="text-sm font-medium tracking-wide transition-colors duration-500"
          style={{ color: state.ring }}
        >
          {state.label}
        </p>
        <div className="flex gap-1.5">
          {states.map((s, i) => (
            <span
              key={s.key}
              className={`h-1.5 rounded-full transition-all duration-500 ${
                i === index ? "w-6 bg-accent" : "w-1.5 bg-white/20"
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
