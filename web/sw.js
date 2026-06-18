'use strict';

// Версия кэша. Меняйте при каждом значимом обновлении приложения,
// чтобы клиенты гарантированно получили свежие файлы.
const CACHE_VERSION = 'sbornik-v1';

// Базовый набор файлов оболочки приложения для офлайн-старта.
// Пути относительные, поэтому работают при любом base-href.
const CORE_ASSETS = [
  './',
  'index.html',
  'manifest.json',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'favicon.png',
  'assets/assets/songs.json',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_VERSION);
      // Кэшируем по одному, чтобы один 404 не ломал всю установку.
      await Promise.all(
        CORE_ASSETS.map((url) =>
          cache.add(new Request(url, { cache: 'reload' })).catch(() => null),
        ),
      );
      self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((key) => key !== CACHE_VERSION).map((key) => caches.delete(key)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Навигационные запросы: сеть с откатом на закэшированную оболочку.
  if (request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        try {
          const fresh = await fetch(request);
          const cache = await caches.open(CACHE_VERSION);
          cache.put(request, fresh.clone());
          return fresh;
        } catch (_) {
          const cache = await caches.open(CACHE_VERSION);
          return (
            (await cache.match(request)) ||
            (await cache.match('index.html')) ||
            (await cache.match('./')) ||
            Response.error()
          );
        }
      })(),
    );
    return;
  }

  // Остальные GET-запросы: cache-first с дозаписью в кэш.
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE_VERSION);
      const cached = await cache.match(request);
      if (cached) return cached;
      try {
        const fresh = await fetch(request);
        if (fresh && fresh.status === 200 && fresh.type === 'basic') {
          cache.put(request, fresh.clone());
        }
        return fresh;
      } catch (_) {
        return cached || Response.error();
      }
    })(),
  );
});
