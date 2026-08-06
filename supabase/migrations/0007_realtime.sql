-- 0007: realtime publication for notifications + tasks
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table tasks;
