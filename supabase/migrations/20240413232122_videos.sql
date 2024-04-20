create type video_state as ENUM (
  'pending',
  'active',
  'failed',
  'synthesizing'
);

create extension if not exists http;
create extension if not exists pg_net;

create function supabase_url()
returns text
language plpgsql
security definer
as $$
declare
  secret_value text;
begin
  select decrypted_secret into secret_value from vault.decrypted_secrets where name = 'supabase_url';
  return secret_value;
end;
$$;

create table videos (
  id bigint generated by default as identity primary key,
  user_id uuid references auth.users not null,
  current_state video_state default 'pending',
  youtube_url text not null,
  title text,
  content text,
  duration varchar(10),
  channel varchar(100),
  published_at timestamp with time zone,
  synthesized_at timestamp with time zone,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table videos enable row level security;

create policy "Individuals can create videos." on videos for
  insert with check (auth.uid() = user_id);
create policy "Individuals can view their own videos. " on videos for
  select using (auth.uid() = user_id);
create policy "Individuals can update their own videos." on videos for
  update using (auth.uid() = user_id);
create policy "Individuals can delete their own videos." on videos for
  delete using (auth.uid() = user_id);

alter publication supabase_realtime add table videos;

create function public.handle_inserted_video()
returns trigger as $$
begin
  perform "net"."http_post"(
    supabase_url() || '/functions/v1/capsum'::text,
    jsonb_build_object(
      'video', to_jsonb(new.*)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', current_setting('request.headers')::json->>'authorization'
    )
  ) as request_id;

  return new;
end;
$$ language plpgsql security definer;

create trigger on_video_inserted
  after insert on videos
  for each row execute procedure public.handle_inserted_video();

create function public.handle_updated_video()
returns trigger as $$
begin
  if new.current_state is distinct from old.current_state and new.current_state = 'synthesizing' then
    perform "net"."http_post"(
      supabase_url() || '/functions/v1/synthesize'::text,
      jsonb_build_object(
        'video', to_jsonb(new.*)
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', current_setting('request.headers')::json->>'authorization'
      )
    ) as request_id;
  end if;

  return new;
end;
$$ language plpgsql security definer;

create trigger on_video_updated
  after update on videos
  for each row execute procedure public.handle_updated_video();

insert into storage.buckets (id, name)
values ('tts', 'tts');

create policy "Public access" on storage.objects
  for select using (bucket_id = 'tts');

create policy "Anyone can upload" on storage.objects
  for insert with check (bucket_id = 'tts');
