# 🎡 午餐大轉輪

解決「今天中午吃什麼」的終極方案——以台北市信義區基隆路一段 200 號為起點，收錄步行 10 分鐘內 405 家餐廳的命運轉輪。

## 檔案結構

前端是三個純靜態檔案，沒有建置流程，開啟 `index.html` 或部署到任何靜態網站服務都能直接跑：

- `index.html` — 頁面結構（DOM），`<head>` 用 `<link>` 引入 `style.css`，`</body>` 前用 `<script type="module" src="script.js">` 引入邏輯
- `style.css` — 全部樣式，配色／圓角／字級整理成 `:root` 裡的 CSS 變數（`--bg`、`--accent`、`--radius-md`、`--fs-base` 這類），改設計規範改這裡的變數就好，不用滿檔案找字串
- `script.js` — 全部互動邏輯（含餐廳資料、Supabase 串接、轉輪運算）。檔案開頭有一段結構說明註解，解釋各段落大致怎麼分工

## 功能

- **預算上限**：NT$0–1000（以人均平均消費過濾）
- **走路時間上限**：2–10 分鐘（以座標計算實際步行分鐘）
- **11 種類別篩選**：麵食、飯食便當、日式、韓式、東南亞、西式、台式小吃、健康餐盒、鍋物、咖啡輕食、其他
- 轉出結果附價位、步行時間、Google 地圖一鍵導航
- 「今天跳過這家」名單隔天自動重置；篩選設定記在瀏覽器
- **帳號登入（Supabase Email + 密碼）**：輸入 email 與密碼登入／註冊，不寄送任何驗證信
- **每人每天基礎 3 次**：次數存在 Supabase 後端、以台北時區跨午夜重置，前端改不掉
- **看廣告多轉一次，可無限次領取**：3 次用完後轉盤上會出現提示，點下去顯示一張滿版靜態廣告圖（遠銀 Bankee，示意用，點圖另開分頁到廣告連結），2 秒後才能關閉並換得 +1 次額度——每個帳號都可以一直重複看廣告、一直加轉，沒有每日上限，「每天 3 次」只是免費的基礎額度
  - 網址加 `?adtest=1`（例如 `https://lunchoice.netlify.app/?adtest=1`）可以讓轉盤上的廣告按鈕永遠顯示，不用等 3 次基礎額度用完，方便隨時點開檢查廣告素材／版面
- **雙轉盤：預設轉盤／共享轉盤**：轉盤上方有頁籤可以切換。「預設轉盤」就是原本這 405 家的固定名單；「共享轉盤」是全站共用、一開始空白的名單，任何登入使用者新增的地點會透過 Supabase Realtime 即時同步給所有正在瀏覽的人，不用重新整理頁面。切到共享轉盤時會出現「+ 新增地點到共享清單」按鈕，表單欄位是店名／類別／價位／走路時間／Google Maps 網址；貼 Google Maps 網址按「自動帶入」可以解析出店名與經緯度、並用直線距離估算走路時間（不是真正的路線時間，可自行調整），價位跟類別 Google 沒有公開在網址裡、需要手動選
  - **編輯共享地點**：切到共享轉盤時，展開「看看今天名單裡有哪些店」清單，每張卡片右上角有個 ✎ 編輯圖示，點開會用同一個表單帶入現有資料，改完按「儲存變更」就會更新（維基式共同維護，任何登入使用者都能改任何一筆，不限本人新增的）；改完自己畫面立刻更新，其他人那邊靠 Realtime 同步過去。**預設轉盤的 405 家沒有這個圖示**——那份資料是寫死在 `script.js` 裡的固定清單，不是資料庫，本來就沒有「更新」這回事
