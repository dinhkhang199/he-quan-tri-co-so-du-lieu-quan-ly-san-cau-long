import { NotificationsView } from '../components/NotificationsView';

/**
 * Customer notifications (Phase 2.6) — locked
 * th_ng_b_o_badmintonpro_production_final_logic_cleaned, rendered inside the
 * CustomerShell. Rows come from dbo.sp_GetNotifications for the authenticated
 * actor only. See NotificationsView for the fetch/filter/mark-read behavior.
 */
export function NotificationsPage() {
  return <NotificationsView />;
}