// Set minimal de iconițe (stroke), ca să nu depindem de nicio librărie externă.
const base = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.6,
  strokeLinecap: "round",
  strokeLinejoin: "round",
};

const paths = {
  mic: (
    <>
      <rect x="9" y="3" width="6" height="11" rx="3" {...base} />
      <path d="M5 11a7 7 0 0 0 14 0M12 18v3" {...base} />
    </>
  ),
  check: (
    <>
      <path d="M20 7 10 17l-5-5" {...base} />
    </>
  ),
  cart: (
    <>
      <path d="M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.5a2 2 0 0 0 2-1.6L20 8H6" {...base} />
      <circle cx="10" cy="20" r="1.4" {...base} />
      <circle cx="17" cy="20" r="1.4" {...base} />
    </>
  ),
  mail: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="2.5" {...base} />
      <path d="m4 8 7.1 4.6a2 2 0 0 0 2.2 0L20 8" {...base} />
    </>
  ),
  video: (
    <>
      <rect x="3" y="6" width="12" height="12" rx="2.5" {...base} />
      <path d="m15 11 6-3.5v9L15 13" {...base} />
    </>
  ),
  tag: (
    <>
      <path d="M3 12.5V5a2 2 0 0 1 2-2h7.5L21 11.5 12.5 20 3 12.5Z" {...base} />
      <circle cx="8" cy="8" r="1.3" {...base} />
    </>
  ),
  brain: (
    <>
      <path d="M12 5.5A3 3 0 0 0 6.2 6 3 3 0 0 0 4 9a3 3 0 0 0 .8 2A3 3 0 0 0 7 16.5a3 3 0 0 0 5 1.2Z" {...base} />
      <path d="M12 5.5A3 3 0 0 1 17.8 6 3 3 0 0 1 20 9a3 3 0 0 1-.8 2A3 3 0 0 1 17 16.5a3 3 0 0 1-5 1.2Z" {...base} />
      <path d="M12 5.5v13" {...base} />
    </>
  ),
  grid: (
    <>
      <rect x="3.5" y="3.5" width="7" height="7" rx="2" {...base} />
      <rect x="13.5" y="3.5" width="7" height="7" rx="2" {...base} />
      <rect x="3.5" y="13.5" width="7" height="7" rx="2" {...base} />
      <rect x="13.5" y="13.5" width="7" height="7" rx="2" {...base} />
    </>
  ),
  arrow: (
    <>
      <path d="M5 12h14m-6-6 6 6-6 6" {...base} />
    </>
  ),
  shield: (
    <>
      <path d="M12 3 5 6v6c0 4 3 7.4 7 9 4-1.6 7-5 7-9V6l-7-3Z" {...base} />
      <path d="m9 12 2 2 4-4" {...base} />
    </>
  ),
};

export default function Icon({ name, className = "w-6 h-6" }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden="true">
      {paths[name] ?? paths.check}
    </svg>
  );
}
