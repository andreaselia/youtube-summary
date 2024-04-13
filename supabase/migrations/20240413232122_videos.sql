create table videos (
  id bigint generated by default as identity primary key,
  user_id uuid references auth.users not null,
  video_id text not null,
  is_complete boolean default false,
  inserted_at timestamp with time zone default timezone('utc'::text, now()) not null
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
