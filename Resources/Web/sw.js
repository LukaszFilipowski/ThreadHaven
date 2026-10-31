'use strict';

const CACHE = 'threadhaven-shell-v1';
const SHELL = ['/', '/app.css', '/app.js', '/manifest.webmanifest', '/icon-192.png'];
const SESSION_PATTERN = /^[A-Za-z0-9._-]{1,128}$/;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(SHELL))
      .catch(() => undefined)
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (url.pathname.startsWith('/api/') || !SHELL.includes(url.pathname)) return;
  event.respondWith(
    fetch(request)
      .then((response) => {
        if (response.ok && response.type === 'basic') {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(request, copy));
        }
        return response;
      })
      .catch(() => caches.match(request).then((cached) => cached || Response.error()))
  );
});

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = {};
  }
  const title = typeof data.title === 'string' && data.title ? data.title.slice(0, 120) : 'ThreadHaven';
  const body = typeof data.body === 'string' ? data.body.slice(0, 300) : '';
  const session = typeof data.session === 'string' && SESSION_PATTERN.test(data.session) ? data.session : null;
  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      tag: session || 'threadhaven',
      icon: '/icon-192.png',
      data: { session }
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const session = event.notification.data && event.notification.data.session;
  const valid = typeof session === 'string' && SESSION_PATTERN.test(session);
  const target = valid ? '/#session=' + encodeURIComponent(session) : '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const client of windows) {
        if (new URL(client.url).origin === self.location.origin && 'focus' in client) {
          if (valid) client.postMessage({ session });
          return client.focus();
        }
      }
      return self.clients.openWindow(target);
    })
  );
});
