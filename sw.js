// Nictech Service Desk: offline shell cache
const CACHE = "nictech-v9";
const SHELL = ["./", "./index.html", "./manifest.json", "./icon.svg"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Network first for pages (so updates arrive), cache fallback when offline
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  if (new URL(e.request.url).origin !== location.origin) return; // database and fonts go straight to the network
  // pages and the app files are re-checked with GitHub every time, so updates show on the next refresh
  const fresh = e.request.mode === "navigate" || /\.(html|js|json)$|\/$/.test(new URL(e.request.url).pathname)
    ? fetch(e.request.url, { cache: "no-cache", credentials: "same-origin" })
    : fetch(e.request);
  e.respondWith(
    fresh
      .then(res => {
        if (res.ok && new URL(e.request.url).origin === location.origin) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, copy));
        }
        return res;
      })
      .catch(() => caches.match(e.request).then(r => r || caches.match("./index.html")))
  );
});