- **飯搭子圈**：右上角「飯搭子圈」可以建立群組（自訂名稱）、輸入 email 把已註冊的帳號直接加進成員名單（不寄信、不用邀請連結，對方要先有帳號）。群組會依「加入順序」每天自動輪流指定一位「今日轉盤人」，只有輪到的人能用這個群組轉（可以選預設或共享轉盤），次數規則跟平常一樣吃自己的每日額度；轉出結果會廣播給全組看到「今天跟著吃這個」，全組即時同步、不用重新整理
  - **移除成員**：只有建立群組的圈主，能在成員卡片上看到 × 按鈕把人移出群組；圈主不能移除自己。× 要點兩次（第一次變成「確定？」，2.5 秒內再點一次才真的送出）避免手滑
- **我的檔案**：右上角「我的檔案」可以改暱稱、上傳大頭照（存在 Supabase Storage，公開讀取、只能改自己的檔案），下面列出自己過去每一次轉盤的日期與轉到的項目
- **Header 版位**：主標題「午餐大轉輪」在左，導覽（飯搭子圈、我的檔案）在右，兩邊水平置中對齊；「今天還可轉 N/3 次」的額度徽章放在轉盤正上方置中；大頭照＋email 在導覽最右邊，點下去才展開「登出」選單（原本是常駐的登出按鈕）

## 資料來源

OpenStreetMap（Overpass API）+ Google Maps 掃區 + 人工查證精選，三方交叉合併。價位與步行時間為估計值，出發前建議確認當日營業時間。共享轉盤的內容則完全由使用者自行新增，未經審核。

## 登入與每日次數（Supabase 設定）

轉盤前需登入，且每人每天只有 **3 次**機會。這個限制放在 Supabase 後端強制執行，任何人清瀏覽器資料或改前端都繞不過去。

**一次性設定：**

