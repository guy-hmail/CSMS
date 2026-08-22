export interface NotificationScheduleScope {
  enabled: boolean;
  churchIds: string[] | null;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseNotificationScheduleScope(
  enabledValue: string | undefined,
  canaryValue: string | undefined,
): NotificationScheduleScope {
  if (enabledValue?.trim().toLowerCase() !== "true") {
    return { enabled: false, churchIds: [] };
  }
  const raw = canaryValue?.trim() ?? "";
  if (!raw) {
    throw new Error(
      "NOTIFICATION_SCHEDULE_CANARY_CHURCH_IDS is required when schedules are enabled.",
    );
  }
  if (raw === "*") return { enabled: true, churchIds: null };
  const churchIds = [
    ...new Set(raw.split(",").map((value) => value.trim()).filter(Boolean)),
  ];
  if (
    churchIds.length === 0 || churchIds.length > 100 ||
    churchIds.some((value) => !UUID_PATTERN.test(value))
  ) {
    throw new Error(
      "NOTIFICATION_SCHEDULE_CANARY_CHURCH_IDS must contain UUIDs or '*'.",
    );
  }
  return { enabled: true, churchIds };
}

export function isAuthorizedScheduledRequest(
  request: Request,
  serviceRoleKey: string,
): boolean {
  if (!serviceRoleKey) return false;
  const apiKey = request.headers.get("apikey")?.trim();
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  const bearer = authorization.startsWith("Bearer ")
    ? authorization.slice(7).trim()
    : "";
  return apiKey === serviceRoleKey || bearer === serviceRoleKey;
}
