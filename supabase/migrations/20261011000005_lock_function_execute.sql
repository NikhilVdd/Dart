-- Hosted Supabase grants EXECUTE on new public functions to anon/authenticated through default
-- privileges owned by its admin roles, which migration 2's ALTER DEFAULT PRIVILEGES does not reach.
-- Signed-out clients should not be able to call any function; signed-in clients keep the
-- explicit grants from migrations 2 and 3.

revoke execute on all functions in schema public from public, anon;

-- Trigger and internal helpers are never called directly by clients.
revoke execute on function public.handle_new_user() from authenticated;
revoke execute on function public.log_request_status() from authenticated;
revoke execute on function public.set_updated_at() from authenticated;
revoke execute on function public.fill_campus_from_creator() from authenticated;
revoke execute on function public.check_list_item_run() from authenticated;
revoke execute on function public.stamp_list_item_editor() from authenticated;
