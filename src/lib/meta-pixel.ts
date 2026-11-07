type FbqFn = ((...args: unknown[]) => void) & { queue: unknown[]; loaded: boolean; version: string; push: FbqFn; callMethod?: (...args: unknown[]) => void };
declare global {
  interface Window { fbq?: FbqFn; _fbq?: FbqFn }
}

const pixelId = (import.meta.env.VITE_META_PIXEL_ID as string | undefined)?.trim() || "";
const PURCHASE_KEY = "lumina.purchase-tracked.";

export const pixelEnabled = /^\d{8,20}$/.test(pixelId);

export function initMetaPixel() {
  if (!pixelEnabled || window.fbq) return;
  const fbq = Object.assign(
    (...args: unknown[]) => {
      if (fbq.callMethod) fbq.callMethod(...args);
      else fbq.queue.push(args);
    },
    { queue: [] as unknown[], loaded: true, version: "2.0", push: null as unknown as FbqFn }
  ) as FbqFn;
  fbq.push = fbq;
  window.fbq = fbq;
  window._fbq = fbq;
  const script = document.createElement("script");
  script.async = true;
  script.src = "https://connect.facebook.net/en_US/fbevents.js";
  document.head.appendChild(script);
  fbq("init", pixelId);
  fbq("track", "PageView");
}

export function trackPixel(event: "ViewContent" | "InitiateCheckout", params: Record<string, unknown>) {
  if (!pixelEnabled || !window.fbq) return;
  window.fbq("track", event, params);
}

export function trackPurchaseOnce(orderId: string, value: number, currency = "PYG") {
  if (!pixelEnabled || !window.fbq) return;
  const key = PURCHASE_KEY + orderId;
  try {
    if (localStorage.getItem(key)) return;
    localStorage.setItem(key, "1");
  } catch {
    return;
  }
  window.fbq("track", "Purchase", { value, currency }, { eventID: `purchase-${orderId}` });
}
