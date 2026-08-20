import { useEffect, useRef, useState } from "react";
import { conversation } from "../data";

/** Telefon stilizat în care conversația demo se scrie mesaj cu mesaj. */
export default function PhoneMock() {
  const [visible, setVisible] = useState(0);
  const boxRef = useRef(null);

  useEffect(() => {
    if (visible >= conversation.length) {
      const restart = setTimeout(() => setVisible(0), 5200);
      return () => clearTimeout(restart);
    }
    const next = setTimeout(() => setVisible((v) => v + 1), visible === 0 ? 700 : 1700);
    return () => clearTimeout(next);
  }, [visible]);

  useEffect(() => {
    boxRef.current?.scrollTo({ top: boxRef.current.scrollHeight, behavior: "smooth" });
  }, [visible]);

  return (
    <div className="relative mx-auto w-full max-w-[320px]">
      <div className="absolute -inset-6 rounded-[3rem] bg-accent/15 blur-3xl" />
      <div className="relative rounded-[2.5rem] border border-white/12 bg-navy-900 p-3 shadow-2xl">
        <div className="mx-auto mb-3 h-1.5 w-16 rounded-full bg-white/15" />
        <div className="rounded-[2rem] border border-white/8 bg-navy-950/80 p-4">
          <div className="mb-4 flex items-center gap-3">
            <img src="/asis-icon.png" alt="" className="h-9 w-9 rounded-xl object-cover" />
            <div>
              <p className="text-sm font-semibold text-white">ASIS</p>
              <p className="text-[11px] text-emerald-400">activ · date locale</p>
            </div>
          </div>

          <div
            ref={boxRef}
            className="flex h-[340px] flex-col gap-3 overflow-y-auto pr-1 text-[13px] leading-relaxed"
          >
            {conversation.slice(0, visible).map((msg, i) => (
              <div
                key={i}
                className={`animate-rise max-w-[85%] rounded-2xl px-3.5 py-2.5 ${
                  msg.from === "user"
                    ? "self-end rounded-br-md bg-accent text-navy-950"
                    : "self-start rounded-bl-md border border-white/10 bg-navy-800 text-slate-100"
                }`}
              >
                {msg.text}
              </div>
            ))}
            {visible < conversation.length && (
              <div className="self-start rounded-2xl rounded-bl-md border border-white/10 bg-navy-800 px-4 py-3">
                <span className="flex gap-1">
                  {[0, 1, 2].map((d) => (
                    <span
                      key={d}
                      className="h-1.5 w-1.5 animate-bounce rounded-full bg-accent-soft"
                      style={{ animationDelay: `${d * 0.15}s` }}
                    />
                  ))}
                </span>
              </div>
            )}
          </div>

          <div className="mt-4 flex items-center gap-2 rounded-full border border-white/10 bg-navy-800 px-4 py-2.5">
            <span className="flex-1 text-[12px] text-slate-400">Scrie sau vorbește...</span>
            <span className="grid h-8 w-8 place-items-center rounded-full bg-accent text-navy-950">
              <svg viewBox="0 0 24 24" className="h-4 w-4" fill="currentColor">
                <path d="M12 3a3 3 0 0 1 3 3v5a3 3 0 1 1-6 0V6a3 3 0 0 1 3-3Zm7 8a7 7 0 0 1-6 6.93V21h-2v-3.07A7 7 0 0 1 5 11h2a5 5 0 0 0 10 0h2Z" />
              </svg>
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
