export interface ClaimedLineDelivery {
  delivery_id: string;
  church_id: string;
  notification_id: string;
  delivery_cycle: number;
  attempt_count: number;
  line_user_id: string;
  title: string;
  body: string;
  deep_link: string | null;
}

export interface LinePushResult {
  outcome: "sent" | "retryable_failure" | "permanent_failure";
  providerMessageId: string | null;
  errorCode: string | null;
  errorMessage: string | null;
}

export interface DeliveryScope {
  enabled: boolean;
  churchIds: string[] | null;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseDeliveryScope(
  enabledValue: string | undefined,
  canaryValue: string | undefined,
): DeliveryScope {
  const enabled = enabledValue?.trim().toLowerCase() === "true";
  if (!enabled) return { enabled: false, churchIds: [] };

  const raw = canaryValue?.trim() ?? "";
  if (!raw) {
    throw new Error(
      "LINE_DELIVERY_CANARY_CHURCH_IDS is required when delivery is enabled.",
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
      "LINE_DELIVERY_CANARY_CHURCH_IDS must contain UUIDs or '*'.",
    );
  }
  return { enabled: true, churchIds };
}

export function isAuthorizedWorkerRequest(
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

export function normalizeDeliveryBaseUrl(value: string | undefined): URL {
  const raw = value?.trim() ?? "";
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error("LINE_DELIVERY_APP_BASE_URL must be a valid HTTPS URL.");
  }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password) {
    throw new Error("LINE_DELIVERY_APP_BASE_URL must be a valid HTTPS URL.");
  }
  parsed.hash = "";
  parsed.search = "";
  if (!parsed.pathname.endsWith("/")) parsed.pathname += "/";
  return parsed;
}

export function buildLineNotificationText(
  delivery: ClaimedLineDelivery,
  baseUrl: URL,
): string {
  const parts = [delivery.title.trim(), delivery.body.trim()];
  if (delivery.deep_link) {
    const absolute = new URL(delivery.deep_link.replace(/^\//, ""), baseUrl);
    if (absolute.origin !== baseUrl.origin) {
      throw new Error("Notification deep link escaped the configured origin.");
    }
    parts.push(absolute.toString());
  }
  const text = parts.filter(Boolean).join("\n\n");
  return text.length <= 4500 ? text : `${text.slice(0, 4497)}...`;
}

function providerRequestId(response: Response): string | null {
  return response.headers.get("x-line-accepted-request-id") ??
    response.headers.get("x-line-request-id");
}

export function classifyLineResponse(response: Response): LinePushResult {
  const providerMessageId = providerRequestId(response);
  if (
    (response.status >= 200 && response.status < 300) || response.status === 409
  ) {
    return {
      outcome: "sent",
      providerMessageId,
      errorCode: null,
      errorMessage: null,
    };
  }

  const retryable = response.status === 408 || response.status === 429 ||
    response.status >= 500;
  return {
    outcome: retryable ? "retryable_failure" : "permanent_failure",
    providerMessageId: null,
    errorCode: `LINE_HTTP_${response.status}`,
    errorMessage: retryable
      ? `LINE Messaging API is temporarily unavailable (HTTP ${response.status}).`
      : `LINE Messaging API rejected the delivery (HTTP ${response.status}).`,
  };
}

export async function pushLineNotification(
  delivery: ClaimedLineDelivery,
  channelAccessToken: string,
  baseUrl: URL,
  fetcher: typeof fetch = fetch,
): Promise<LinePushResult> {
  try {
    const response = await fetcher("https://api.line.me/v2/bot/message/push", {
      method: "POST",
      headers: {
        "authorization": `Bearer ${channelAccessToken}`,
        "content-type": "application/json",
        "x-line-retry-key": delivery.delivery_id,
      },
      body: JSON.stringify({
        to: delivery.line_user_id,
        messages: [{
          type: "text",
          text: buildLineNotificationText(delivery, baseUrl),
        }],
      }),
      signal: AbortSignal.timeout(10_000),
    });
    return classifyLineResponse(response);
  } catch {
    return {
      outcome: "retryable_failure",
      providerMessageId: null,
      errorCode: "LINE_NETWORK_ERROR",
      errorMessage:
        "LINE Messaging API request timed out or failed at the network boundary.",
    };
  }
}

export function safeDeliveryLogContext(
  delivery: ClaimedLineDelivery,
  outcome: string,
): Record<string, unknown> {
  return {
    deliveryId: delivery.delivery_id,
    notificationId: delivery.notification_id,
    deliveryCycle: delivery.delivery_cycle,
    attemptCount: delivery.attempt_count,
    outcome,
  };
}
