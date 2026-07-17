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

-- winner_name／wheel_mode：轉盤動畫跑完、知道轉到誰之後，前端再呼叫
-- set_spin_result() 回填，讓「個人轉盤紀錄」查得到日期跟轉到的項目。
alter table public.spins add column if not exists winner_name text;
alter table public.spins add column if not exists wheel_mode  text not null default 'default';

create index if not exists spins_user_day_idx on public.spins (user_id, spin_day);

-- ── RLS：使用者只能讀自己的紀錄，且不能自行 insert/update/delete ──
alter table public.spins enable row level security;

drop policy if exists "read own spins" on public.spins;
create policy "read own spins" on public.spins
  for select using (auth.uid() = user_id);
-- 刻意不建立 insert policy：寫入只能透過下面的 record_spin() 函式。

-- ── bonus_spins：看廣告換一次額外轉盤機會，可無限次領取 ─────────
-- （命名刻意避開 "ad_" 開頭：瀏覽器的廣告攔截外掛常用 URL/選取器規則擋掉
--   帶有 ad_ / ad- / banner 字樣的請求與元素，用這種命名會讓功能被誤擋。）
-- 每看一次廣告、bonus_count 就 +1，沒有每日上限——「每天 3 次」只是
-- 免費的基礎額度，看廣告可以一直換到更多次。
create table if not exists public.bonus_spins (
  user_id     uuid not null references auth.users(id) on delete cascade,
  bonus_day   date not null default (now() at time zone 'Asia/Taipei')::date,
  granted_at  timestamptz not null default now(),
  bonus_count int not null default 1,
  primary key (user_id, bonus_day)
);
alter table public.bonus_spins add column if not exists bonus_count int not null default 1;

alter table public.bonus_spins enable row level security;

drop policy if exists "read own bonus spin" on public.bonus_spins;
create policy "read own bonus spin" on public.bonus_spins
  for select using (auth.uid() = user_id);
-- 刻意不建立 insert policy：寫入只能透過下面的 claim_bonus_spin() 函式。

-- ── claim_bonus_spin：領取一次廣告加轉額度，無次數上限 ──────────
create or replace function public.claim_bonus_spin()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_day   date := (now() at time zone 'Asia/Taipei')::date;
  v_count int;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  insert into public.bonus_spins (user_id, bonus_day, bonus_count)
  values (v_uid, v_day, 1)
  on conflict (user_id, bonus_day) do update
    set bonus_count = public.bonus_spins.bonus_count + 1;

  select bonus_count into v_count
    from public.bonus_spins
   where user_id = v_uid and bonus_day = v_day;

  return json_build_object('ok', true, 'granted', true, 'bonus_count', v_count);
end;
$$;

-- ── record_spin：登記一次轉盤（超過上限會被擋下，含廣告加轉額度）
-- 回傳的 spin_id 給前端在動畫跑完後呼叫 set_spin_result() 回填轉到誰。
create or replace function public.record_spin(p_limit int default 3)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_day     date := (now() at time zone 'Asia/Taipei')::date;
  v_used    int;
  v_bonus   int;
  v_limit   int;
  v_spin_id bigint;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- 同一使用者的並發請求序列化，確保計數正確
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

  select count(*) into v_used
    from public.spins
   where user_id = v_uid and spin_day = v_day;

  select coalesce(sum(bonus_count), 0) into v_bonus
    from public.bonus_spins
   where user_id = v_uid and bonus_day = v_day;

  v_limit := p_limit + v_bonus;

  if v_used >= v_limit then
    return json_build_object(
      'ok', false, 'error', 'limit_reached',
      'used', v_used, 'limit', v_limit, 'remaining', 0);
  end if;

  insert into public.spins (user_id, spin_day) values (v_uid, v_day) returning id into v_spin_id;

  return json_build_object(
    'ok', true, 'spin_id', v_spin_id,
    'used', v_used + 1, 'limit', v_limit, 'remaining', v_limit - (v_used + 1));
end;
$$;

