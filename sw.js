/* 午餐大轉輪・Service Worker
   只負責「離線也能開得起來」，不是真的離線可用（轉盤要吃 Supabase）。
   策略刻意用 network-first：先試網路拿最新版，只有真的斷線／逾時才回退
   到快取——這個專案常常改版，cache-first 會讓使用者裝了 PWA 之後卡在
   舊版 script.js 出不來，比沒有離線快取更糟。

   改版後如果想強制大家換一批新快取，把 CACHE_NAME 版號往上加一即可，
   舊快取會在 activate 時被清掉。 */
const CACHE_NAME = "lunch-wheel-v1";
const PRECACHE_URLS = [
  "./",
  "./index.html",
  "./style.css",
  "./script.js",
  "./manifest.webmanifest",
  "./assets/icons/icon-192.png",
  "./assets/icons/icon-512.png",
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const req = event.request;
  // 只處理自己網域、GET 的請求；Supabase API／CDN 的 esm.sh 都交給瀏覽器正常處理，
  // 不快取（帳號資料本來就不該離線快取，esm.sh 有自己的快取機制）。
  if (req.method !== "GET" || new URL(req.url).origin !== location.origin) return;

  event.respondWith(
    fetch(req)
      .then(res => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(req, copy));
        return res;
      })
      .catch(() => caches.match(req).then(cached => cached || caches.match("./index.html")))
  );
});
