const CACHE = "grab-shell-v3";
const SHELL = ["./", "./manifest.webmanifest", "./offline.html", "./icons/icon-192.png", "./icons/icon-512.png"];

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(fetch(request).catch(() => caches.match("./offline.html")));
    return;
  }

  event.respondWith(
    caches.match(request).then(cached => cached || fetch(request).then(response => {
      if (response.ok) caches.open(CACHE).then(cache => cache.put(request, response.clone()));
      return response;
    }))
  );
});

// Web Push. Every push must show a notification (Safari drops subscriptions that don't). Pushes
// that share a tag replace each other, so an order's notification moves forward step by step.
self.addEventListener("push", event => {
  let data = {};
  try {
    data = event.data?.json() ?? {};
  } catch {
    data = { body: event.data?.text() ?? "" };
  }
  const work = [
    self.registration.showNotification(data.title || "Grab", {
      body: data.body || "",
      tag: data.tag || undefined,
      renotify: Boolean(data.tag),
      icon: "./icons/icon-192.png",
      timestamp: Date.now(),
      data: { url: data.url || "./" }
    })
  ];
  if (typeof data.badge === "number" && "setAppBadge" in self.navigator) {
    work.push((data.badge > 0 ? self.navigator.setAppBadge(data.badge) : self.navigator.clearAppBadge()).catch(() => {}));
  }
  event.waitUntil(Promise.all(work));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || "./", self.registration.scope).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    const open = windows.find(client => client.url.startsWith(self.registration.scope));
    if (open) {
      try { await open.focus(); } catch { /* some platforms refuse focus; the message still opens it */ }
      open.postMessage({ type: "open", url: target });
      return;
    }
    await self.clients.openWindow(target);
  })());
});

// The browser rotated the subscription. Saving it needs the signed-in session, so the app
// re-registers the device the next time it opens (syncPush).