-- ── set_spin_result：轉盤動畫結束後回填「轉到誰」，只能設定自己名下
--    還沒填過的那一筆，避免竄改別人或重複覆蓋 ──────────────────
create or replace function public.set_spin_result(p_spin_id bigint, p_winner_name text, p_wheel_mode text default 'default')
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_n   int;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  update public.spins
     set winner_name = left(p_winner_name, 120),
         wheel_mode  = coalesce(nullif(trim(p_wheel_mode), ''), 'default')
   where id = p_spin_id and user_id = v_uid and winner_name is null;

  get diagnostics v_n = row_count;
  return json_build_object('ok', v_n > 0);
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

  select coalesce(sum(bonus_count), 0) into v_bonus
    from public.bonus_spins
   where user_id = v_uid and bonus_day = v_day;

  v_limit := p_limit + v_bonus;

  return json_build_object(
    'ok', true,
    'used', v_used, 'limit', v_limit, 'remaining', greatest(0, v_limit - v_used),
    'bonus_available', true);
end;
$$;

-- ── 授權：只有登入使用者可呼叫，anon 不行 ─────────────────────
revoke all on function public.record_spin(int)              from public, anon;
revoke all on function public.spin_status(int)               from public, anon;
revoke all on function public.claim_bonus_spin()             from public, anon;
revoke all on function public.set_spin_result(bigint, text, text) from public, anon;
grant execute on function public.record_spin(int)            to authenticated;
grant execute on function public.spin_status(int)             to authenticated;
grant execute on function public.claim_bonus_spin()           to authenticated;
grant execute on function public.set_spin_result(bigint, text, text) to authenticated;

-- ── shared_spots：全局共享轉盤名單，所有登入使用者共讀共寫 ──────
-- 一開始是空的，任何人新增的地點會透過 Supabase Realtime 即時推播給
-- 所有正在瀏覽的使用者（不用重新整理頁面）。刻意不開放 update/delete，
-- 先求「大家一起加」，內容治理（檢舉、刪除）之後有需要再加。
create table if not exists public.shared_spots (
  id         bigint generated always as identity primary key,
  name       text not null,
  cat        text not null,
  price_min  int not null default 0,
  price_max  int not null default 0,
  walk       int not null default 0,
  addr       text not null default '',
  note       text not null default '',
  lat        double precision,
  lng        double precision,
  maps_url   text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint shared_spots_name_len check (char_length(trim(name)) > 0 and char_length(name) <= 80),
  constraint shared_spots_walk_range check (walk >= 0 and walk <= 240),
  constraint shared_spots_price_range check (price_min >= 0 and price_max >= price_min)
);

create index if not exists shared_spots_created_at_idx on public.shared_spots (created_at);

alter table public.shared_spots enable row level security;

-- 任何登入使用者都能讀取整份共享名單。
drop policy if exists "read shared spots" on public.shared_spots;
create policy "read shared spots" on public.shared_spots
  for select using (auth.role() = 'authenticated');

-- 任何登入使用者都能新增，但 created_by 必須是自己，避免冒名。
drop policy if exists "insert own shared spot" on public.shared_spots;
create policy "insert own shared spot" on public.shared_spots
  for insert with check (auth.uid() = created_by);

-- 編輯是維基式共同維護：任何登入使用者都能改任何一筆（不限本人新增的）。
drop policy if exists "any member can update shared spot" on public.shared_spots;
create policy "any member can update shared spot" on public.shared_spots
  for update using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

revoke all on public.shared_spots from public, anon;
grant select, insert, update on public.shared_spots to authenticated;

-- 開啟 Realtime：新增資料要即時推播給所有使用者。重複執行不會報錯。
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'shared_spots'
  ) then
    alter publication supabase_realtime add table public.shared_spots;
  end if;
end $$;

-- 防禦性補強：cat 原本只靠前端 <select> 限制選項，直接呼叫 API 還是能塞任意字串，
-- 而畫面上分類清單是用 innerHTML 組出來的，等於留了一個 XSS 縫。用 CHECK 把
-- 後端也鎖在同一份分類清單上（前端逃逸也一樣會擋，屬於防禦性補強，非唯一防線）。
alter table public.shared_spots drop constraint if exists shared_spots_cat_whitelist;
alter table public.shared_spots add constraint shared_spots_cat_whitelist
  check (cat in ('麵食','飯食便當','日式','韓式','東南亞','西式','台式小吃','健康餐盒','鍋物','咖啡輕食','其他'));

