import { NotificationsView } from '../../components/NotificationsView';

/**
 * MANAGER / COURT_MANAGER notifications (Phase 2.6) — locked
 * th_ng_b_o_badmintonpro_production_final_logic_cleaned, rendered inside the
 * ManagerShell (scope presentation follows the shell role). Notification
 * ownership is USER-specific regardless of role: dbo.sp_GetNotifications
 * returns only the authenticated actor's rows, so a MANAGER never sees other
 * users' notifications via their system-wide booking/court authority.
 */
export function ManagerNotificationsPage() {
  return <NotificationsView />;
}