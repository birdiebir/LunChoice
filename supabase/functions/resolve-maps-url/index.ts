import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// 解析 Google Maps 網址：跟隨短網址（maps.app.goo.gl / goo.gl/maps）轉址拿到完整網址，
// 再從網址結構裡盡量抽出店名與經緯度。Google 不會把價位／類別放在網址裡，
// 這兩項本來就抓不到，前端會留給使用者手動選。

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function extractName(url: string): string | null {
  const m = url.match(/\/maps\/place\/([^/@]+)/);
  if (!m) return null;
  const raw = decodeURIComponent(m[1].replace(/\+/g, " "));
  const name = raw.trim();
  return name.length > 0 ? name : null;
}

function extractLatLng(url: string): { lat: number; lng: number } | null {
  // 常見的 !3d<lat>!4d<lng> 資料區塊，通常比 @lat,lng 精準（那是地圖中心點不一定是店家本身）
  let m = url.match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/);
  if (m) return { lat: parseFloat(m[1]), lng: parseFloat(m[2]) };
  m = url.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (m) return { lat: parseFloat(m[1]), lng: parseFloat(m[2]) };
  m = url.match(/[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (m) return { lat: parseFloat(m[1]), lng: parseFloat(m[2]) };
  return null;
}

// 只服務 Google 地圖網址：這支 function 會用 server 的網路身分去 fetch
// 使用者傳進來的網址並跟著 redirect 走，沒有網域限制的話等於任何人都能
// 把它當成一個從 Supabase 機房發出、隱藏呼叫者 IP 的任意 URL fetch 代理
// （issue #052）。白名單同時套用在起始網址跟每一次轉址落點上，避免經由
// 開放轉址跳出白名單。
const ALLOWED_HOSTS = [/(^|\.)google\.com$/i, /(^|\.)goo\.gl$/i, /(^|\.)g\.co$/i];

function isAllowedHost(hostname: string): boolean {
  return ALLOWED_HOSTS.some((re) => re.test(hostname));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const { url } = await req.json();
    if (typeof url !== "string" || !/^https?:\/\//.test(url)) {
      return json({ ok: false, error: "invalid_url" }, 400);
    }
    let initialHost: string;
    try {
      initialHost = new URL(url).hostname;
    } catch {
      return json({ ok: false, error: "invalid_url" }, 400);
    }
    if (!isAllowedHost(initialHost)) {
      return json({ ok: false, error: "unsupported_host" }, 400);
    }

    let finalUrl = url;
    try {
      // manual 模式一路跟著 Location header 走，最多跳 5 次，避免短網址被無限重導卡住；
      // 每一跳的落點也要在白名單內，避免跳出 google.com/goo.gl 之外。
      let hop = url;
      for (let i = 0; i < 5; i++) {
        const res = await fetch(hop, { redirect: "manual" });
        const loc = res.headers.get("location");
        if (!loc) { finalUrl = res.url || hop; break; }
        const nextHop = new URL(loc, hop).toString();
        if (!isAllowedHost(new URL(nextHop).hostname)) { finalUrl = hop; break; }
        hop = nextHop;
        finalUrl = hop;
      }
    } catch {
      // 轉址失敗就直接拿原始網址做字串解析，不整個失敗
      finalUrl = url;
    }

    const name = extractName(finalUrl);
    const latlng = extractLatLng(finalUrl);

    return json({
      ok: true,
      resolvedUrl: finalUrl,
      name,
      lat: latlng?.lat ?? null,
      lng: latlng?.lng ?? null,
    });
  } catch (e) {
    return json({ ok: false, error: "bad_request", message: String(e) }, 400);
  }
});
