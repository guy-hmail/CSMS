export type CalculationError = 'MISSING_DATA' | 'DIVISION_BY_ZERO' | null;
export type CalculationResult = { value: number | null; error: CalculationError };

export function calculationMessage(error?: CalculationError): string | undefined {
  if (error === 'MISSING_DATA') return 'ข้อมูลไม่ครบ';
  if (error === 'DIVISION_BY_ZERO') return 'หารด้วยศูนย์ไม่ได้';
  return undefined;
}

// Match PostgreSQL numeric round: halfway values round away from zero.
export function ratioResult(a: number | null | undefined, b: number | null | undefined): CalculationResult {
  if (a == null || b == null) return { value: null, error: 'MISSING_DATA' };
  if (b === 0) return { value: null, error: 'DIVISION_BY_ZERO' };
  const quotient = a / b;
  return { value: Math.sign(quotient) * Math.round(Math.abs(quotient)) || 0, error: null };
}

export function visibleRatioTotal(
  rows: Array<{ values: Record<string, number | null>; errors?: Record<string, CalculationError> }>,
  metric: { metricCode: string; sourceMetricCodes: string[] }
): CalculationResult {
  const [a, b] = metric.sourceMetricCodes;
  if (!rows.length || !a || !b || rows.some(row => row.errors?.[metric.metricCode] === 'MISSING_DATA' || row.values[a] == null || row.values[b] == null)) {
    return { value: null, error: 'MISSING_DATA' };
  }
  return ratioResult(rows.reduce((sum, row) => sum + row.values[a]!, 0), rows.reduce((sum, row) => sum + row.values[b]!, 0));
}
