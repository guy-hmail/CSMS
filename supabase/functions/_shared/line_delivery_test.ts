import {
  buildLineNotificationText,
  type ClaimedLineDelivery,
  classifyLineResponse,
  isAuthorizedWorkerRequest,
  normalizeDeliveryBaseUrl,
  parseDeliveryScope,
  pushLineNotification,
  safeDeliveryLogContext,
} from "./line-delivery.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const delivery: ClaimedLineDelivery = {
  delivery_id: "123e4567-e89b-42d3-a456-426614174000",
  church_id: "223e4567-e89b-42d3-a456-426614174000",
  notification_id: "323e4567-e89b-42d3-a456-426614174000",
  delivery_cycle: 0,
  attempt_count: 1,
  line_user_id: "U-sensitive-recipient",
  title: "Pending approval",
  body: "A weekly report needs review.",
  deep_link: "/app/approval?submissionId=abc",
};

Deno.test("delivery scope fails closed and validates canary UUIDs", () => {
  assert(
    !parseDeliveryScope("false", "").enabled,
    "disabled delivery must not require a canary",
  );
  let emptyFailed = false;
  try {
    parseDeliveryScope("true", "");
  } catch {
    emptyFailed = true;
  }
  assert(emptyFailed, "enabled delivery without a canary must fail closed");
  const scoped = parseDeliveryScope("true", delivery.church_id);
  assert(
    scoped.churchIds?.[0] === delivery.church_id,
    "canary church should be retained",
  );
  assert(
    parseDeliveryScope("true", "*").churchIds === null,
    "wildcard explicitly enables all tenants",
  );
});

Deno.test("worker authorization accepts only the configured service role credential", () => {
  const bearer = new Request("https://worker.test", {
    headers: { authorization: "Bearer service-key" },
  });
  const apiKey = new Request("https://worker.test", {
    headers: { apikey: "service-key" },
  });
  const wrong = new Request("https://worker.test", {
    headers: { authorization: "Bearer wrong" },
  });
  assert(
    isAuthorizedWorkerRequest(bearer, "service-key"),
    "bearer service key should authorize",
  );
  assert(
    isAuthorizedWorkerRequest(apiKey, "service-key"),
    "apikey service key should authorize",
  );
  assert(
    !isAuthorizedWorkerRequest(wrong, "service-key"),
    "wrong key must be rejected",
  );
});

Deno.test("message builder keeps deep links on the configured production origin", () => {
  const baseUrl = normalizeDeliveryBaseUrl("https://app.example.com/base/");
  const text = buildLineNotificationText(delivery, baseUrl);
  assert(
    text.includes("https://app.example.com/base/app/approval"),
    "relative deep link should use production origin",
  );
  assert(
    !text.includes(delivery.line_user_id),
    "message must not contain recipient ID",
  );
});

Deno.test("LINE response classification follows bounded retry policy", () => {
  assert(
    classifyLineResponse(new Response(null, { status: 200 })).outcome ===
      "sent",
    "2xx is sent",
  );
  assert(
    classifyLineResponse(new Response(null, { status: 409 })).outcome ===
      "sent",
    "retry-key 409 is already accepted",
  );
  assert(
    classifyLineResponse(new Response(null, { status: 429 })).outcome ===
      "retryable_failure",
    "429 retries",
  );
  assert(
    classifyLineResponse(new Response(null, { status: 503 })).outcome ===
      "retryable_failure",
    "5xx retries",
  );
  assert(
    classifyLineResponse(new Response(null, { status: 400 })).outcome ===
      "permanent_failure",
    "other 4xx is permanent",
  );
});

Deno.test("push uses stable retry key and returns no sensitive request data", async () => {
  let observed: RequestInit | undefined;
  const result = await pushLineNotification(
    delivery,
    "secret-access-token",
    normalizeDeliveryBaseUrl("https://app.example.com/"),
    ((_input: string | URL | Request, init?: RequestInit) => {
      observed = init;
      return Promise.resolve(
        new Response(null, {
          status: 200,
          headers: { "x-line-request-id": "provider-request-1" },
        }),
      );
    }) as typeof fetch,
  );
  const headers = new Headers(observed?.headers);
  assert(
    headers.get("x-line-retry-key") === delivery.delivery_id,
    "delivery UUID must be the stable retry key",
  );
  assert(
    result.providerMessageId === "provider-request-1",
    "provider request ID should be retained",
  );
  assert(
    !JSON.stringify(result).includes("secret-access-token"),
    "result must not expose the access token",
  );
});

Deno.test("network failure is retryable and log context is redacted", async () => {
  const result = await pushLineNotification(
    delivery,
    "secret-access-token",
    normalizeDeliveryBaseUrl("https://app.example.com/"),
    (() =>
      Promise.reject(
        new Error("network includes U-sensitive-recipient"),
      )) as typeof fetch,
  );
  assert(
    result.outcome === "retryable_failure",
    "network failure should retry",
  );
  const context = safeDeliveryLogContext(delivery, result.outcome);
  const serialized = JSON.stringify(context);
  assert(
    !serialized.includes(delivery.line_user_id),
    "logs must omit LINE user ID",
  );
  assert(!serialized.includes(delivery.title), "logs must omit message title");
  assert(!serialized.includes(delivery.body), "logs must omit message body");
});
