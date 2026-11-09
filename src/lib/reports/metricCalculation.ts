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
  const scaled = Math.abs(a / b) * 10000;
  const value = Math.sign(a / b) * Math.round(scaled + Number.EPSILON * scaled) / 100;
  return { value: value || 0, error: null };
}

export function visibleRatioTotal(
  rows: Array<{ values: Record<string, number | null>; errors?: Record<string, CalculationError> }>,
  metric: { metricCode: string; sourceMetricCodes: string[]; numeratorCount?: number }
): CalculationResult {
  const sources = metric.sourceMetricCodes;
  const split = metric.numeratorCount ?? 1;
  if (!rows.length || split < 1 || split >= sources.length) {
    return { value: null, error: 'MISSING_DATA' };
  }
  function total(codes: string[]): number | null {
    const values = rows.flatMap(row => codes.map(code => row.values[code]))
      .filter((value): value is number => value != null);
    return values.length ? values.reduce((sum, value) => sum + value, 0) : null;
  }

  return ratioResult(total(sources.slice(0, split)), total(sources.slice(split)));
}