-- ════════════════════════════════════════════════════════════════
--  個人檔案 ／ 飯搭子圈
-- ════════════════════════════════════════════════════════════════

-- ── profiles：暱稱與大頭照，跟 auth.users 一對一 ──────────────
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  nickname   text,
  avatar_url text,
  updated_at timestamptz not null default now(),
  constraint profiles_nickname_len check (nickname is null or char_length(nickname) <= 40)
);

alter table public.profiles enable row level security;

drop policy if exists "read all profiles" on public.profiles;
create policy "read all profiles" on public.profiles
  for select using (auth.role() = 'authenticated');

drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles
  for insert with check (auth.uid() = user_id);

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on public.profiles from public, anon;
grant select, insert, update on public.profiles to authenticated;

-- ── avatars storage bucket：公開讀取，只能寫自己 {user_id}/ 底下的檔案 ──
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatar public read" on storage.objects;
create policy "avatar public read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatar owner upload" on storage.objects;
create policy "avatar owner upload" on storage.objects
  for insert with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatar owner update" on storage.objects;
create policy "avatar owner update" on storage.objects
  for update using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatar owner delete" on storage.objects;
create policy "avatar owner delete" on storage.objects
  for delete using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ── meal_groups / group_members：飯搭子圈 ─────────────────────
create table if not exists public.meal_groups (
  id         bigint generated always as identity primary key,
  name       text not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint meal_groups_name_len check (char_length(trim(name)) > 0 and char_length(name) <= 60)
);

