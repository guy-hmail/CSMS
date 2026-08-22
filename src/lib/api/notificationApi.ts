import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';

export type NotificationEventType =
  | 'submission_submitted'
  | 'submission_approved'
  | 'submission_returned'
  | 'edit_request_created'
  | 'edit_request_resolved'
  | 'ou_assignment_created'
  | 'missing_submission_reminder'
  | 'pending_approval_digest';

export type NotificationItem = {
  id: string;
  eventType: NotificationEventType;
  title: string;
  body: string;
  ouId: string | null;
  deepLink: string | null;
  payload: Record<string, unknown>;
  createdAt: string;
  readAt: string | null;
  archivedAt: string | null;
};

export type NotificationCursor = {
  createdAt: string;
  id: string;
};

export type NotificationPage = {
  items: NotificationItem[];
  nextCursor: NotificationCursor | null;
};

export function listNotifications(
  client: SupabaseClient,
  options: { limit?: number; cursor?: NotificationCursor | null; includeArchived?: boolean } = {}
) {
  return callRpc<NotificationPage>(client, 'list_notifications', {
    p_limit: options.limit ?? 20,
    p_cursor_created_at: options.cursor?.createdAt ?? null,
    p_cursor_id: options.cursor?.id ?? null,
    p_include_archived: options.includeArchived ?? false
  });
}

export async function getUnreadNotificationCount(client: SupabaseClient): Promise<number> {
  const result = await callRpc<{ count: number }>(client, 'get_unread_notification_count');
  return Number(result.count);
}

export function markNotificationRead(client: SupabaseClient, notificationId: string) {
  return callRpc<{ id: string; readAt: string }>(client, 'mark_notification_read', {
    p_notification_id: notificationId
  });
}

export function markAllNotificationsRead(client: SupabaseClient) {
  return callRpc<{ count: number }>(client, 'mark_all_notifications_read');
}

export function archiveNotification(client: SupabaseClient, notificationId: string) {
  return callRpc<{ id: string; readAt: string; archivedAt: string }>(client, 'archive_notification', {
    p_notification_id: notificationId
  });
}
