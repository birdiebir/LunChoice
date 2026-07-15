-- ════════════════════════════════════════════════════════════════
--  午餐大轉輪 · Supabase 後端結構
--  在 Supabase 後台 → SQL Editor 貼上整份執行一次即可。
--
--  設計重點：
--   1. 每次轉盤都寫一筆 spins 紀錄。
--   2. 「一天」以台北時區（Asia/Taipei）計算，跨午夜自動重置。
--   3. 次數上限由 record_spin() 這個 SECURITY DEFINER 函式強制執行，
--      前端就算被竄改、localStorage 被清掉也繞不過去。
--   4. 用 advisory lock 讓同一使用者的並發請求序列化，避免灌到超過上限。
-- ════════════════════════════════════════════════════════════════

-- ── 轉盤紀錄表 ─────────────────────────────────────────────────
create table if not exists public.spins (
  id       bigint generated always as identity primary key,
  user_id  uuid        not null references auth.users(id) on delete cascade,
  spun_at  timestamptz not null default now(),
  spin_day date        not null default (now() at time zone 'Asia/Taipei')::date
);

create index if not exists spins_user_day_idx on public.spins (user_id, spin_day);

-- ── RLS：使用者只能讀自己的紀錄，且不能自行 insert/update/delete ──
alter table public.spins enable row level security;

drop policy if exists "read own spins" on public.spins;
create policy "read own spins" on public.spins
  for select using (auth.uid() = user_id);
-- 刻意不建立 insert policy：寫入只能透過下面的 record_spin() 函式。

-- ── bonus_spins：看廣告換一次額外轉盤機會，每人每天最多領一次 ──
-- （命名刻意避開 "ad_" 開頭：瀏覽器的廣告攔截外掛常用 URL/選取器規則擋掉
--   帶有 ad_ / ad- / banner 字樣的請求與元素，用這種命名會讓功能被誤擋。）
create table if not exists public.bonus_spins (
  user_id    uuid not null references auth.users(id) on delete cascade,
  bonus_day  date not null default (now() at time zone 'Asia/Taipei')::date,
  granted_at timestamptz not null default now(),
  primary key (user_id, bonus_day)
);

alter table public.bonus_spins enable row level security;

drop policy if exists "read own bonus spin" on public.bonus_spins;
create policy "read own bonus spin" on public.bonus_spins
  for select using (auth.uid() = user_id);
-- 刻意不建立 insert policy：寫入只能透過下面的 claim_bonus_spin() 函式。

-- ── claim_bonus_spin：領取當天的廣告加轉額度（只能領一次）──────
create or replace function public.claim_bonus_spin()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_day date := (now() at time zone 'Asia/Taipei')::date;
  v_new boolean;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  insert into public.bonus_spins (user_id, bonus_day)
  values (v_uid, v_day)
  on conflict (user_id, bonus_day) do nothing
  returning true into v_new;

  return json_build_object('ok', true, 'granted', coalesce(v_new, false));
end;
$$;

-- ── record_spin：登記一次轉盤（超過上限會被擋下，含廣告加轉額度）
create or replace function public.record_spin(p_limit int default 3)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_day   date := (now() at time zone 'Asia/Taipei')::date;
  v_used  int;
  v_bonus int;
  v_limit int;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- 同一使用者的並發請求序列化，確保計數正確
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

  select count(*) into v_used
    from public.spins
   where user_id = v_uid and spin_day = v_day;

  select count(*) into v_bonus
    from public.bonus_spins
   where user_id = v_uid and bonus_day = v_day;

  v_limit := p_limit + v_bonus;

  if v_used >= v_limit then
    return json_build_object(
      'ok', false, 'error', 'limit_reached',
      'used', v_used, 'limit', v_limit, 'remaining', 0);
  end if;

  insert into public.spins (user_id, spin_day) values (v_uid, v_day);

  return json_build_object(
    'ok', true,
    'used', v_used + 1, 'limit', v_limit, 'remaining', v_limit - (v_used + 1));
end;
$$;

-- ── spin_status：只讀取剩餘次數與廣告額度是否還能領，不消耗 ──
create or replace function public.spin_status(p_limit int default 3)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_day   date := (now() at time zone 'Asia/Taipei')::date;
  v_used  int;
  v_bonus int;
  v_limit int;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select count(*) into v_used
    from public.spins
   where user_id = v_uid and spin_day = v_day;

  select count(*) into v_bonus
    from public.bonus_spins
   where user_id = v_uid and bonus_day = v_day;

  v_limit := p_limit + v_bonus;

  return json_build_object(
    'ok', true,
    'used', v_used, 'limit', v_limit, 'remaining', greatest(0, v_limit - v_used),
    'bonus_available', v_bonus = 0);
end;
$$;

-- ── 授權：只有登入使用者可呼叫，anon 不行 ─────────────────────
revoke all on function public.record_spin(int)   from public, anon;
revoke all on function public.spin_status(int)    from public, anon;
revoke all on function public.claim_bonus_spin()    from public, anon;
grant execute on function public.record_spin(int) to authenticated;
grant execute on function public.spin_status(int) to authenticated;
grant execute on function public.claim_bonus_spin() to authenticated;
