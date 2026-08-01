import {
  BarChart3,
  BookOpenCheck,
  Building2,
  ClipboardCheck,
  FileText,
  LayoutDashboard,
  Settings
} from '@lucide/svelte';
import type { Component } from 'svelte';

export type AppNavItem = {
  label: string;
  href: string;
  icon: Component;
  badgeCount?: number;
};

function normalizePath(path: string): string {
  return path.replace(/\/+$/, '') || '/';
}

export function isAppNavItemActive(href: string, pathname: string): boolean {
  const normalizedHref = normalizePath(href);
  const normalizedPath = normalizePath(pathname);

  // `/app` is the dashboard route, not a parent navigation group.
  if (normalizedHref === '/app') {
    return normalizedPath === '/app' || normalizedPath === '/app/dashboard';
  }

  return normalizedPath === normalizedHref || normalizedPath.startsWith(`${normalizedHref}/`);
}

export const APP_NAV_ITEMS: AppNavItem[] = [
  {
    label: 'แดชบอร์ด',
    href: '/app',
    icon: LayoutDashboard
  },
  {
    label: 'ส่งข้อมูลรายสัปดาห์',
    href: '/app/submissions',
    icon: ClipboardCheck
  },
  {
    label: 'รายงาน',
    href: '/app/reports',
    icon: BarChart3
  },
  {
    label: 'องค์กร/หน่วยงาน',
    href: '/app/organization',
    icon: Building2
  },
  {
    label: 'อนุมัติ',
    href: '/app/approval',
    icon: FileText
  },
  {
    label: 'คู่มือใช้งาน',
    href: '/app/help',
    icon: BookOpenCheck
  },
  {
    label: 'ตั้งค่า',
    href: '/app/settings',
    icon: Settings
  }
];
