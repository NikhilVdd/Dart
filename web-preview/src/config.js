export const SUPABASE_URL = "https://kqqmdegvjgbycnmygivs.supabase.co";
export const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_QtetGbFGjZ-ogSrVnogWWA_B8wD8MgV";

export const REQUEST_SELECT = "*, requester:profiles!requester_id(id, display_name, initials), helper:profiles!helper_id(id, display_name, initials)";
export const RUN_SELECT = "*, runner:profiles!runner_id(id, display_name, initials)";
export const PROFILE_SELECT = "id, display_name, initials, campus_id, home_place_id, campus:campuses(id, name, lat, lng), home_place:places!home_place_id(*)";
