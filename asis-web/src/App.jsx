import { useEffect, useState } from "react";
import Icon from "./components/Icons";
import Reveal from "./components/Reveal";
import VoiceOrb from "./components/VoiceOrb";
import PhoneMock from "./components/PhoneMock";
import { features, flow, layers, phrases, privacy, stack, stats } from "./data";

const navLinks = [
  { href: "#functii", label: "Funcții" },
  { href: "#cum-functioneaza", label: "Cum merge" },
  { href: "#arhitectura", label: "Ce face" },
  { href: "#confidentialitate", label: "Confidențialitate" },
  { href: "#tehnologii", label: "Pe scurt" },
];

function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 16);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={`fixed inset-x-0 top-0 z-50 transition-all duration-300 ${
        scrolled
          ? "border-b border-white/10 bg-navy-950/85 backdrop-blur-xl"
          : "border-b border-transparent"
      }`}
    >
      <nav className="mx-auto flex max-w-6xl items-center justify-between px-5 py-4">
        <a href="#top" className="flex items-center gap-2.5">
          <img src="/asis-icon.png" alt="" className="h-9 w-9 rounded-xl" />
          <span className="text-lg font-semibold tracking-tight text-white">
            ASIS
          </span>
        </a>

        <div className="hidden items-center gap-7 md:flex">
          {navLinks.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-sm text-slate-300 transition-colors hover:text-white"
            >
              {link.label}
            </a>
          ))}
          <a
            href="#demo"
            className="rounded-full bg-accent px-4 py-2 text-sm font-semibold text-navy-950 transition-transform hover:scale-105"
          >
            Vezi demo
          </a>
        </div>

        <button
          onClick={() => setOpen((o) => !o)}
          className="grid h-10 w-10 place-items-center rounded-xl border border-white/12 text-white md:hidden"
          aria-label="Meniu"
          aria-expanded={open}
        >
          <svg
            viewBox="0 0 24 24"
            className="h-5 w-5"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.8"
          >
            {open ? (
              <path d="m6 6 12 12M18 6 6 18" />
            ) : (
              <path d="M4 7h16M4 12h16M4 17h16" />
            )}
          </svg>
        </button>
      </nav>

      {open && (
        <div className="border-t border-white/10 bg-navy-950/95 px-5 py-4 md:hidden">
          {navLinks.map((link) => (
            <a
              key={link.href}
              href={link.href}
              onClick={() => setOpen(false)}
              className="block py-2.5 text-sm text-slate-300"
            >
              {link.label}
            </a>
          ))}
        </div>
      )}
    </header>
  );
}

function SectionTitle({ eyebrow, title, text }) {
  return (
    <Reveal className="mx-auto mb-14 max-w-2xl text-center">
      <p className="mb-3 text-xs font-semibold uppercase tracking-[0.22em] text-accent">
        {eyebrow}
      </p>
      <h2 className="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
        {title}
      </h2>
      {text && (
        <p className="mt-4 text-base leading-relaxed text-slate-400">{text}</p>
      )}
    </Reveal>
  );
}

