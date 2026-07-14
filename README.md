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

## 資料來源

OpenStreetMap（Overpass API）+ Google Maps 掃區 + 人工查證精選，三方交叉合併。價位與步行時間為估計值，出發前建議確認當日營業時間。

## 登入與每日次數（Supabase 設定）

轉盤前需登入，且每人每天只有 **3 次**機會。這個限制放在 Supabase 後端強制執行，任何人清瀏覽器資料或改前端都繞不過去。

**一次性設定：**

1. 到 [supabase.com](https://supabase.com) 建立一個免費專案。
2. 後台 **SQL Editor** → 貼上 `supabase/schema.sql` 整份執行（建立 `spins` 表與 `record_spin`／`spin_status` 函式）。
3. 後台 **Authentication → Providers** → 確認 **Email** 已開啟。
4. **（必做）** 後台 **Authentication → Providers → Email** → 關閉 **Confirm email**（不勾）。前端只有一顆「登入 / 註冊」按鈕：先嘗試登入，失敗就自動註冊；註冊後要馬上能直接進場，所以這個開關一定要關，否則新帳號會卡在「已註冊但未驗證」、按鈕會一直顯示錯誤。
5. 後台 **Project Settings → API** → 複製 **Project URL** 與 **anon public key**，填進 `index.html` 最上方的：
   ```js
   const SUPABASE_URL = "https://YOUR-PROJECT.supabase.co";
   const SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY";
   const DAILY_LIMIT = 3;   // 想改每日次數就改這裡（也要和 SQL 的 default 3 一致）
   ```

> anon key 是設計上可公開的金鑰，放在前端沒問題——真正的把關在資料庫的 RLS 與函式。`supabase/email-templates/magic-link.html` 已不再使用（舊的魔法連結信件範本），可留著備用或直接刪除。

## 使用

部署後開啟網頁 → 輸入 email 與密碼 → 點「登入 / 註冊」（沒帳號會自動建立）→ 開始轉盤。右上角會顯示「今天還可轉 N/3 次」。

---
🤖 Built with [Claude Code](https://claude.com/claude-code)
