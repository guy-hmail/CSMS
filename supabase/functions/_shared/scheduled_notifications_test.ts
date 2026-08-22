import {
  isAuthorizedScheduledRequest,
  parseNotificationScheduleScope,
} from "./scheduled-notifications.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const churchId = "123e4567-e89b-42d3-a456-426614174000";

Deno.test("notification schedules fail closed and require explicit canary scope", () => {
  assert(
    !parseNotificationScheduleScope("false", "").enabled,
    "disabled schedules must stay disabled",
  );
  let failed = false;
  try {
    parseNotificationScheduleScope("true", "");
  } catch {
    failed = true;
  }
  assert(failed, "enabled schedule without scope must fail");
  assert(
    parseNotificationScheduleScope("true", churchId).churchIds?.[0] ===
      churchId,
    "canary Tenant should be retained",
  );
  assert(
    parseNotificationScheduleScope("true", "*").churchIds === null,
    "wildcard must be explicit",
  );
});

Deno.test("scheduled endpoints require the exact service role credential", () => {
  const bearer = new Request("https://schedule.test", {
    headers: { authorization: "Bearer service-key" },
  });
  const wrong = new Request("https://schedule.test", {
    headers: { apikey: "wrong" },
  });
  assert(
    isAuthorizedScheduledRequest(bearer, "service-key"),
    "service bearer should authorize",
  );
  assert(
    !isAuthorizedScheduledRequest(wrong, "service-key"),
    "wrong key must be rejected",
  );
});