1. 到 [supabase.com](https://supabase.com) 建立一個免費專案。
2. 後台 **SQL Editor** → 貼上 `supabase/schema.sql` 整份執行（建立 `spins`／`bonus_spins` 表與 `record_spin`／`spin_status`／`claim_bonus_spin` 函式；整份可重複執行，改版後重貼一次即可更新）。
3. 後台 **Authentication → Providers** → 確認 **Email** 已開啟。
4. **（必做）** 後台 **Authentication → Providers → Email** → 關閉 **Confirm email**（不勾）。前端只有一顆「登入 / 註冊」按鈕：先嘗試登入，失敗就自動註冊；註冊後要馬上能直接進場，所以這個開關一定要關，否則新帳號會卡在「已註冊但未驗證」、按鈕會一直顯示錯誤。
5. 後台 **Project Settings → API** → 複製 **Project URL** 與 **anon public key**，填進 `script.js` 最上方的：
   ```js
   const SUPABASE_URL = "https://YOUR-PROJECT.supabase.co";
   const SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY";
   const DAILY_LIMIT = 3;   // 想改每日次數就改這裡（也要和 SQL 的 default 3 一致）
   ```

> anon key 是設計上可公開的金鑰，放在前端沒問題——真正的把關在資料庫的 RLS 與函式。`supabase/email-templates/magic-link.html` 已不再使用（舊的魔法連結信件範本），可留著備用或直接刪除。

> 廣告視窗是純前端做的示意版（顯示 `assets/bonus-offer.jpg` 靜態圖，2 秒後才能按 X 關閉並領取加轉，點圖會另開分頁到廣告連結），沒有接任何真的廣告 SDK 或聯盟連結。要正式上線的話，把 `assets/bonus-offer.jpg` 換成實際的廣告圖片（同檔名直接覆蓋即可，或改 `index.html` 裡 `.bonus-media img` 的 `src`），或改接 Google AdSense/AdMob 之類的廣告 SDK。
>
> **命名注意**：這裡所有跟廣告視窗相關的 CSS class／id／檔名都刻意避開 `ad-`／`ad_`／`banner` 字樣（例如用 `bonus-card`、`bonus-offer.jpg`、`claim_bonus_spin`），因為瀏覽器的廣告攔截外掛（uBlock Origin 等）預設規則會直接隱藏或擋掉含這些字樣的元素與請求——之前就是因為命名踩到這個雷，導致廣告視窗在裝了廣告攔截器的瀏覽器上完全跳不出來。之後如果要加新的相關程式碼，記得沿用這個命名習慣。

## 共享轉盤（Supabase 設定）

`supabase/schema.sql` 裡的 `shared_spots` 表就是共享轉盤的資料，跟著上面「一次性設定」步驟 2 一起貼 SQL Editor 執行就會建好（含 RLS 與 Realtime）：

- RLS：任何登入使用者都能讀取全部資料、都能新增（新增時 `created_by` 一定要是自己，後端擋，前端改不掉）、也都能更新任何一筆（維基式共同維護，不限本人新增的），刻意不開放 delete
- Realtime：`shared_spots` 已加進 `supabase_realtime` publication，任何人新增資料，所有正在瀏覽網頁的使用者都會透過 `postgres_changes` 訂閱即時收到，不用重新整理

**Google Maps 網址自動解析**需要額外部署一個 Edge Function（原始碼在 `supabase/functions/resolve-maps-url/index.ts`）：

```bash
supabase functions deploy resolve-maps-url --project-ref YOUR-PROJECT-REF
```

這個函式的功能很單純：跟隨 Google Maps 短網址（`maps.app.goo.gl`）的轉址拿到完整網址，再用網址結構抽出店名跟經緯度（`@lat,lng` 或 `!3d..!4d..` 這種區塊）。**沒有串 Google Places API**，所以抓不到價位跟類別——Google 本來就不會把這兩項寫在網址裡，要另外呼叫收費 API 才拿得到。前端會把這兩個欄位留給使用者手動選。走路時間是用抓到的經緯度對基隆路一段 200 號算直線距離換算（約 70 公尺/分鐘），僅供參考，送出前都可以手動調整。如果之後想要更準：串 Google Places API 可以補上分類；串 Distance Matrix API 可以拿到实際路線的走路時間，都需要另外申請有計費的 API 金鑰。

## 個人檔案／飯搭子圈（Supabase 設定）

`supabase/schema.sql` 後半段是這兩個功能的資料表，一樣跟著「一次性設定」步驟 2 貼 SQL Editor 執行就會建好：

- **profiles**：暱稱＋大頭照網址，RLS 是「任何登入使用者都能讀全部（要顯示別人的暱稱/頭像），但只能寫自己那筆」
- **avatars storage bucket**：公開讀取、2MB 上限、只收 jpg/png/webp/gif；寫入權限限定只能寫進自己的 `{user_id}/` 資料夾（RLS 用 `storage.foldername` 判斷），已用真實帳號測試過「傳自己資料夾成功、傳別人資料夾被擋」
- **meal_groups / group_members**：群組跟成員名單，RLS 只有「同群組成員」能互相看到
- **加入名單**：`add_group_member_by_email()` 這個函式做（不是直接 insert group_members），會檢查呼叫者是不是已經在這個群組、email 是不是已註冊帳號
- **每日輪值**：`group_daily_spinner()` 用「成員依加入時間排序 → 從 Unix epoch 起算的天數 mod 成員人數」算出當天輪到誰，是**單純函式即算，沒有用 cron**——不管伺服器有沒有跑、什麼時候呼叫，同一天算出來的人都一樣，過了台北時區午夜自然換下一個，重開機、離線都不影響正確性
- **權限驗證雙重把關**：前端只是不顯示轉盤按鈕，真正擋下「不是你的班」的是 `record_group_result()` 內部重新算一次今天該輪到誰，跟呼叫者不同就直接拒絕——已用兩個測試帳號實測過，非輪值者呼叫會被擋
- **廣播**：`group_spin_results` 開了 Realtime，轉盤人送出結果後全組會即時收到，不用重新整理

## 使用

部署後開啟網頁 → 輸入 email 與密碼 → 點「登入 / 註冊」（沒帳號會自動建立）→ 開始轉盤。轉盤正上方會顯示「今天還可轉 N/3 次」。轉盤上方可以切換「預設轉盤」／「共享轉盤」；右上角可以建立或加入飯搭子圈、進我的檔案。

---
🤖 Built with [Claude Code](https://claude.com/claude-code)
