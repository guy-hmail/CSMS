export type ExportMetadata = {
  churchName: string;
  ouName: string;
  ouCode: string;
  reportType: string;
  periodLabel: string;
  metrics: ExportMetric[];
  selectedMetricCode: string;
  metricName: string;
  unit: string;
  generatedAt: string;
};

export type ExportMetric = {
  metricCode: string;
  metricName: string;
  unit: string;
};

export type ExportRow = {
  ouCode: string;
  ouName: string;
  values: Record<string, number | null>;
  status: 'approved' | 'partial' | 'missing';
  expected: number;
  submitted: number;
  approved: number;
  pending: number;
  draft: number;
  returned: number;
  rejected: number;
  missing: number;
};

const completenessColumns = ['Status', 'Expected', 'Submitted', 'Approved', 'Pending', 'Draft', 'Returned', 'Rejected', 'Missing'];

export function exportColumns(metadata: ExportMetadata): string[] {
  return [
    'OU Code',
    'Organization Unit',
    ...metadata.metrics.map((metric) => `${metric.metricName} (${metric.unit})`),
    ...completenessColumns
  ];
}

export function exportDetailRow(metadata: ExportMetadata, row: ExportRow): Array<string | number | null> {
  return [
    row.ouCode,
    row.ouName,
    ...metadata.metrics.map((metric) => row.values[metric.metricCode] ?? null),
    row.status,
    row.expected,
    row.submitted,
    row.approved,
    row.pending,
    row.draft,
    row.returned,
    row.rejected,
    row.missing
  ];
}

