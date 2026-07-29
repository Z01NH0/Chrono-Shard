begin;

alter table public.chrono_profiles
  add column if not exists email_ownership_verified boolean not null default false,
  add column if not exists email_last_changed_at timestamptz;

update public.chrono_profiles
set email_ownership_verified = false
where email_ownership_verified is distinct from false;

create index if not exists chrono_profiles_email_status_idx
  on public.chrono_profiles(email_ownership_verified, email_last_changed_at desc nulls last);

alter table public.chrono_profiles enable row level security;
revoke all on public.chrono_profiles from public, anon, authenticated;
grant all on public.chrono_profiles to service_role;

comment on column public.chrono_profiles.email_ownership_verified is
  'Indica confirmação real de posse do e-mail. Permanece false enquanto o projeto não tiver SMTP/OTP.';

comment on column public.chrono_profiles.email_last_changed_at is
  'Data da última troca ou migração do e-mail usado como identidade no Supabase Auth.';

commit;
