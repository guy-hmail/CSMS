import { createClient } from "@supabase/supabase-js";
import { serve } from "../_shared/handler.ts";
import { HttpError, readJson } from "../_shared/http.ts";
import { bearerToken } from "../_shared/supabase-admin.ts";

interface ExportRequest {
  ouId?: string;
  fromDate?: string;
  toDate?: string;
  metricCode?: string;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function csv(value: unknown): string {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

serve(async (request, headers) => {
  const body = await readJson<ExportRequest>(request);
  if (!body.ouId || !UUID_PATTERN.test(body.ouId) || !body.fromDate || !DATE_PATTERN.test(body.fromDate) ||
      !body.toDate || !DATE_PATTERN.test(body.toDate) || !body.metricCode) {
    throw new HttpError(400, "INVALID_EXPORT_FILTER", "OU, date range and metric are required.");
  }
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) throw new HttpError(500, "SERVER_MISCONFIGURED", "Supabase credentials are missing.");
  const token = bearerToken(request);
  const client = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: response, error } = await client.rpc("get_report_table", {
    p_ou_id: body.ouId,
    p_from_date: body.fromDate,
    p_to_date: body.toDate,
  });
  if (error) throw new HttpError(403, "REPORT_FORBIDDEN", error.message);
  const report = response?.data;
  const metric = report?.metrics?.find((item: Record<string, unknown>) => item.metricCode === body.metricCode);
  if (!report || !metric) throw new HttpError(404, "REPORT_METRIC_NOT_FOUND", "Metric is unavailable.");
  const lines = [
    ["Church", report.church.name], ["Organization Unit", report.ou.name],
    ["From", body.fromDate], ["To", body.toDate], ["Metric", metric.metricName],
    ["Generated At", new Date().toISOString()], [],
    ["OU Code", "Organization Unit", "Value", "Unit"],
    ...report.rows.map((row: Record<string, unknown>) => [
      row.ouCode, row.ouName, (row.values as Record<string, unknown>)[body.metricCode!], metric.unit,
    ]),
  ].map((row) => row.map(csv).join(","));
  const fileName = `CSMS_Report_${String(report.ou.code).replace(/[^A-Za-z0-9_-]/g, "_")}_${body.fromDate}_${body.toDate}.csv`;
  return new Response(`\uFEFF${lines.join("\r\n")}`, {
    status: 200,
    headers: { ...headers, "content-type": "text/csv; charset=utf-8", "content-disposition": `attachment; filename="${fileName}"` },
  });
});