function escapeCsv(value: unknown): string {
  const text = value === null || value === undefined ? '' : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function download(blob: Blob, fileName: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  URL.revokeObjectURL(url);
}

export function reportFileBase(metadata: ExportMetadata): string {
  const safeCode = metadata.ouCode.replace(/[^A-Za-z0-9_-]/g, '_');
  const safePeriod = metadata.periodLabel.replace(/[^A-Za-z0-9_-]/g, '_').replace(/_+/g, '_');
  return `CSMS_${metadata.reportType}_${safeCode}_${safePeriod}`;
}

export function exportCsv(metadata: ExportMetadata, rows: ExportRow[]): void {
  const metadataRows = [
    ['Church', metadata.churchName], ['Organization Unit', metadata.ouName],
    ['Report Type', metadata.reportType], ['Period', metadata.periodLabel],
    ['Matrix Metrics', String(metadata.metrics.length)],
    ['Generated At', metadata.generatedAt]
  ];
  const detailRows = rows.map((row) => exportDetailRow(metadata, row).map((value, index) =>
    typeof value === 'number' && metadata.metrics[index - 2]?.unit === '%' ? value.toFixed(2) : value));
  const csv = [...metadataRows, [], exportColumns(metadata), ...detailRows]
    .map((row) => row.map(escapeCsv).join(','))
    .join('\r\n');
  download(new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8' }), `${reportFileBase(metadata)}.csv`);
}

export async function exportExcel(metadata: ExportMetadata, rows: ExportRow[]): Promise<void> {
  const { default: writeXlsxFile } = await import('write-excel-file/browser');
  const header = (value: string) => ({ value, fontWeight: 'bold' as const, backgroundColor: '#E0F2FE' });
  const summary = [
    [header('Field'), header('Value')],
    ['Church', metadata.churchName], ['Organization Unit', metadata.ouName],
    ['Report Type', metadata.reportType], ['Period', metadata.periodLabel],
    ['Matrix Metrics', String(metadata.metrics.length)],
    ['Metric Columns', metadata.metrics.map((metric) => `${metric.metricName} (${metric.unit})`).join(', ')],
    ['Generated At', metadata.generatedAt]
  ];
  const detail = [
    exportColumns(metadata).map(header),
    ...rows.map((row) => exportDetailRow(metadata, row).map((value, index) =>
      typeof value === 'number' && metadata.metrics[index - 2]?.unit === '%' ? { value, type: Number, format: '0.00' } : value))
  ];
  const detailColumns = [
    { width: 16 },
    { width: 32 },
    ...metadata.metrics.map(() => ({ width: 22 })),
    { width: 14 },
    ...completenessColumns.slice(1).map(() => ({ width: 12 }))
  ];
  await writeXlsxFile([
    { sheet: 'Summary', data: summary, columns: [{ width: 24 }, { width: 44 }], stickyRowsCount: 1 },
    { sheet: 'Matrix', data: detail, columns: detailColumns, stickyRowsCount: 1 }
  ]).toFile(`${reportFileBase(metadata)}.xlsx`);
}

export async function exportPdf(metadata: ExportMetadata, rows: ExportRow[]): Promise<void> {
  const { PDFDocument } = await import('pdf-lib');
  const pdf = await PDFDocument.create();
  const pageWidth = 1240;
  const pageHeight = 1754;
  const rowsPerPage = 28;
  const pageCount = Math.max(1, Math.ceil(rows.length / rowsPerPage));

  for (let pageIndex = 0; pageIndex < pageCount; pageIndex += 1) {
    const canvas = document.createElement('canvas');
    canvas.width = pageWidth;
    canvas.height = pageHeight;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('PDF_CANVAS_UNAVAILABLE');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, pageWidth, pageHeight);
    context.fillStyle = '#0f172a';
    context.font = '700 34px "Noto Sans Thai", Tahoma, sans-serif';
    context.fillText('CSMS Report', 70, 82);
    context.font = '600 22px "Noto Sans Thai", Tahoma, sans-serif';
    context.fillText(`${metadata.churchName} · ${metadata.ouName}`, 70, 125);
    context.font = '18px "Noto Sans Thai", Tahoma, sans-serif';
    context.fillStyle = '#475569';
    context.fillText(`${metadata.reportType} · ${metadata.periodLabel}`, 70, 163);
    context.fillText(`${metadata.metricName} (${metadata.unit}) · Generated ${metadata.generatedAt}`, 70, 197);
    context.fillText(`Page ${pageIndex + 1} / ${pageCount}`, 1030, 82);

    const widths = [150, 330, 130, 130, 130, 130, 130];
    const headings = ['OU Code', 'Organization Unit', 'Value', 'Expected', 'Submitted', 'Approved', 'Missing'];
    let x = 70;
    let y = 245;
    context.fillStyle = '#e0f2fe';
    context.fillRect(70, y, 1100, 56);
    context.fillStyle = '#075985';
    context.font = '600 17px "Noto Sans Thai", Tahoma, sans-serif';
    headings.forEach((heading, index) => { context.fillText(heading, x + 10, y + 35); x += widths[index]; });
    y += 56;
    context.font = '17px "Noto Sans Thai", Tahoma, sans-serif';
    const pageRows = rows.slice(pageIndex * rowsPerPage, (pageIndex + 1) * rowsPerPage);
    pageRows.forEach((row, rowIndex) => {
      if (rowIndex % 2) { context.fillStyle = '#f8fafc'; context.fillRect(70, y, 1100, 48); }
      context.fillStyle = '#1e293b';
      x = 70;
      const values = [row.ouCode, row.ouName, row.values[metadata.selectedMetricCode] ?? '—', row.expected, row.submitted, row.approved, row.missing];
      values.forEach((value, index) => { context.fillText(String(value), x + 10, y + 31, widths[index] - 20); x += widths[index]; });
      y += 48;
    });
    context.fillStyle = '#64748b';
    context.font = '15px "Noto Sans Thai", Tahoma, sans-serif';
    context.fillText('Approved submissions only · Permission-scoped report', 70, 1695);
    const png = await pdf.embedPng(canvas.toDataURL('image/png'));
    const page = pdf.addPage([595.28, 841.89]);
    page.drawImage(png, { x: 0, y: 0, width: 595.28, height: 841.89 });
  }
  download(new Blob([new Uint8Array(await pdf.save())], { type: 'application/pdf' }), `${reportFileBase(metadata)}.pdf`);
}