function Hero() {
  return (
    <section id="top" className="relative overflow-hidden pt-32 pb-24 sm:pt-40">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute -top-40 left-1/2 h-[520px] w-[820px] -translate-x-1/2 rounded-full bg-indigo-glow/20 blur-[120px]" />
        <div className="absolute bottom-0 right-10 h-72 w-72 rounded-full bg-accent/15 blur-[100px]" />
      </div>

      <div className="relative mx-auto grid max-w-6xl items-center gap-16 px-5 lg:grid-cols-2">
        <Reveal>
          <span className="inline-flex items-center gap-2 rounded-full border border-white/12 bg-white/5 px-3.5 py-1.5 text-xs text-slate-300">
            <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
            Pentru Android · în limba română
          </span>

          <h1 className="mt-6 text-4xl font-semibold leading-[1.1] tracking-tight text-white sm:text-6xl">
            Asistentul tău personal{" "}
            <span className="bg-gradient-to-r from-accent to-sky-400 bg-clip-text text-transparent"></span>
          </h1>

          <p className="mt-6 max-w-xl text-lg leading-relaxed text-slate-400">
            Îi spui într-o frază ce ai de făcut, iar el se ocupă: îți ține minte
            treburile, lista de cumpărături și întâlnirile, îți citește
            emailurile și îți spune unde e mai ieftin. Fără meniuri de căutat și
            fără să-ți plece datele de pe telefon.
          </p>

          <div className="mt-9 flex flex-wrap items-center gap-4">
            <a
              href="#demo"
              className="group inline-flex items-center gap-2 rounded-full bg-accent px-6 py-3 text-sm font-semibold text-navy-950 transition-transform hover:scale-105"
            >
              Vezi cum răspunde
              <Icon
                name="arrow"
                className="h-4 w-4 transition-transform group-hover:translate-x-1"
              />
            </a>
            <a
              href="#functii"
              className="rounded-full border border-white/15 px-6 py-3 text-sm font-medium text-slate-200 transition-colors hover:border-accent hover:text-white"
            >
              Ce știe să facă
            </a>
          </div>

          <dl className="mt-14 grid grid-cols-2 gap-6 sm:grid-cols-4">
            {stats.map((s) => (
              <div key={s.label}>
                <dt className="text-2xl font-semibold text-white">{s.value}</dt>
                <dd className="mt-1 text-xs leading-snug text-slate-500">
                  {s.label}
                </dd>
              </div>
            ))}
          </dl>
        </Reveal>

        <Reveal delay={150} className="flex justify-center">
          <div className="animate-float">
            <VoiceOrb />
          </div>
        </Reveal>
      </div>
    </section>
  );
}