create table if not exists public.group_members (
  group_id  bigint not null references public.meal_groups(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

alter table public.meal_groups enable row level security;
drop policy if exists "members can read their groups" on public.meal_groups;
create policy "members can read their groups" on public.meal_groups
  for select using (exists (
    select 1 from public.group_members gm where gm.group_id = id and gm.user_id = auth.uid()
  ));
revoke all on public.meal_groups from public, anon;
grant select on public.meal_groups to authenticated;

alter table public.group_members enable row level security;
drop policy if exists "members can read group roster" on public.group_members;
create policy "members can read group roster" on public.group_members
  for select using (exists (
    select 1 from public.group_members gm2
     where gm2.group_id = group_members.group_id and gm2.user_id = auth.uid()
  ));
revoke all on public.group_members from public, anon;
grant select on public.group_members to authenticated;
-- 刻意不開放直接 insert：新增成員只能透過下面的函式，才能檢查權限跟目標帳號存在。

-- ── create_group：建立群組，建立者自動成為第一個成員 ──────────
create or replace function public.create_group(p_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id  bigint;
begin
  if v_uid is null then return json_build_object('ok', false, 'error', 'not_authenticated'); end if;
  if coalesce(trim(p_name), '') = '' then return json_build_object('ok', false, 'error', 'empty_name'); end if;

  insert into public.meal_groups (name, created_by) values (trim(p_name), v_uid) returning id into v_id;
  insert into public.group_members (group_id, user_id) values (v_id, v_uid);

  return json_build_object('ok', true, 'group_id', v_id);
end;
$$;

-- ── add_group_member_by_email：輸入 email 直接加入名單──────────
-- 只有群組成員能加人；輸入的 email 要是已註冊帳號才加得進去（不寄信、不產生邀請連結）。
create or replace function public.add_group_member_by_email(p_group_id bigint, p_email text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_is_member boolean;
  v_target    uuid;
begin
  if v_uid is null then return json_build_object('ok', false, 'error', 'not_authenticated'); end if;

  select exists(select 1 from public.group_members where group_id = p_group_id and user_id = v_uid)
    into v_is_member;
  if not v_is_member then return json_build_object('ok', false, 'error', 'not_a_member'); end if;

  select id into v_target from auth.users where lower(email) = lower(trim(p_email));
  if v_target is null then return json_build_object('ok', false, 'error', 'user_not_found'); end if;

  insert into public.group_members (group_id, user_id) values (p_group_id, v_target)
  on conflict (group_id, user_id) do nothing;

  return json_build_object('ok', true, 'user_id', v_target);
end;
$$;

revoke all on function public.create_group(text) from public, anon;
revoke all on function public.add_group_member_by_email(bigint, text) from public, anon;
grant execute on function public.create_group(text) to authenticated;
grant execute on function public.add_group_member_by_email(bigint, text) to authenticated;

-- ── joinable_groups：目前系統裡「我還沒加入」的所有飯搭子圈，讓使用者
--    自己瀏覽、主動選擇加入（相對於 add_group_member_by_email 那種只能
--    被圈主動加入的被動流程）。meal_groups 本身的 RLS 只開放成員讀取
--    自己所屬的群組，這裡用 security definer 繞過，只回傳名稱／人數，
--    不洩漏成員名單等敏感資訊。 ─────────────────────────────────
create or replace function public.joinable_groups()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(json_agg(json_build_object(
           'group_id', g.id, 'name', g.name,
           'member_count', (select count(*) from public.group_members gm2 where gm2.group_id = g.id)
         ) order by g.created_at desc), '[]'::json)
    from public.meal_groups g
   where not exists (
     select 1 from public.group_members gm where gm.group_id = g.id and gm.user_id = auth.uid()
   );
$$;
revoke all on function public.joinable_groups() from public, anon;
grant execute on function public.joinable_groups() to authenticated;

-- ── join_group：主動加入任何一個群組，不需要圈主邀請 ──────────
create or replace function public.join_group(p_group_id bigint)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_exists boolean;
begin
  if v_uid is null then return json_build_object('ok', false, 'error', 'not_authenticated'); end if;

  select exists(select 1 from public.meal_groups where id = p_group_id) into v_exists;
  if not v_exists then return json_build_object('ok', false, 'error', 'group_not_found'); end if;

  insert into public.group_members (group_id, user_id) values (p_group_id, v_uid)
  on conflict (group_id, user_id) do nothing;

  return json_build_object('ok', true, 'group_id', p_group_id);
end;
$$;
revoke all on function public.join_group(bigint) from public, anon;
grant execute on function public.join_group(bigint) to authenticated;

-- ── group_spin_results：每天的轉盤結果，廣播給全組看 ───────────
create table if not exists public.group_spin_results (
  id          bigint generated always as identity primary key,
  group_id    bigint not null references public.meal_groups(id) on delete cascade,
  spin_day    date not null default (now() at time zone 'Asia/Taipei')::date,
  spinner_id  uuid not null references auth.users(id) on delete cascade,
  winner_name text not null,
  wheel_mode  text not null default 'default',
  created_at  timestamptz not null default now(),
  unique (group_id, spin_day)
);

alter table public.group_spin_results enable row level security;
drop policy if exists "members can read group results" on public.group_spin_results;
create policy "members can read group results" on public.group_spin_results
  for select using (exists (
    select 1 from public.group_members gm
     where gm.group_id = group_spin_results.group_id and gm.user_id = auth.uid()
  ));
revoke all on public.group_spin_results from public, anon;
grant select on public.group_spin_results to authenticated;
-- 刻意不開放直接 insert：只能透過 record_group_result()，內部會檢查是不是輪到你。

-- ── my_groups：我所屬的所有群組 ─────────────────────────────
create or replace function public.my_groups()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(json_agg(json_build_object(
           'group_id', g.id, 'name', g.name,
           'member_count', (select count(*) from public.group_members gm2 where gm2.group_id = g.id)
         ) order by g.created_at), '[]'::json)
    from public.meal_groups g
    join public.group_members gm on gm.group_id = g.id and gm.user_id = auth.uid();
$$;
revoke all on function public.my_groups() from public, anon;
grant execute on function public.my_groups() to authenticated;

-- ── group_daily_spinner：依加入順序，用「日期序號 mod 人數」輪值 ──
-- 不用 cron：每次呼叫都是當下即算，今天算出來的人全天都一樣，
-- 過了台北時區的午夜自然換下一個，伺服器重開機、離線都不影響正確性。
create or replace function public.group_daily_spinner(p_group_id bigint)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select user_id
    from (
      select user_id, (row_number() over (order by joined_at) - 1) as idx,
             count(*) over () as cnt
        from public.group_members
       where group_id = p_group_id
    ) m
   where cnt > 0
     and idx = mod(
       (extract(epoch from (now() at time zone 'Asia/Taipei')::date)::bigint / 86400),
       cnt
     )
$$;
revoke all on function public.group_daily_spinner(bigint) from public, anon;
grant execute on function public.group_daily_spinner(bigint) to authenticated;

-- ── group_status：群組頁一次拿到成員名單／今日轉盤人／今日結果／圈主是誰 ──
create or replace function public.group_status(p_group_id bigint)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_is_member boolean;
  v_spinner   uuid;
  v_members   json;
  v_result    json;
  v_owner     uuid;
begin
  if v_uid is null then return json_build_object('ok', false, 'error', 'not_authenticated'); end if;

  select exists(select 1 from public.group_members where group_id = p_group_id and user_id = v_uid)
    into v_is_member;
  if not v_is_member then return json_build_object('ok', false, 'error', 'not_a_member'); end if;

  select created_by into v_owner from public.meal_groups where id = p_group_id;
  select public.group_daily_spinner(p_group_id) into v_spinner;

  select json_agg(json_build_object(
           'user_id', gm.user_id,
           'nickname', coalesce(p.nickname, split_part(u.email, '@', 1)),
           'avatar_url', p.avatar_url,
           'joined_at', gm.joined_at
         ) order by gm.joined_at)
    into v_members
    from public.group_members gm
    join auth.users u on u.id = gm.user_id
    left join public.profiles p on p.user_id = gm.user_id
   where gm.group_id = p_group_id;

  select json_build_object(
           'winner_name', winner_name, 'wheel_mode', wheel_mode,
           'spinner_id', spinner_id, 'created_at', created_at
         )
    into v_result
    from public.group_spin_results
   where group_id = p_group_id and spin_day = (now() at time zone 'Asia/Taipei')::date;

  return json_build_object(
    'ok', true, 'group_id', p_group_id,
    'created_by', v_owner,
    'members', coalesce(v_members, '[]'::json),
    'daily_spinner_id', v_spinner,
    'is_daily_spinner', (v_spinner = v_uid),
    'is_owner', (v_owner = v_uid),
    'today_result', v_result
  );
end;
$$;
revoke all on function public.group_status(bigint) from public, anon;
grant execute on function public.group_status(bigint) to authenticated;

-- ── remove_group_member：只有圈主能移除別人，不能移除自己 ──────
create or replace function public.remove_group_member(p_group_id bigint, p_user_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then return json_build_object('ok', false, 'error', 'not_authenticated'); end if;

  select created_by into v_owner from public.meal_groups where id = p_group_id;
  if v_owner is null then return json_build_object('ok', false, 'error', 'group_not_found'); end if;
  if v_owner <> v_uid then return json_build_object('ok', false, 'error', 'not_owner'); end if;
  if p_user_id = v_owner then return json_build_object('ok', false, 'error', 'cannot_remove_owner'); end if;

  delete from public.group_members where group_id = p_group_id and user_id = p_user_id;

  return json_build_object('ok', true);
end;
$$;
revoke all on function public.remove_group_member(bigint, uuid) from public, anon;
grant execute on function public.remove_group_member(bigint, uuid) to authenticated;

-- ── record_group_result：轉盤人回填今天的結果，內部驗證真的輪到你 ──
create or replace function public.record_group_result(p_group_id bigint, p_winner_name text, p_wheel_mode text default 'default')
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_spinner uuid;
begin
  if v_uid is null then return json_build_object('ok', false, 'error', 'not_authenticated'); end if;

  select public.group_daily_spinner(p_group_id) into v_spinner;
  if v_spinner is distinct from v_uid then
    return json_build_object('ok', false, 'error', 'not_your_turn');
  end if;

  insert into public.group_spin_results (group_id, spinner_id, winner_name, wheel_mode)
  values (p_group_id, v_uid, left(p_winner_name, 120), coalesce(nullif(trim(p_wheel_mode), ''), 'default'))
  on conflict (group_id, spin_day) do nothing;

  return json_build_object('ok', true);
end;
$$;
revoke all on function public.record_group_result(bigint, text, text) from public, anon;
grant execute on function public.record_group_result(bigint, text, text) to authenticated;

-- ── Realtime：群組結果要即時廣播給全組 ─────────────────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'group_spin_results'
  ) then
    alter publication supabase_realtime add table public.group_spin_results;
  end if;
end $$;
