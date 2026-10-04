const CACHE_NAME = 'espelunca-pwa-v6'
const SHELL_URLS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icons/icon-96.png',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/icon-192-maskable.png',
  '/icons/icon-512-maskable.png',
  '/screenshots/desktop-home.png',
  '/screenshots/mobile-home.png',
  '/espelunca-icon.svg',
]

self.addEventListener('install', event => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then(cache => cache.addAll(SHELL_URLS))
      .then(() => self.skipWaiting()),
  )
})

self.addEventListener('activate', event => {
  event.waitUntil(
    caches
      .keys()
      .then(keys =>
        Promise.all(
          keys
            .filter(key => key !== CACHE_NAME)
            .map(key => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', event => {
  const request = event.request
  const url = new URL(request.url)

  if (request.method !== 'GET' || url.origin !== self.location.origin) {
    return
  }

  // Never cache AT Protocol API responses.
  if (url.pathname.startsWith('/xrpc/')) {
    return
  }

  const cacheableDestination = new Set([
    'document',
    'script',
    'style',
    'image',
    'font',
  ])

  if (!cacheableDestination.has(request.destination)) {
    return
  }

  if (request.destination === 'document') {
    event.respondWith(
      fetch(request).catch(() =>
        caches.match('/').then(response => response || caches.match('/index.html')),
      ),
    )
    return
  }

  event.respondWith(
    fetch(request)
      .then(response => {
        if (response.ok) {
          const copy = response.clone()
          void caches.open(CACHE_NAME).then(cache => cache.put(request, copy))
        }
        return response
      })
      .catch(() => caches.match(request)),
  )
})
