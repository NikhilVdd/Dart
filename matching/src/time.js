// Times cross the contract as ISO strings; arithmetic happens in epoch milliseconds.

const MS_PER_MIN = 60000;

export const toMs = iso => Date.parse(iso);
export const toIso = ms => new Date(ms).toISOString();
export const addMinutes = (ms, minutes) => ms + minutes * MS_PER_MIN;
export const minutesBetween = (fromMs, toMs_) => (toMs_ - fromMs) / MS_PER_MIN;

/** Rounds to one decimal, which is the precision every estimate is reported (and compared) at. */
export const round1 = x => Math.round(x * 10) / 10;

/** "6" or "6.5", for prose. */
export const fmtMin = x => {
  const r = round1(x);
  return Number.isInteger(r) ? String(r) : r.toFixed(1);
};

const formatters = new Map();

/** "5:42 PM" in the given time zone, independent of the machine running the code. */
export function fmtClock(iso, timeZone) {
  if (!formatters.has(timeZone)) {
    formatters.set(timeZone, new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone }));
  }
  return formatters.get(timeZone).format(new Date(iso));
}
