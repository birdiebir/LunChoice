# 🎡 午餐大轉輪

解決「今天中午吃什麼」的終極方案——以台北市信義區基隆路一段 200 號為起點，收錄步行 10 分鐘內 405 家餐廳的命運轉輪。

## 功能

- **預算上限**：NT$0–1000（以人均平均消費過濾）
- **走路時間上限**：2–10 分鐘（以座標計算實際步行分鐘）
- **11 種類別篩選**：麵食、飯食便當、日式、韓式、東南亞、西式、台式小吃、健康餐盒、鍋物、咖啡輕食、其他
- 轉出結果附價位、步行時間、Google 地圖一鍵導航
- 「今天跳過這家」名單隔天自動重置；篩選設定記在瀏覽器
- **帳號登入（Supabase Email + 密碼）**：輸入 email 與密碼登入／註冊，不寄送任何驗證信
- **每人每天限轉 3 次**：次數存在 Supabase 後端、以台北時區跨午夜重置，前端改不掉
- **看廣告多轉一次**：3 次用完後轉盤上會出現提示，點下去顯示一張滿版靜態廣告圖（遠銀 Bankee，示意用，點圖另開分頁到廣告連結），2 秒後才能關閉並換得當天 +1 次額度，每人每天限領一次，額度同樣由後端強制執行
  - 網址加 `?adtest=1`（例如 `https://lunchoice.netlify.app/?adtest=1`）會進入廣告測試模式：轉盤上的廣告按鈕永遠顯示、可以無限次點開廣告視窗檢查素材／版面，不受「次數用完」限制
  - 後端另外用 `is_ad_test_account()` 白名單機制限制「每次領取真的都 +1 次（不封頂）」只對特定帳號開放（目前寫死是 `feibaidbu@gmail.com`，要換帳號就改 `supabase/schema.sql` 裡這個函式），其他一般使用者不管網址有沒有加 `?adtest=1`，廣告加轉還是維持「每人每天限領一次」——所以 `?adtest=1` 本身不是後門，只是讓廣告視窗的按鈕一直看得到、方便反覆點開檢查

## 資料來源

OpenStreetMap（Overpass API）+ Google Maps 掃區 + 人工查證精選，三方交叉合併。價位與步行時間為估計值，出發前建議確認當日營業時間。

## 登入與每日次數（Supabase 設定）

轉盤前需登入，且每人每天只有 **3 次**機會。這個限制放在 Supabase 後端強制執行，任何人清瀏覽器資料或改前端都繞不過去。

**一次性設定：**

1. 到 [supabase.com](https://supabase.com) 建立一個免費專案。
2. 後台 **SQL Editor** → 貼上 `supabase/schema.sql` 整份執行（建立 `spins`／`bonus_spins` 表與 `record_spin`／`spin_status`／`claim_bonus_spin` 函式；整份可重複執行，改版後重貼一次即可更新）。
3. 後台 **Authentication → Providers** → 確認 **Email** 已開啟。
4. **（必做）** 後台 **Authentication → Providers → Email** → 關閉 **Confirm email**（不勾）。前端只有一顆「登入 / 註冊」按鈕：先嘗試登入，失敗就自動註冊；註冊後要馬上能直接進場，所以這個開關一定要關，否則新帳號會卡在「已註冊但未驗證」、按鈕會一直顯示錯誤。
5. 後台 **Project Settings → API** → 複製 **Project URL** 與 **anon public key**，填進 `index.html` 最上方的：
   ```js
   const SUPABASE_URL = "https://YOUR-PROJECT.supabase.co";
   const SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY";
   const DAILY_LIMIT = 3;   // 想改每日次數就改這裡（也要和 SQL 的 default 3 一致）
   ```

> anon key 是設計上可公開的金鑰，放在前端沒問題——真正的把關在資料庫的 RLS 與函式。`supabase/email-templates/magic-link.html` 已不再使用（舊的魔法連結信件範本），可留著備用或直接刪除。

> 廣告視窗是純前端做的示意版（顯示 `assets/bonus-offer.jpg` 靜態圖，2 秒後才能按 X 關閉並領取加轉，點圖會另開分頁到廣告連結），沒有接任何真的廣告 SDK 或聯盟連結。要正式上線的話，把 `assets/bonus-offer.jpg` 換成實際的廣告圖片（同檔名直接覆蓋即可，或改 `index.html` 裡 `.bonus-media img` 的 `src`），或改接 Google AdSense/AdMob 之類的廣告 SDK。
>
> **命名注意**：這裡所有跟廣告視窗相關的 CSS class／id／檔名都刻意避開 `ad-`／`ad_`／`banner` 字樣（例如用 `bonus-card`、`bonus-offer.jpg`、`claim_bonus_spin`），因為瀏覽器的廣告攔截外掛（uBlock Origin 等）預設規則會直接隱藏或擋掉含這些字樣的元素與請求——之前就是因為命名踩到這個雷，導致廣告視窗在裝了廣告攔截器的瀏覽器上完全跳不出來。之後如果要加新的相關程式碼，記得沿用這個命名習慣。

## 使用

部署後開啟網頁 → 輸入 email 與密碼 → 點「登入 / 註冊」（沒帳號會自動建立）→ 開始轉盤。右上角會顯示「今天還可轉 N/3 次」。

---
🤖 Built with [Claude Code](https://claude.com/claude-code)
