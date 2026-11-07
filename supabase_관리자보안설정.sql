-- =====================================================================
-- 소방안전 앱 · Supabase 관리자 보안 설정
-- ※ 기존에 저장된 데이터는 하나도 지우거나 바꾸지 않습니다.
-- 사용법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 적용 후: 직원은 "빈 칸 채우기"만 가능, 삭제·수정은 관리자(5324)만 가능
-- =====================================================================

-- 1) 저장에 쓰는 컬럼이 없으면 추가 (있으면 그대로 둠)
alter table public.fire_extinguishers add column if not exists updated_at timestamptz default now();
alter table public.fire_inspections  add column if not exists updated_at timestamptz default now();

-- 2) 보안(RLS) 켜기
alter table public.fire_extinguishers enable row level security;
alter table public.fire_inspections  enable row level security;

-- 3) 기존 정책 정리 후 새 정책
drop policy if exists fire_ext_select on public.fire_extinguishers;
drop policy if exists fire_ext_insert on public.fire_extinguishers;
drop policy if exists fire_ext_update on public.fire_extinguishers;
drop policy if exists fire_ins_select on public.fire_inspections;
drop policy if exists fire_ins_insert on public.fire_inspections;
drop policy if exists fire_ins_update on public.fire_inspections;

-- 누구나 보기 / 새로 올리기 가능
create policy fire_ext_select on public.fire_extinguishers for select using (true);
create policy fire_ext_insert on public.fire_extinguishers for insert with check (true);
create policy fire_ext_update on public.fire_extinguishers for update using (true) with check (true);
create policy fire_ins_select on public.fire_inspections for select using (true);
create policy fire_ins_insert on public.fire_inspections for insert with check (true);
-- 월별 기록: 비어 있는 칸만 직원이 채울 수 있음 (이미 쓴 칸은 덮어쓰기 불가)
create policy fire_ins_update on public.fire_inspections for update
  using (coalesce(inspector,'') = '' and signature is null and coalesce(note,'') = '')
  with check (true);
-- 삭제 정책은 만들지 않음 → 직원 앱에서 삭제 불가 (관리자 함수로만 삭제)

-- 4) 관리자 전용 함수 (비밀번호 확인 후 실행)
create or replace function public.fire_admin_delete_month(p_pin text, p_store text, p_no int, p_year int, p_month int)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_pin <> '5324' then raise exception 'invalid pin'; end if;
  delete from fire_inspections
   where store = p_store and extinguisher_no = p_no and inspection_year = p_year and inspection_month = p_month;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.fire_admin_delete_year(p_pin text, p_store text, p_no int, p_year int)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_pin <> '5324' then raise exception 'invalid pin'; end if;
  delete from fire_inspections where store = p_store and extinguisher_no = p_no and inspection_year = p_year;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.fire_admin_delete_ext(p_pin text, p_store text, p_no int)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_pin <> '5324' then raise exception 'invalid pin'; end if;
  delete from fire_extinguishers where store = p_store and extinguisher_no = p_no;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.fire_admin_save_month(p_pin text, p_store text, p_no int, p_year int, p_month int,
  p_inspector text, p_note text, p_signature text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_pin <> '5324' then raise exception 'invalid pin'; end if;
  update fire_inspections
     set inspector = p_inspector, note = p_note, signature = p_signature, result = '정상', updated_at = now()
   where store = p_store and extinguisher_no = p_no and inspection_year = p_year and inspection_month = p_month;
  get diagnostics n = row_count;
  if n = 0 then
    insert into fire_inspections(store, extinguisher_no, inspection_year, inspection_month, inspector, note, signature, result, updated_at)
    values (p_store, p_no, p_year, p_month, p_inspector, p_note, p_signature, '정상', now());
    n := 1;
  end if;
  return n;
end $$;

grant execute on function public.fire_admin_delete_month(text,text,int,int,int) to anon, authenticated;
grant execute on function public.fire_admin_delete_year(text,text,int,int) to anon, authenticated;
grant execute on function public.fire_admin_delete_ext(text,text,int) to anon, authenticated;
grant execute on function public.fire_admin_save_month(text,text,int,int,int,text,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