function Features() {
  return (
    <section id="functii" className="border-t border-white/5 py-24">
      <div className="mx-auto max-w-6xl px-5">
        <SectionTitle
          eyebrow="Ce știe să facă"
          title="Opt lucruri, dintr-o singură frază"
          text="Nimic de configurat înainte. Spui ce ai nevoie, cum ai spune unui om care te ajută cu treburile."
        />

        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {features.map((f, i) => (
            <Reveal key={f.title} delay={(i % 4) * 90}>
              <article className="group h-full rounded-2xl border border-white/10 bg-white/[0.03] p-6 transition-all duration-300 hover:-translate-y-1 hover:border-accent/40 hover:bg-white/[0.06]">
                <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent/15 text-accent transition-colors group-hover:bg-accent group-hover:text-navy-950">
                  <Icon name={f.icon} />
                </span>
                <h3 className="mt-5 text-base font-semibold text-white">
                  {f.title}
                </h3>
                <p className="mt-2.5 text-sm leading-relaxed text-slate-400">
                  {f.text}
                </p>
                <p className="mt-4 text-[11px] font-medium uppercase tracking-wider text-accent/80">
                  {f.tag}
                </p>
              </article>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

function Demo() {
  return (
    <section id="demo" className="border-t border-white/5 py-24">
      <div className="mx-auto grid max-w-6xl items-center gap-16 px-5 lg:grid-cols-2">
        <Reveal>
          <p className="mb-3 text-xs font-semibold uppercase tracking-[0.22em] text-accent">
            Demo
          </p>
          <h2 className="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
            Vorbești normal. Restul se întâmplă singur.
          </h2>
          <p className="mt-5 text-base leading-relaxed text-slate-400">
            Nu trebuie să vorbești „pe robotește”. Spui lucrurile cum îți vin,
            iar el își dă seama dacă e vorba de ceva de făcut, de ceva de
            cumpărat, de un preț de căutat sau de ceva ce merită ținut minte.
          </p>

          <ul className="mt-8 space-y-4">
            {[
              "Când ceri ceva clar, face direct — nu te mai întreabă de trei ori.",
              "Când doar pomenești ceva în treacăt, întreabă întâi.",
              "Îți răspunde scurt, ca să fie ușor de ascultat din mers.",
              "Conversațiile rămân salvate, dacă vrei să te întorci la ele.",
            ].map((line) => (
              <li key={line} className="flex gap-3 text-sm text-slate-300">
                <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-accent/20 text-accent">
                  <Icon name="check" className="h-3.5 w-3.5" />
                </span>
                {line}
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal delay={150}>
          <PhoneMock />
        </Reveal>
      </div>
    </section>
  );
}

function HowItWorks() {
  return (
    <section id="cum-functioneaza" className="border-t border-white/5 py-24">
      <div className="mx-auto max-w-6xl px-5">
        <SectionTitle
          eyebrow="Cum merge"
          title="De la ce spui, la ce se întâmplă"
          text="Cinci pași care durează câteva secunde și pe care, în general, nici nu-i observi."
        />

        <div className="relative">
          <div className="absolute left-[27px] top-4 bottom-4 hidden w-px bg-gradient-to-b from-accent/60 via-accent/20 to-transparent sm:block" />
          <div className="space-y-4">
            {flow.map((s, i) => (
              <Reveal key={s.step} delay={i * 80}>
                <div className="relative flex gap-5 rounded-2xl border border-white/10 bg-white/[0.03] p-6 transition-colors hover:border-accent/30">
                  <span className="z-10 grid h-14 w-14 shrink-0 place-items-center rounded-2xl border border-accent/30 bg-navy-900 text-sm font-semibold text-accent">
                    {s.step}
                  </span>
                  <div>
                    <h3 className="text-base font-semibold text-white">
                      {s.title}
                    </h3>
                    <p className="mt-2 text-sm leading-relaxed text-slate-400">
                      {s.text}
                    </p>
                  </div>
                </div>
              </Reveal>
            ))}
          </div>
        </div>

        <Reveal delay={120} className="mt-14">
          <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-7 sm:p-9">
            <h3 className="text-lg font-semibold text-white">
              Lucruri pe care i le poți spune
            </h3>
            <p className="mt-2 text-sm text-slate-400">
              Exact așa, cu voce tare. Nu e o listă de comenzi — sunt doar
              exemple.
            </p>
            <div className="mt-8 grid gap-8 sm:grid-cols-2">
              {phrases.map((group) => (
                <div key={group.group}>
                  <p className="text-xs font-semibold uppercase tracking-wider text-accent/80">
                    {group.group}
                  </p>
                  <ul className="mt-4 space-y-2.5">
                    {group.lines.map((line) => (
                      <li
                        key={line}
                        className="rounded-xl border border-white/8 bg-navy-900/70 px-4 py-2.5 text-sm text-slate-300"
                      >
                        „{line}”
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

function Architecture() {
  return (
    <section id="arhitectura" className="border-t border-white/5 py-24">
      <div className="mx-auto max-w-6xl px-5">
        <SectionTitle
          eyebrow="Pe îndelete"
          title="Ce vezi, ce înțelege și ce face"
          text="Pe scurt, tot ce contează despre aplicație, fără termeni pe care oricum nu i-ai folosi în vorbirea de zi cu zi."
        />

        <div className="grid gap-5 md:grid-cols-2">
          {layers.map((layer, i) => (
            <Reveal key={layer.name} delay={(i % 2) * 100}>
              <div
                className={`h-full rounded-2xl border border-white/10 bg-gradient-to-br ${layer.color} p-7`}
              >
                <div className="flex items-baseline gap-3">
                  <span className="font-mono text-xs text-white/40">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                  <h3 className="text-lg font-semibold text-white">
                    {layer.name}
                  </h3>
                </div>
                <ul className="mt-5 space-y-3">
                  {layer.items.map((item) => (
                    <li
                      key={item}
                      className="flex gap-3 text-sm text-slate-300"
                    >
                      <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-accent" />
                      <span className="leading-relaxed">{item}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

function Privacy() {
  return (
    <section id="confidentialitate" className="border-t border-white/5 py-24">
      <div className="mx-auto max-w-6xl px-5">
        <div className="grid gap-14 lg:grid-cols-[1fr_1.4fr] lg:items-center">
          <Reveal>
            <span className="grid h-14 w-14 place-items-center rounded-2xl bg-emerald-400/15 text-emerald-300">
              <Icon name="shield" className="h-7 w-7" />
            </span>
            <h2 className="mt-6 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
              Datele tale rămân la tine
            </h2>
            <p className="mt-5 text-base leading-relaxed text-slate-400">
              Nu există un server al aplicației unde să se strângă listele sau
              conversațiile tale. De pe telefon pleacă doar întrebarea pe care o
              pui asistentului și, dacă tu ceri asta, cererea către Gmail sau
              către calendar.
            </p>
          </Reveal>

          <div className="grid gap-4 sm:grid-cols-3">
            {privacy.map((p, i) => (
              <Reveal key={p.title} delay={i * 100}>
                <div className="h-full rounded-2xl border border-white/10 bg-white/[0.03] p-6">
                  <h3 className="text-sm font-semibold text-white">
                    {p.title}
                  </h3>
                  <p className="mt-3 text-sm leading-relaxed text-slate-400">
                    {p.text}
                  </p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

function Stack() {
  return (
    <section id="tehnologii" className="border-t border-white/5 py-24">
      <div className="mx-auto max-w-6xl px-5">
        <SectionTitle
          eyebrow="Pe scurt"
          title="Ce trebuie să știi înainte"
          text="Fără surprize: atât îți trebuie ca să-l folosești."
        />

        <div className="grid gap-px overflow-hidden rounded-2xl border border-white/10 bg-white/10 sm:grid-cols-2 lg:grid-cols-4">
          {stack.map((t, i) => (
            <Reveal key={t.name} delay={(i % 4) * 70}>
              <div className="h-full bg-navy-950 p-6 transition-colors hover:bg-navy-900">
                <h3 className="text-sm font-semibold text-white">{t.name}</h3>
                <p className="mt-2 text-xs leading-relaxed text-slate-400">
                  {t.role}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

function Cta() {
  return (
    <section className="border-t border-white/5 py-24">
      <Reveal className="mx-auto max-w-4xl px-5">
        <div className="relative overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-br from-navy-800 to-navy-900 px-8 py-14 text-center">
          <div className="pointer-events-none absolute -top-24 left-1/2 h-64 w-[520px] -translate-x-1/2 rounded-full bg-accent/20 blur-[90px]" />
          <div className="relative">
            <img src="/asis-mark.png" alt="" className="mx-auto h-16 w-16" />
            <h2 className="mt-6 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
              Un ajutor care chiar face lucrurile
            </h2>
            <p className="mx-auto mt-5 max-w-xl text-base leading-relaxed text-slate-400">
              Nu îți explică cum ai putea rezolva tu. Trimite emailul, pune
              produsul pe listă, programează întâlnirea și te anunță când e
              cazul — cât timp tu ești ocupat cu altceva.
            </p>
            <div className="mt-9 flex flex-wrap justify-center gap-4">
              <a
                href="#functii"
                className="rounded-full bg-accent px-6 py-3 text-sm font-semibold text-navy-950 transition-transform hover:scale-105"
              >
                Vezi ce știe să facă
              </a>
              <a
                href="#arhitectura"
                className="rounded-full border border-white/15 px-6 py-3 text-sm font-medium text-slate-200 transition-colors hover:border-accent hover:text-white"
              >
                Cum funcționează
              </a>
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}

function Footer() {
  return (
    <footer className="border-t border-white/10 py-10">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-5 text-sm text-slate-500 sm:flex-row">
        <div className="flex items-center gap-2.5">
          <img src="/asis-icon.png" alt="" className="h-7 w-7 rounded-lg" />
          <span>ASIS — Asistent Personal AI</span>
        </div>
        <p>© {new Date().getFullYear()} ASIS · Toate drepturile rezervate</p>
      </div>
    </footer>
  );
}

export default function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Features />
        <Demo />
        <HowItWorks />
        <Architecture />
        <Privacy />
        <Stack />
        <Cta />
      </main>
      <Footer />
    </>
  );
}
