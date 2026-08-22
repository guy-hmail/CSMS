<script lang="ts">
  import { onMount } from 'svelte';
  import { env } from '$env/dynamic/public';
  import {
    AlertTriangle,
    Building2,
    CalendarDays,
    CheckCircle2,
    ChevronDown,
    ChevronRight,
    CirclePlus,
    Copy,
    Info,
    Link2,
    MapPin,
    Pencil,
    Search,
    Send,
    ShieldCheck,
    Trash2,
    UserPlus,
    Users,
    X
  } from '@lucide/svelte';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import { buildLiffUrl } from '$lib/auth/liffConfig';
  import {
    assignOuMember,
    createOrganizationUnit,
    getAccessibleOuTree,
    getOuMembers,
    removeOuMember,
    searchAssignableMembers,
    softDeleteOrganizationUnit,
    updateOrganizationUnit,
    updateOuMemberAssignment,
    type OrganizationTreeNode
  } from '$lib/api/organizationApi';
  import {
    createOuInviteLink,
    listOuInvitations,
    reissueOuInvitation,
    revokeOuInvitation,
    type OuInvitation
  } from '$lib/api/invitationApi';

  type OuType = string;
  type Role = 'admin' | 'manager' | 'data_entry' | 'approver' | 'viewer';
  type Tab = 'overview' | 'members';

  type OrganizationUnit = {
    id: string;
    parentId: string | null;
    name: string;
    code: string;
    description: string | null;
    type: OuType;
    level: number;
    sortOrder: number;
    allowDataEntry: boolean;
    active: boolean;
  };

  type LineAccount = {
    id: string;
    churchMemberId: string;
    displayName: string;
    lineUserId: string;
    email: string | null;
    active: boolean;
    existingRoles: Role[];
  };

  type Assignment = {
    id: string;
    ouId: string;
    accountId: string;
    role: Role;
    canOverride: boolean;
    assignedAt: string;
    canEdit: boolean;
    canRemove: boolean;
  };

  const roleOptions: { id: Role; label: string; description: string }[] = [
    { id: 'admin', label: 'ผู้ดูแลระบบ', description: 'จัดการข้อมูลและสิทธิ์ทั้งหมดในขอบเขต' },
    { id: 'manager', label: 'ผู้จัดการหน่วยงาน', description: 'จัดการ OU ลูกและสมาชิกภายใน subtree' },
    { id: 'data_entry', label: 'ผู้บันทึกข้อมูล', description: 'สร้างและส่งข้อมูลรายสัปดาห์' },
    { id: 'approver', label: 'ผู้อนุมัติ', description: 'ตรวจทานและอนุมัติข้อมูลในขอบเขต' },
    { id: 'viewer', label: 'ผู้ดูรายงาน', description: 'ดู Dashboard และรายงานเท่านั้น' }
  ];
  let ouTypeOptions: {
    id: string;
    label: string;
    defaultAllowDataEntry: boolean;
  }[] = [];
  let authorizedRootIds: string[] = [];
  let ous: OrganizationUnit[] = [];
  let accounts: LineAccount[] = [];
  let assignableAccounts: LineAccount[] = [];
  let assignments: Assignment[] = [];
  let invitations: OuInvitation[] = [];

  let selectedOuId = '';
  let expandedIds = new Set<string>();
  let treeSearch = '';
  let activeTab: Tab = 'members';
  let createModalOpen = false;
  let assignModalOpen = false;
  let inviteModalOpen = false;
  let editModalOpen = false;
  let deleteOuModalOpen = false;
  let removeTarget: Assignment | null = null;
  let revokeInviteTarget: OuInvitation | null = null;
  let reissueInviteTarget: OuInvitation | null = null;
  let removeReason = '';
  let revokeInviteReason = '';
  let reissueInviteExpiresInDays = 7;
  let toastMessage = '';
  let formError = '';
  let organizationError = '';
  let organizationLoading = true;
  let ouCreating = false;
  let ouUpdating = false;
  let ouDeleting = false;
  let accountSearchLoading = false;
  let accountAssigning = false;
  let membersLoading = false;
  let memberMutationId = '';
  let invitationMutationId = '';
  let memberAssignableRoles: Role[] = [];
  let canGrantMemberOverride = false;

  let newOuParentId = selectedOuId;
  let newOuName = '';
  let newOuType: OuType = 'group';
  let newOuAllowDataEntry = true;

  let editOuName = '';
  let editOuDescription = '';
  let editOuType: OuType = '';
  let editOuParentId = '';
  let editOuAllowDataEntry = false;
  let editOuSortOrder = 0;
  let confirmAdditiveParentEntry = false;
  let deleteOuReason = '';

  let selectedAccountId = '';
  let selectedRole: Role = 'data_entry';
  let selectedCanOverride = false;
  let accountSearch = '';
  let inviteRole: Role = 'data_entry';
  let inviteCanOverride = false;
  let inviteExpiresInDays = 7;
  let inviteDisplayName = '';
  let inviteLink = '';
  let inviteExpiresAt = '';
  let inviteCreating = false;
  let inviteSharing = false;
  let isInLineClient = false;

  $: authorizedOus = getAuthorizedOus(ous, authorizedRootIds);
  $: selectedOu = authorizedOus.find((ou) => ou.id === selectedOuId) ?? authorizedOus[0];
  $: selectedMembers = assignments.filter((assignment) => assignment.ouId === selectedOuId);
  $: childCount = authorizedOus.filter((ou) => ou.parentId === selectedOuId).length;
  $: visibleOus = getVisibleOus(authorizedOus, expandedIds, treeSearch);
  $: selectedNewOuParent = ous.find((ou) => ou.id === newOuParentId);
  $: willDisableParentDataEntry = newOuAllowDataEntry && selectedNewOuParent?.allowDataEntry === true;
  $: availableAccounts = assignableAccounts.filter((account) => account.active && !account.existingRoles.includes(selectedRole) && `${account.displayName} ${account.lineUserId} ${account.email ?? ''}`.toLowerCase().includes(accountSearch.trim().toLowerCase()));

  function getAuthorizedOus(allOus: OrganizationUnit[], rootIds: string[]): OrganizationUnit[] {
    return allOus.filter((ou) => {
      if (rootIds.includes(ou.id)) return true;
      let parentId = ou.parentId;
      while (parentId) {
        if (rootIds.includes(parentId)) return true;
        parentId = allOus.find((item) => item.id === parentId)?.parentId ?? null;
      }
      return false;
    });
  }
  function getVisibleOus(allOus: OrganizationUnit[], expanded: Set<string>, search: string): OrganizationUnit[] {
    const query = search.trim().toLowerCase();
    if (query) return allOus.filter((ou) => `${ou.name} ${ou.code}`.toLowerCase().includes(query));
    return allOus.filter((ou) => {
      let parentId = ou.parentId;
      while (parentId) {
        const parent = allOus.find((item) => item.id === parentId);
        if (!parent) break;
        if (!expanded.has(parentId)) return false;
        parentId = parent.parentId;
      }
      return true;
    });
  }

  function getExpandedIdsForSelection(
    allOus: OrganizationUnit[],
    currentExpandedIds: Set<string>,
    selectedId: string
  ): Set<string> {
    const ouIds = new Set(allOus.map((ou) => ou.id));
    const next = new Set([...currentExpandedIds].filter((id) => ouIds.has(id)));

    for (const ou of allOus) {
      if (!ou.parentId || !ouIds.has(ou.parentId)) next.add(ou.id);
    }

    let parentId = allOus.find((ou) => ou.id === selectedId)?.parentId ?? null;
    while (parentId && ouIds.has(parentId)) {
      next.add(parentId);
      parentId = allOus.find((ou) => ou.id === parentId)?.parentId ?? null;
    }

    return next;
  }

  function getAccount(accountId: string): LineAccount {
    return accounts.find((account) => account.id === accountId) ?? accounts[0];
  }

  function getParent(ou: OrganizationUnit): OrganizationUnit | null {
    return ou.parentId ? authorizedOus.find((item) => item.id === ou.parentId) ?? null : null;
  }

  function getPath(ou: OrganizationUnit): string {
    const names = [ou.name];
    let parentId = ou.parentId;
    while (parentId) {
      const parent = authorizedOus.find((item) => item.id === parentId);
      if (!parent) break;
      names.unshift(parent.name);
      parentId = parent.parentId;
    }
    return names.join(' / ');
  }

  function buildInviteUrl(inviteToken: string): string {
    const url = buildLiffUrl(env.PUBLIC_LINE_LIFF_ID)
      ?? new URL('/', window.location.origin);
    url.searchParams.set('invite', inviteToken);
    return url.toString();
  }

  function hasChildren(ouId: string): boolean {
    return authorizedOus.some((ou) => ou.parentId === ouId);
  }
  function getDisplayDepth(ou: OrganizationUnit): number {
    let depth = 0;
    let parentId = ou.parentId;
    while (parentId && authorizedOus.some((item) => item.id === parentId)) {
      depth += 1;
      parentId = authorizedOus.find((item) => item.id === parentId)?.parentId ?? null;
    }
    return depth;
  }

  function toggleExpanded(ouId: string): void {
    const next = new Set(expandedIds);
    next.has(ouId) ? next.delete(ouId) : next.add(ouId);
    expandedIds = next;
  }

  function selectOu(ouId: string): void {
    selectedOuId = ouId;
    activeTab = 'members';
    void loadMembers(ouId);
  }

  function showToast(message: string): void {
    toastMessage = message;
  }

  function openCreateModal(): void {
    if (ouTypeOptions.length === 0) {
      formError = 'Tenant นี้ยังไม่มี OU Type ที่เปิดใช้งาน';
      return;
    }
    newOuParentId = selectedOuId;
    newOuName = '';
    newOuType = ouTypeOptions[0].id;
    newOuAllowDataEntry = ouTypeOptions[0].defaultAllowDataEntry;
    formError = '';
    createModalOpen = true;
  }

  function isDescendant(candidateId: string, ancestorId: string): boolean {
    let parentId = ous.find((item) => item.id === candidateId)?.parentId ?? null;
    while (parentId) {
      if (parentId === ancestorId) return true;
      parentId = ous.find((item) => item.id === parentId)?.parentId ?? null;
    }
    return false;
  }

  function openEditModal(): void {
    if (!selectedOu) return;
    editOuName = selectedOu.name;
    editOuDescription = selectedOu.description ?? '';
    editOuType = selectedOu.type;
    editOuParentId = selectedOu.parentId ?? '';
    editOuAllowDataEntry = selectedOu.allowDataEntry;
    editOuSortOrder = selectedOu.sortOrder;
    confirmAdditiveParentEntry = false;
    formError = '';
    editModalOpen = true;
  }

  async function saveOu(): Promise<void> {
    if (!selectedOu) return;
    const name = editOuName.trim();
    if (!name || !editOuType) {
      formError = 'กรุณากรอกชื่อและประเภท OU ให้ครบ';
      return;
    }
    if (selectedOu.parentId && !editOuParentId) {
      formError = 'OU ที่ไม่ใช่ Root ต้องมี OU แม่';
      return;
    }
    if (editOuParentId && (editOuParentId === selectedOu.id || isDescendant(editOuParentId, selectedOu.id))) {
      formError = 'ไม่สามารถย้าย OU ไปไว้ใต้ตัวเองหรือ OU ลูกได้';
      return;
    }
    if (editOuAllowDataEntry && !selectedOu.allowDataEntry && hasChildren(selectedOu.id) && !confirmAdditiveParentEntry) {
      formError = 'กรุณายืนยันว่าข้อมูลตรงของ OU แม่จะถูกนับเพิ่มจาก OU ลูก';
      return;
    }

    ouUpdating = true;
    formError = '';
    try {
      await updateOrganizationUnit(getSupabaseBrowserClient(), {
        ouId: selectedOu.id,
        parentOuId: selectedOu.parentId === null ? null : editOuParentId,
        ouTypeId: editOuType,
        name,
        description: editOuDescription.trim() || null,
        allowDataEntry: editOuAllowDataEntry,
        confirmAdditiveParentEntry,
        sortOrder: editOuSortOrder
      });
      editModalOpen = false;
      await loadOrganization(selectedOu.id);
      showToast(`อัปเดต ${name} และบันทึกลงฐานข้อมูลแล้ว`);
    } catch (error) {
      formError = error instanceof Error ? error.message : 'ไม่สามารถแก้ไข OU ได้';
    } finally {
      ouUpdating = false;
    }
  }

  function openDeleteOuModal(): void {
    if (!selectedOu || selectedOu.parentId === null) return;
    deleteOuReason = '';
    formError = '';
    deleteOuModalOpen = true;
  }

  async function deleteOu(): Promise<void> {
    if (!selectedOu || !deleteOuReason.trim()) {
      formError = 'กรุณาระบุเหตุผลในการปิดใช้งาน OU';
      return;
    }
    const deletedName = selectedOu.name;
    const fallbackOuId = selectedOu.parentId ?? undefined;
    ouDeleting = true;
    formError = '';
    try {
      await softDeleteOrganizationUnit(getSupabaseBrowserClient(), {
        ouId: selectedOu.id,
        reason: deleteOuReason.trim()
      });
      deleteOuModalOpen = false;
      await loadOrganization(fallbackOuId);
      showToast(`ปิดใช้งาน ${deletedName} แบบ soft delete แล้ว`);
    } catch (error) {
      formError = error instanceof Error ? error.message : 'ไม่สามารถปิดใช้งาน OU ได้';
    } finally {
      ouDeleting = false;
    }
  }

  function getOuTypeLabel(typeId: string): string {
    return ouTypeOptions.find((item) => item.id === typeId)?.label ?? typeId;
  }

  function handleOuTypeChange(): void {
    newOuAllowDataEntry = ouTypeOptions.find((item) => item.id === newOuType)?.defaultAllowDataEntry ?? false;
  }

  async function createOu(): Promise<void> {
    const name = newOuName.trim();
    const parent = ous.find((ou) => ou.id === newOuParentId);
    if (!name || !parent) { formError = 'กรุณากรอกชื่อและเลือก OU แม่ให้ครบ'; return; }
    ouCreating = true;
    formError = '';
    try {
      const created = await createOrganizationUnit(getSupabaseBrowserClient(), {
        parentOuId: parent.id,
        ouTypeId: newOuType,
        name,
        allowDataEntry: newOuAllowDataEntry
      });
      await loadOrganization(created.ouId);
      createModalOpen = false;
      showToast(created.parentDataEntryDisabled
        ? `สร้าง ${name} แล้ว และปิดการรับข้อมูลของ OU แม่ “${created.parentOuName}” อัตโนมัติ เพื่อป้องกันการนับข้อมูลซ้ำ`
        : `สร้าง ${name} ภายใต้ ${parent.name} แล้ว`);
    } catch (error) {
      formError = error instanceof Error ? error.message : 'ไม่สามารถสร้าง OU ได้';
    } finally {
      ouCreating = false;
    }
  }

  async function openAssignModal(): Promise<void> {
    selectedAccountId = '';
    selectedRole = memberAssignableRoles.includes('data_entry') ? 'data_entry' : memberAssignableRoles[0] ?? 'viewer';
    selectedCanOverride = false;
    accountSearch = '';
    formError = '';
    assignModalOpen = true;
    await loadAssignableAccounts();
  }

  async function loadAssignableAccounts(): Promise<void> {
    if (!selectedOuId) return;
    accountSearchLoading = true;
    formError = '';
    try {
      const result = await searchAssignableMembers(getSupabaseBrowserClient(), selectedOuId, accountSearch);
      const loadedAccounts = result.items.map((member) => ({
        id: member.accountId,
        churchMemberId: member.churchMemberId,
        displayName: member.displayName,
        lineUserId: member.lineUserId,
        email: member.email,
        active: true,
        existingRoles: member.existingRoles
      }));
      assignableAccounts = loadedAccounts;
      if (!loadedAccounts.some((account) => account.id === selectedAccountId)) selectedAccountId = '';
    } catch (error) {
      formError = error instanceof Error ? error.message : 'ไม่สามารถค้นหา LINE Account ได้';
    } finally {
      accountSearchLoading = false;
    }
  }

  function flattenTree(nodes: OrganizationTreeNode[]): OrganizationUnit[] {
    return nodes.flatMap((node) => [
      {
        id: node.id,
        parentId: node.parentId,
        name: node.name,
        code: node.code,
        description: node.description,
        type: node.ouTypeId,
        level: node.level,
        sortOrder: node.sortOrder,
        allowDataEntry: node.allowDataEntry,
        active: true
      },
      ...flattenTree(node.children)
    ]);
  }

  async function loadMembers(ouId: string): Promise<void> {
    membersLoading = true;
    try {
      organizationError = '';
      const client = getSupabaseBrowserClient();
      const [result, invitationResult] = await Promise.all([
        getOuMembers(client, ouId),
        listOuInvitations(client, ouId)
      ]);
      memberAssignableRoles = result.assignableRoles;
      canGrantMemberOverride = result.canGrantOverride;
      invitations = invitationResult.items;
      accounts = result.items.map((member) => ({
        id: member.accountId,
        churchMemberId: member.churchMemberId,
        displayName: member.displayName,
        lineUserId: member.lineUserId,
        email: member.email,
        active: true,
        existingRoles: [member.role]
      }));
      assignments = result.items.map((member) => ({
        id: member.assignmentId,
        ouId: member.ouId,
        accountId: member.accountId,
        role: member.role,
        canOverride: member.canOverride,
        canEdit: member.canEdit,
        canRemove: member.canRemove,
        assignedAt: new Intl.DateTimeFormat('th-TH', { dateStyle: 'medium' }).format(
          new Date(member.assignedAt)
        )
      }));
    } catch (error) {
      organizationError = error instanceof Error ? error.message : 'ไม่สามารถโหลดสมาชิกของ OU ได้';
    } finally {
      membersLoading = false;
    }
  }

  async function loadOrganization(preferredOuId?: string): Promise<void> {
    try {
      organizationError = '';
      const client = getSupabaseBrowserClient();
      const [result, typeResult] = await Promise.all([
        getAccessibleOuTree(client),
        client
          .from('organization_unit_types')
          .select('id,name,default_allow_data_entry')
          .eq('is_active', true)
          .is('deleted_at', null)
          .order('sort_order')
      ]);
      if (typeResult.error) throw typeResult.error;
      ouTypeOptions = (typeResult.data ?? []).map((item) => ({
        id: item.id,
        label: item.name,
        defaultAllowDataEntry: item.default_allow_data_entry
      }));
      const liveOus = flattenTree(result.items);
      if (liveOus.length === 0) {
        organizationError = 'บัญชีนี้ยังไม่มี OU ที่เข้าถึงได้';
        return;
      }
      ous = liveOus;
      authorizedRootIds = result.items.map((item) => item.id);
      selectedOuId = liveOus.some((item) => item.id === preferredOuId)
        ? preferredOuId!
        : liveOus.some((item) => item.id === selectedOuId)
          ? selectedOuId
          : liveOus[0].id;
      expandedIds = getExpandedIdsForSelection(liveOus, expandedIds, selectedOuId);
      await loadMembers(selectedOuId);
    } catch (error) {
      organizationError = error instanceof Error ? error.message : 'ไม่สามารถโหลดโครงสร้างองค์กรได้';
    } finally {
      organizationLoading = false;
    }
  }

  function openInviteModal(): void {
    inviteRole = 'data_entry';
    inviteCanOverride = false;
    inviteExpiresInDays = 7;
    inviteDisplayName = '';
    inviteLink = '';
    inviteExpiresAt = '';
    formError = '';
    inviteModalOpen = true;
  }

  function handleInviteRoleChange(): void {
    if (inviteRole !== 'approver') inviteCanOverride = false;
  }

  async function createInvite(): Promise<void> {
    if (!selectedOu) return;
    inviteCreating = true;
    formError = '';
    try {
      const created = await createOuInviteLink(getSupabaseBrowserClient(), {
        targetOuId: selectedOu.id,
        permission: inviteRole,
        canOverride: inviteCanOverride,
        expiresInDays: inviteExpiresInDays,
        displayName: inviteDisplayName.trim() || undefined
      });
      inviteLink = buildInviteUrl(created.inviteToken);
      inviteExpiresAt = created.expiresAt;
      await loadMembers(selectedOu.id);
    } catch (error) {
      formError = error instanceof Error ? error.message : 'ไม่สามารถสร้าง Invite Link ได้';
    } finally {
      inviteCreating = false;
    }
  }

  async function copyInviteLink(): Promise<void> {
    if (!inviteLink) return;
    await navigator.clipboard.writeText(inviteLink);
    showToast('คัดลอก Invite Link แล้ว ส่งให้ผู้รับทาง LINE ได้เลย');
  }

  function shareInviteToLineFriend(): void {
    if (!inviteLink || !selectedOu) return;
    formError = '';
    const shareUrl = buildLiffUrl(env.PUBLIC_LINE_LIFF_ID, 'line/share-invite');
    if (!shareUrl) {
      formError = 'ยังไม่ได้ตั้งค่า LINE LIFF ID';
      return;
    }
    const roleLabel = roleOptions.find((role) => role.id === inviteRole)?.label ?? inviteRole;
    shareUrl.searchParams.set('invite', inviteLink);
    shareUrl.searchParams.set('ou', selectedOu.name);
    shareUrl.searchParams.set('role', roleLabel);
    if (inviteDisplayName.trim()) shareUrl.searchParams.set('recipient', inviteDisplayName.trim());
    inviteSharing = true;
    window.location.assign(shareUrl.toString());
  }

  function invitationStatusLabel(status: OuInvitation['status']): string {
    return {
      pending: 'รอรับสิทธิ์',
      accepted: 'รับสิทธิ์แล้ว',
      expired: 'หมดอายุ',
      revoked: 'เพิกถอนแล้ว'
    }[status];
  }

  function invitationStatusClass(status: OuInvitation['status']): string {
    return {
      pending: 'border-amber-200 bg-amber-50 text-amber-800',
      accepted: 'border-emerald-200 bg-emerald-50 text-emerald-800',
      expired: 'border-slate-200 bg-slate-100 text-slate-600',
      revoked: 'border-rose-200 bg-rose-50 text-rose-700'
    }[status];
  }

  function openRevokeInvitation(invitation: OuInvitation): void {
    revokeInviteTarget = invitation;
    revokeInviteReason = '';
    formError = '';
  }

  async function revokeInvitation(): Promise<void> {
    if (!revokeInviteTarget || !revokeInviteReason.trim()) {
      formError = 'กรุณาระบุเหตุผลในการเพิกถอน Invite';
      return;
    }
    invitationMutationId = revokeInviteTarget.invitationId;
    formError = '';
    try {
      await revokeOuInvitation(getSupabaseBrowserClient(), {
        invitationId: revokeInviteTarget.invitationId,
        reason: revokeInviteReason.trim()
      });
      revokeInviteTarget = null;
      await loadMembers(selectedOuId);
      showToast('เพิกถอน Invite Link แล้ว ลิงก์เดิมไม่สามารถใช้ได้อีก');
    } catch (error) {
      formError = error instanceof Error ? error.message : 'ไม่สามารถเพิกถอน Invite ได้';
    } finally {
      invitationMutationId = '';
    }
  }

  function openReissueInvitation(invitation: OuInvitation): void {
    reissueInviteTarget = invitation;
    reissueInviteExpiresInDays = 7;
    formError = '';
  }

  async function reissueInvitation(): Promise<void> {
    if (!reissueInviteTarget) return;
    const invitation = reissueInviteTarget;
    invitationMutationId = invitation.invitationId;
    organizationError = '';
    try {
      const created = await reissueOuInvitation(getSupabaseBrowserClient(), {
        invitationId: invitation.invitationId,
        expiresInDays: reissueInviteExpiresInDays
      });
      inviteRole = invitation.permission;
      inviteCanOverride = invitation.canOverride;
      inviteLink = buildInviteUrl(created.inviteToken);
      inviteExpiresAt = created.expiresAt;
      reissueInviteTarget = null;
      inviteModalOpen = true;
      await loadMembers(selectedOuId);
      showToast('ออก Invite Link ใหม่แล้ว กรุณาคัดลอกลิงก์ล่าสุด');
    } catch (error) {
      organizationError = error instanceof Error ? error.message : 'ไม่สามารถออก Invite ใหม่ได้';
    } finally {
      invitationMutationId = '';
    }
  }

  onMount(() => {
    isInLineClient = /\bLine\//i.test(navigator.userAgent);
    void loadOrganization();
  });

  async function assignAccount(): Promise<void> {
    if (!selectedAccountId) { formError = 'กรุณาเลือก LINE Account'; return; }
    if (!memberAssignableRoles.includes(selectedRole)) { formError = 'คุณไม่มีสิทธิ์มอบ role นี้'; return; }
    if (selectedCanOverride && (!canGrantMemberOverride || selectedRole !== 'approver')) { formError = 'Can Override ใช้ได้กับ approver และผู้มอบสิทธิ์ต้องเป็น admin'; return; }
    const account = assignableAccounts.find((item) => item.id === selectedAccountId);
    if (!account) { formError = 'ไม่พบบัญชีที่เลือกใน tenant ปัจจุบัน'; return; }
    accountAssigning = true;
    formError = '';
    try {
      await assignOuMember(getSupabaseBrowserClient(), {
        ouId: selectedOuId,
        churchMemberId: account.churchMemberId,
        permission: selectedRole,
        canOverride: selectedCanOverride
      });
      assignModalOpen = false;
      await loadMembers(selectedOuId);
      showToast(`เพิ่ม ${account.displayName} เป็น ${roleOptions.find((role) => role.id === selectedRole)?.label} แล้ว`);
    } catch (error) {
      formError = error instanceof Error ? error.message : 'ไม่สามารถ Assign Account ได้';
    } finally {
      accountAssigning = false;
    }
  }

  async function handleRoleChange(event: Event, assignmentId: string): Promise<void> {
    const role = (event.currentTarget as HTMLSelectElement).value as Role;
    const assignment = assignments.find((item) => item.id === assignmentId);
    if (!assignment?.canEdit || !memberAssignableRoles.includes(role)) {
      organizationError = 'คุณไม่มีสิทธิ์เปลี่ยน assignment นี้';
      return;
    }
    memberMutationId = assignmentId;
    organizationError = '';
    try {
      await updateOuMemberAssignment(getSupabaseBrowserClient(), {
        assignmentId,
        permission: role,
        canOverride: role === 'approver' ? assignment.canOverride : false
      });
      await loadMembers(selectedOuId);
      showToast('อัปเดต role และบันทึกลงฐานข้อมูลแล้ว');
    } catch (error) {
      organizationError = error instanceof Error ? error.message : 'ไม่สามารถอัปเดต role ได้';
      await loadMembers(selectedOuId);
    } finally {
      memberMutationId = '';
    }
  }

  async function handleOverrideChange(event: Event, assignmentId: string): Promise<void> {
    const canOverride = (event.currentTarget as HTMLInputElement).checked;
    const assignment = assignments.find((item) => item.id === assignmentId);
    if (!assignment?.canEdit || !canGrantMemberOverride || assignment.role !== 'approver') {
      organizationError = 'คุณไม่มีสิทธิ์เปลี่ยน Can Override ของ assignment นี้';
      return;
    }
    memberMutationId = assignmentId;
    organizationError = '';
    try {
      await updateOuMemberAssignment(getSupabaseBrowserClient(), {
        assignmentId,
        permission: assignment.role,
        canOverride
      });
      await loadMembers(selectedOuId);
      showToast('อัปเดต Can Override และบันทึกลงฐานข้อมูลแล้ว');
    } catch (error) {
      organizationError = error instanceof Error ? error.message : 'ไม่สามารถอัปเดต Can Override ได้';
      await loadMembers(selectedOuId);
    } finally {
      memberMutationId = '';
    }
  }

  function openRemoveAssignment(assignment: Assignment): void {
    removeTarget = assignment;
    removeReason = '';
    formError = '';
  }

  async function removeAssignment(): Promise<void> {
    if (!removeTarget) return;
    if (!removeTarget.canRemove) {
      formError = 'คุณไม่มีสิทธิ์นำ assignment นี้ออก';
      return;
    }
    if (!removeReason.trim()) {
      formError = 'กรุณาระบุเหตุผลในการนำสมาชิกออก';
      return;
    }
    const account = getAccount(removeTarget.accountId);
    memberMutationId = removeTarget.id;
    formError = '';
    try {
      await removeOuMember(getSupabaseBrowserClient(), {
        assignmentId: removeTarget.id,
        reason: removeReason.trim()
      });
      removeTarget = null;
      removeReason = '';
      await loadMembers(selectedOuId);
      showToast(`นำ ${account.displayName} ออกจาก ${selectedOu.name} แล้ว โดยบัญชี LINE ยังอยู่ในระบบ`);
    } catch (error) {
      formError = error instanceof Error ? error.message : 'ไม่สามารถนำสมาชิกออกจาก OU ได้';
    } finally {
      memberMutationId = '';
    }
  }

  function closeAllModals(): void {
    createModalOpen = false;
    assignModalOpen = false;
    inviteModalOpen = false;
    editModalOpen = false;
    deleteOuModalOpen = false;
    removeTarget = null;
    revokeInviteTarget = null;
    reissueInviteTarget = null;
  }
</script>

<svelte:head><title>Organization | CSMS</title></svelte:head>
<svelte:window on:keydown={(event) => event.key === 'Escape' && closeAllModals()} />

<div class="app-page space-y-5">
  <section class="app-card relative overflow-hidden p-4 sm:p-5 lg:p-6" aria-labelledby="organization-title">
    <div class="pointer-events-none absolute -right-16 -top-20 h-64 w-64 rounded-full bg-sky-200/40 blur-3xl"></div>
    <div class="relative flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
      <div class="max-w-2xl">
        <span class="inline-flex items-center gap-2 rounded-full border border-sky-200 bg-sky-50 px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-sky-800"><Building2 size={14} /> โครงสร้างองค์กร</span>
        <h1 id="organization-title" class="mt-3 text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">องค์กรและการกำหนดสิทธิ์</h1>
        <p class="mt-2 text-sm leading-6 text-slate-600 sm:text-[0.95rem]">จัดการลำดับชั้น OU พร้อมกำหนด LINE Account และ role แยกตามหน่วยงาน</p>
      </div>
      <button type="button" class="app-button-primary app-focus inline-flex items-center justify-center gap-2 disabled:opacity-50" disabled={!selectedOu} on:click={openCreateModal}><CirclePlus size={18} /> สร้าง OU ใหม่</button>
    </div>

  </section>

  {#if organizationError}
    <p class="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700" role="alert">
      เชื่อมต่อข้อมูล Organization ไม่สำเร็จ: {organizationError}
    </p>
  {/if}

  {#if organizationLoading}
    <div class="app-card px-5 py-14 text-center text-sm text-slate-500">กำลังโหลดโครงสร้างองค์กรจากฐานข้อมูล...</div>
  {:else if selectedOu}
  <div class="grid gap-5 xl:grid-cols-[20rem_minmax(0,1fr)]">
    <aside class="app-card h-fit overflow-hidden xl:sticky xl:top-20" aria-labelledby="tree-title">
      <div class="border-b border-slate-100 p-4 sm:p-5">
        <div class="flex items-center justify-between gap-3"><div><h2 id="tree-title" class="app-section-title">โครงสร้าง OU</h2><p class="app-section-copy">เลือกหน่วยงานเพื่อจัดการ</p></div><span class="rounded-full bg-sky-50 px-2.5 py-1 text-xs font-semibold text-sky-700">{authorizedOus.length} OU</span></div>
        <label class="relative mt-4 block"><span class="sr-only">ค้นหา OU</span><Search class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={16} /><input class="app-input pl-10" type="search" placeholder="ค้นหาชื่อหรือรหัส..." bind:value={treeSearch} /></label>
      </div>
      <nav class="max-h-[32rem] space-y-1 overflow-y-auto p-2.5" aria-label="Organization tree">
        {#each visibleOus as ou}
          <div class="flex items-center gap-1" style={`padding-left: ${treeSearch ? 0 : getDisplayDepth(ou) * 0.75}rem`}>
            {#if hasChildren(ou.id) && !treeSearch}
              <button type="button" class="app-focus flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-slate-400 hover:bg-slate-100 hover:text-slate-700" aria-label={`${expandedIds.has(ou.id) ? 'ย่อ' : 'ขยาย'} ${ou.name}`} on:click={() => toggleExpanded(ou.id)}>{#if expandedIds.has(ou.id)}<ChevronDown size={16} />{:else}<ChevronRight size={16} />{/if}</button>
            {:else}<span class="h-8 w-8 shrink-0"></span>{/if}
            <button type="button" class={`app-focus min-w-0 flex-1 rounded-xl border px-3 py-2.5 text-left transition ${selectedOuId === ou.id ? 'border-sky-200 bg-gradient-to-r from-sky-50 to-emerald-50 shadow-sm' : 'border-transparent hover:bg-slate-50'}`} on:click={() => selectOu(ou.id)}>
              <span class="flex items-center justify-between gap-2"><span class={`truncate text-sm font-semibold ${selectedOuId === ou.id ? 'text-sky-900' : 'text-slate-700'}`}>{ou.name}</span>{#if ou.allowDataEntry}<span class="h-2 w-2 shrink-0 rounded-full bg-emerald-500" title="รับข้อมูล"></span>{/if}</span>
              <span class="mt-0.5 block truncate text-[0.68rem] text-slate-400">{getOuTypeLabel(ou.type)}</span>
            </button>
          </div>
        {:else}
          <div class="px-4 py-10 text-center"><Search class="mx-auto text-slate-300" size={24} /><p class="mt-2 text-sm text-slate-500">ไม่พบ OU ที่ค้นหา</p></div>
        {/each}
      </nav>
    </aside>

    <section class="min-w-0 space-y-5">
      <article class="app-card overflow-hidden">
        <div class="relative bg-gradient-to-br from-slate-950 via-sky-950 to-teal-900 p-5 text-white sm:p-6">
          <div class="pointer-events-none absolute right-0 top-0 h-40 w-40 rounded-full bg-sky-400/15 blur-3xl"></div>
          <div class="relative flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
            <div class="flex min-w-0 items-start gap-4">
              <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-white/10 text-sky-200 ring-1 ring-white/15"><Building2 size={24} /></span>
              <div class="min-w-0"><p class="text-xs font-semibold uppercase tracking-[0.18em] text-sky-300">{getOuTypeLabel(selectedOu.type)}</p><h2 class="mt-1 truncate text-2xl font-semibold">{selectedOu.name}</h2><p class="mt-2 flex items-start gap-1.5 text-xs leading-5 text-slate-300"><MapPin class="mt-0.5 shrink-0" size={14} /><span>{getPath(selectedOu)}</span></p></div>
            </div>
            <div class="flex flex-wrap gap-2"><button type="button" class="app-focus inline-flex min-h-10 items-center justify-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 text-sm font-semibold text-white hover:bg-white/15" on:click={openEditModal}><Pencil size={16} /> แก้ไขข้อมูล</button>{#if selectedOu.parentId !== null}<button type="button" class="app-focus inline-flex min-h-10 items-center justify-center gap-2 rounded-full border border-rose-300/30 bg-rose-500/15 px-4 text-sm font-semibold text-rose-100 hover:bg-rose-500/25" on:click={openDeleteOuModal}><Trash2 size={16} /> ปิดใช้งาน</button>{/if}</div>
          </div>
          <div class="relative mt-5 flex flex-wrap gap-2"><span class="rounded-full bg-white/10 px-3 py-1 text-xs text-slate-200">ระดับ {selectedOu.level}</span><span class="rounded-full bg-white/10 px-3 py-1 text-xs text-slate-200">OU ลูก {childCount}</span><span class={`rounded-full px-3 py-1 text-xs ${selectedOu.allowDataEntry ? 'bg-emerald-400/20 text-emerald-200' : 'bg-white/10 text-slate-200'}`}>{selectedOu.allowDataEntry ? 'รับข้อมูลรายสัปดาห์' : 'สรุปข้อมูลจาก OU ลูก'}</span></div>
        </div>
        <div class="flex gap-1 overflow-x-auto border-b border-slate-100 bg-white px-3 pt-2 sm:px-5">
          <button type="button" class={`app-focus min-w-max border-b-2 px-4 py-3 text-sm font-semibold ${activeTab === 'overview' ? 'border-sky-600 text-sky-800' : 'border-transparent text-slate-500'}`} on:click={() => (activeTab = 'overview')}>ข้อมูล OU</button>
          <button type="button" class={`app-focus min-w-max border-b-2 px-4 py-3 text-sm font-semibold ${activeTab === 'members' ? 'border-sky-600 text-sky-800' : 'border-transparent text-slate-500'}`} on:click={() => (activeTab = 'members')}>LINE Accounts & Roles <span class="ml-1 rounded-full bg-slate-100 px-2 py-0.5 text-[0.68rem]">{selectedMembers.length}</span></button>
        </div>

        {#if activeTab === 'overview'}
          <div class="grid gap-4 p-4 sm:grid-cols-2 sm:p-5">
            <div class="rounded-2xl border border-slate-200 bg-slate-50/70 p-4"><p class="text-xs font-medium text-slate-500">OU แม่</p><p class="mt-2 text-sm font-semibold text-slate-900">{getParent(selectedOu)?.name ?? 'ไม่มี — หน่วยงานราก'}</p></div>
            <div class="rounded-2xl border border-slate-200 bg-slate-50/70 p-4"><p class="text-xs font-medium text-slate-500">ประเภท</p><p class="mt-2 text-sm font-semibold text-slate-900">{getOuTypeLabel(selectedOu.type)}</p></div>
            <div class="rounded-2xl border border-slate-200 bg-slate-50/70 p-4"><p class="text-xs font-medium text-slate-500">การรับข้อมูล</p><p class="mt-2 text-sm font-semibold text-slate-900">{selectedOu.allowDataEntry ? 'เปิดรับข้อมูลโดยตรง' : 'ปิด — ใช้ข้อมูลรวมจาก OU ลูก'}</p></div>
            <div class="rounded-2xl border border-slate-200 bg-slate-50/70 p-4"><p class="text-xs font-medium text-slate-500">สถานะ</p><p class="mt-2 inline-flex items-center gap-1.5 text-sm font-semibold text-emerald-700"><CheckCircle2 size={16} /> เปิดใช้งาน</p></div>
            <div class="rounded-2xl border border-sky-200 bg-sky-50 p-4 sm:col-span-2"><div class="flex gap-3"><Info class="mt-0.5 shrink-0 text-sky-700" size={18} /><div><p class="text-sm font-semibold text-sky-900">กฎโครงสร้าง</p><p class="mt-1 text-xs leading-5 text-sky-800">OU รองรับลำดับชั้นไม่จำกัด และแต่ละ OU มี OU แม่ได้เพียงหนึ่งรายการ การลบ OU ที่มี OU ลูกหรือข้อมูลสถิติจะถูกบล็อกโดย Backend</p></div></div></div>
          </div>
        {:else}
          <div>
            <div class="flex flex-col gap-4 border-b border-slate-100 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
              <div><h3 class="app-section-title">สมาชิกและสิทธิ์ใน {selectedOu.name}</h3><p class="app-section-copy">role มีผลเฉพาะ OU นี้และ subtree ตามนโยบาย RLS</p></div>
              <div class="flex flex-col gap-2 sm:flex-row"><button type="button" class="app-button-secondary app-focus inline-flex items-center justify-center gap-2" on:click={openAssignModal}><UserPlus size={17} /> Assign Existing</button><button type="button" class="app-button-primary app-focus inline-flex items-center justify-center gap-2" on:click={openInviteModal}><Link2 size={17} /> สร้าง Invite Link</button></div>
            </div>
            {#if membersLoading}
              <div class="px-5 py-14 text-center text-sm text-slate-500">กำลังโหลดสมาชิกและสิทธิ์จากฐานข้อมูล...</div>
            {:else if selectedMembers.length > 0}
              <div class="divide-y divide-slate-100">
                {#each selectedMembers as assignment}
                  {@const account = getAccount(assignment.accountId)}
                  <article class="grid gap-4 p-4 sm:p-5 lg:grid-cols-[minmax(0,1fr)_13rem_8rem_auto] lg:items-center">
                    <div class="flex min-w-0 items-center gap-3"><span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-sky-500 to-teal-600 text-sm font-bold text-white">{account.displayName.slice(0, 1)}</span><div class="min-w-0"><p class="truncate text-sm font-semibold text-slate-900">{account.displayName}</p><p class="mt-0.5 flex items-center gap-1 truncate text-xs text-slate-500"><Link2 size={12} /> LINE {account.lineUserId}</p><p class="mt-0.5 truncate text-[0.68rem] text-slate-400">เพิ่มเมื่อ {assignment.assignedAt}</p></div></div>
                    <label><span class="mb-1.5 block text-xs font-medium text-slate-500 lg:hidden">Role</span><select class="app-input disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-500" value={assignment.role} disabled={!assignment.canEdit || memberMutationId === assignment.id} on:change={(event) => handleRoleChange(event, assignment.id)}>{#each roleOptions as role}<option value={role.id} disabled={!memberAssignableRoles.includes(role.id)}>{role.label}</option>{/each}</select></label>
                    <label class={`inline-flex min-h-11 items-center justify-center gap-2 rounded-xl border px-3 py-2 text-xs font-medium ${assignment.canOverride ? 'border-amber-200 bg-amber-50 text-amber-800' : 'border-slate-200 bg-slate-50 text-slate-500'}`}><input class="h-4 w-4 accent-amber-600" type="checkbox" checked={assignment.canOverride} disabled={!assignment.canEdit || !canGrantMemberOverride || assignment.role !== 'approver' || memberMutationId === assignment.id} on:change={(event) => handleOverrideChange(event, assignment.id)} /> Override</label>
                    <button type="button" class="app-focus inline-flex min-h-10 items-center justify-center gap-1.5 rounded-xl border border-rose-200 px-3 text-xs font-semibold text-rose-700 hover:bg-rose-50 disabled:cursor-not-allowed disabled:border-slate-200 disabled:text-slate-400" disabled={!assignment.canRemove || memberMutationId === assignment.id} on:click={() => openRemoveAssignment(assignment)}><Trash2 size={15} /> นำออก</button>
                  </article>
                {/each}
              </div>
            {:else}
              <div class="px-5 py-14 text-center"><span class="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-slate-100 text-slate-400"><Users size={26} /></span><h3 class="mt-4 text-sm font-semibold text-slate-800">ยังไม่มี LINE Account ใน OU นี้</h3><p class="mt-1 text-xs text-slate-500">สร้างลิงก์พร้อม role แล้วส่งให้ผู้รับทาง LINE ได้ทันที</p><button type="button" class="app-button-primary mt-5 inline-flex items-center gap-2" on:click={openInviteModal}><Link2 size={17} /> สร้าง Invite Link</button></div>
            {/if}
            <section class="border-t border-slate-100 p-4 sm:p-5" aria-labelledby="invitation-list-title">
              <div class="flex items-center justify-between gap-3"><div><h4 id="invitation-list-title" class="text-sm font-semibold text-slate-900">Invite Links</h4><p class="mt-1 text-xs text-slate-500">ติดตาม pending, accepted, expired และ revoked ของ OU นี้</p></div><span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-600">{invitations.length}</span></div>
              {#if invitations.length > 0}
                <div class="mt-4 space-y-3">
                  {#each invitations as invitation}
                    <article class="flex flex-col gap-3 rounded-2xl border border-slate-200 bg-slate-50/60 p-4 sm:flex-row sm:items-center sm:justify-between">
                      <div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><p class="truncate text-sm font-semibold text-slate-900">{invitation.displayName || 'ไม่ได้ระบุชื่อผู้รับ'}</p><span class={`rounded-full border px-2 py-0.5 text-[0.68rem] font-semibold ${invitationStatusClass(invitation.status)}`}>{invitationStatusLabel(invitation.status)}</span></div><p class="mt-1 text-xs text-slate-500">{roleOptions.find((role) => role.id === invitation.permission)?.label} {invitation.canOverride ? '· Override' : ''} · หมดอายุ {new Intl.DateTimeFormat('th-TH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(invitation.expiresAt))}</p></div>
                      {#if invitation.status !== 'accepted'}<div class="flex shrink-0 gap-2">{#if invitation.status === 'pending'}<button type="button" class="app-button-secondary min-h-9 px-3 text-xs" disabled={invitationMutationId === invitation.invitationId} aria-label={`เพิกถอน Invite ของ ${invitation.displayName || invitation.permission}`} on:click={() => openRevokeInvitation(invitation)}>เพิกถอน</button>{/if}<button type="button" class="app-button-secondary min-h-9 px-3 text-xs" disabled={invitationMutationId === invitation.invitationId} aria-label={`ออก Invite ใหม่ให้ ${invitation.displayName || invitation.permission}`} on:click={() => openReissueInvitation(invitation)}>ออกลิงก์ใหม่</button></div>{/if}
                    </article>
                  {/each}
                </div>
              {:else}<p class="mt-4 rounded-2xl border border-dashed border-slate-200 px-4 py-6 text-center text-xs text-slate-500">ยังไม่มีประวัติ Invite ใน OU นี้</p>{/if}
            </section>
          </div>
        {/if}
      </article>

      <div class="app-card flex gap-3 p-4 sm:p-5"><ShieldCheck class="mt-0.5 shrink-0 text-emerald-700" size={20} /><div><p class="text-sm font-semibold text-slate-900">Backend ยังคงเป็นผู้ตัดสินสิทธิ์สุดท้าย</p><p class="mt-1 text-xs leading-5 text-slate-500">ตัวเลือกในหน้านี้ช่วยจัดการ assignment แต่ Supabase RLS จะบังคับขอบเขต OU และป้องกันการให้สิทธิ์นอก subtree ที่ผู้ดูแลเข้าถึงได้</p></div></div>
    </section>
  </div>
  {/if}

  {#if toastMessage}
    <div class="fixed bottom-20 right-4 z-40 max-w-sm rounded-2xl border border-emerald-200 bg-white px-4 py-3 shadow-xl md:bottom-5" role="status"><div class="flex gap-3"><CheckCircle2 class="mt-0.5 shrink-0 text-emerald-600" size={18} /><div><p class="text-sm font-semibold text-slate-900">ดำเนินการแล้ว</p><p class="mt-0.5 text-xs leading-5 text-slate-600">{toastMessage}</p></div><button class="ml-auto text-slate-400" type="button" aria-label="ปิดข้อความ" on:click={() => (toastMessage = '')}><X size={16} /></button></div></div>
  {/if}
</div>

{#if createModalOpen}
  <div class="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4" role="dialog" aria-modal="true" aria-labelledby="create-ou-title">
    <button type="button" class="absolute inset-0 h-full w-full bg-slate-950/55 backdrop-blur-sm" aria-label="ปิดหน้าต่างสร้าง OU" on:click={() => (createModalOpen = false)}></button>
    <section class="relative max-h-[92vh] w-full overflow-y-auto rounded-t-[1.5rem] bg-white p-5 shadow-2xl sm:max-w-xl sm:rounded-[1.5rem] sm:p-6">
      <div class="flex items-start justify-between gap-4"><div><span class="flex h-11 w-11 items-center justify-center rounded-2xl bg-sky-50 text-sky-700"><CirclePlus size={22} /></span><h2 id="create-ou-title" class="mt-4 text-xl font-semibold text-slate-950">สร้าง OU ใหม่</h2><p class="mt-1 text-sm text-slate-500">OU ใหม่จะอยู่ภายใต้หน่วยงานแม่ที่เลือก</p></div><button type="button" class="app-focus rounded-full p-2 text-slate-400 hover:bg-slate-100" aria-label="ปิด" on:click={() => (createModalOpen = false)}><X size={20} /></button></div>
      {#if formError}<p class="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-sm text-rose-700">{formError}</p>{/if}
      <div class="mt-5 grid gap-4 sm:grid-cols-2">
        <label class="sm:col-span-2"><span class="text-sm font-medium text-slate-700">OU แม่</span><select class="app-input mt-2" bind:value={newOuParentId}>{#each authorizedOus as ou}<option value={ou.id}>{'— '.repeat(getDisplayDepth(ou))}{ou.name}</option>{/each}</select></label>
        <label><span class="text-sm font-medium text-slate-700">ชื่อ OU</span><input class="app-input mt-2" bind:value={newOuName} placeholder="เช่น กลุ่ม E" /></label>
        <label><span class="text-sm font-medium text-slate-700">ประเภท</span><select class="app-input mt-2" bind:value={newOuType} disabled={ouCreating} on:change={handleOuTypeChange}>{#each ouTypeOptions as item}<option value={item.id}>{item.label}</option>{/each}</select><span class="mt-1 block text-xs text-slate-500">เลือก Type ที่เปิดใช้งานได้โดยไม่ต้องเรียงตามลำดับ</span></label>
        <label class="flex items-center gap-3 rounded-2xl border border-slate-200 px-4 py-3 sm:self-end"><input class="h-4 w-4 accent-sky-600" type="checkbox" bind:checked={newOuAllowDataEntry} /><span><span class="block text-sm font-medium text-slate-700">รับข้อมูลรายสัปดาห์</span><span class="block text-xs text-slate-400">ข้อมูลตรงของ OU นี้เท่านั้น และจะรวมเพิ่มกับ OU ลูก</span></span></label>
      </div>
      {#if willDisableParentDataEntry}
        <div class="mt-4 flex gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-4" role="alert"><AlertTriangle class="mt-0.5 shrink-0 text-amber-700" size={18} /><div><p class="text-sm font-semibold text-amber-950">OU แม่จะหยุดรับข้อมูลอัตโนมัติ</p><p class="mt-1 text-xs leading-5 text-amber-800">เมื่อสร้าง OU นี้ ระบบจะเปลี่ยน “{selectedNewOuParent?.name}” เป็นสรุปข้อมูลจาก OU ลูก เพื่อป้องกันการนับข้อมูลซ้ำ</p></div></div>
      {/if}
      <div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" class="app-button-secondary" disabled={ouCreating} on:click={() => (createModalOpen = false)}>ยกเลิก</button><button type="button" class="app-button-primary" disabled={ouCreating || !newOuName.trim() || !newOuType} on:click={createOu}>{ouCreating ? 'กำลังสร้าง...' : 'สร้าง OU'}</button></div>
    </section>
  </div>
{/if}

{#if editModalOpen}
  <div class="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4" role="dialog" aria-modal="true" aria-labelledby="edit-ou-title">
    <button type="button" class="absolute inset-0 h-full w-full bg-slate-950/55 backdrop-blur-sm" aria-label="ปิดหน้าต่างแก้ไข OU" on:click={() => (editModalOpen = false)}></button>
    <section class="relative max-h-[92vh] w-full overflow-y-auto rounded-t-[1.5rem] bg-white p-5 shadow-2xl sm:max-w-2xl sm:rounded-[1.5rem] sm:p-6">
      <div class="flex items-start justify-between gap-4"><div><span class="flex h-11 w-11 items-center justify-center rounded-2xl bg-sky-50 text-sky-700"><Pencil size={22} /></span><h2 id="edit-ou-title" class="mt-4 text-xl font-semibold text-slate-950">แก้ไขข้อมูล OU</h2><p class="mt-1 text-sm text-slate-500">ชื่อ รหัส ประเภท และ OU แม่จะบันทึกลงฐานข้อมูลจริง</p></div><button type="button" class="app-focus rounded-full p-2 text-slate-400 hover:bg-slate-100" aria-label="ปิด" disabled={ouUpdating} on:click={() => (editModalOpen = false)}><X size={20} /></button></div>
      {#if formError}<p class="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-sm text-rose-700" role="alert">{formError}</p>{/if}
      <div class="mt-5 grid gap-4 sm:grid-cols-2">
        <label><span class="text-sm font-medium text-slate-700">ชื่อ OU</span><input class="app-input mt-2" bind:value={editOuName} maxlength="255" /></label>
        <label><span class="text-sm font-medium text-slate-700">ประเภท</span><select class="app-input mt-2" bind:value={editOuType}>{#each ouTypeOptions as item}<option value={item.id}>{item.label}</option>{/each}{#if !ouTypeOptions.some((item) => item.id === editOuType)}<option value={editOuType}>{getOuTypeLabel(editOuType)} (ปิดใช้งานแล้ว)</option>{/if}</select></label>
        <label><span class="text-sm font-medium text-slate-700">OU แม่</span><select class="app-input mt-2 disabled:bg-slate-100" bind:value={editOuParentId} disabled={selectedOu.parentId === null}>{#if selectedOu.parentId === null}<option value="">ไม่มี — Root OU</option>{:else}{#each authorizedOus.filter((ou) => ou.id !== selectedOu.id && !isDescendant(ou.id, selectedOu.id)) as ou}<option value={ou.id}>{'— '.repeat(getDisplayDepth(ou))}{ou.name}</option>{/each}{/if}</select></label>
        <label class="sm:col-span-2"><span class="text-sm font-medium text-slate-700">รายละเอียด</span><textarea class="app-input mt-2 min-h-24 resize-y" bind:value={editOuDescription} maxlength="2000"></textarea></label>
        <label><span class="text-sm font-medium text-slate-700">ลำดับแสดงผล</span><input class="app-input mt-2" type="number" min="0" step="1" bind:value={editOuSortOrder} /></label>
        <label class="flex items-center gap-3 rounded-2xl border border-slate-200 px-4 py-3 sm:self-end"><input class="h-4 w-4 accent-sky-600" type="checkbox" bind:checked={editOuAllowDataEntry} /><span><span class="block text-sm font-medium text-slate-700">รับข้อมูลรายสัปดาห์</span><span class="block text-xs text-slate-400">ข้อมูลตรงของ OU นี้จะรวมเพิ่มกับ OU ลูก</span></span></label>
      </div>
      {#if editOuAllowDataEntry && !selectedOu.allowDataEntry && hasChildren(selectedOu.id)}
        <label class="mt-4 flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-4"><input class="mt-0.5 h-4 w-4 accent-amber-600" type="checkbox" bind:checked={confirmAdditiveParentEntry} /><span class="text-xs leading-5 text-amber-900">ฉันยืนยันว่าข้อมูลตรงของ OU แม่เป็นกิจกรรมคนละส่วนกับ OU ลูก และเข้าใจว่า Backend จะนำมารวมแบบ additive</span></label>
      {/if}
      <div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" class="app-button-secondary" disabled={ouUpdating} on:click={() => (editModalOpen = false)}>ยกเลิก</button><button type="button" class="app-button-primary disabled:opacity-60" disabled={ouUpdating || !editOuName.trim() || !editOuType} on:click={saveOu}>{ouUpdating ? 'กำลังบันทึก...' : 'บันทึกการแก้ไข'}</button></div>
    </section>
  </div>
{/if}

{#if deleteOuModalOpen}
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4" role="alertdialog" aria-modal="true" aria-labelledby="delete-ou-title">
    <button type="button" class="absolute inset-0 h-full w-full bg-slate-950/55 backdrop-blur-sm" aria-label="ยกเลิก" on:click={() => (deleteOuModalOpen = false)}></button>
    <section class="relative w-full max-w-md rounded-[1.5rem] bg-white p-5 shadow-2xl sm:p-6"><span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-rose-50 text-rose-700"><Trash2 size={22} /></span><h2 id="delete-ou-title" class="mt-4 text-xl font-semibold text-slate-950">ปิดใช้งาน {selectedOu.name}?</h2><p class="mt-2 text-sm leading-6 text-slate-600">ระบบจะทำ soft delete และเก็บประวัติไว้ การดำเนินการจะถูกบล็อกหากยังมี OU ลูกหรือข้อมูลรายงาน</p>{#if formError}<p class="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-sm text-rose-700" role="alert">{formError}</p>{/if}<label class="mt-4 block"><span class="text-sm font-medium text-slate-700">เหตุผล</span><textarea class="app-input mt-2 min-h-24 resize-y" bind:value={deleteOuReason} maxlength="500" placeholder="ระบุเหตุผลเพื่อบันทึกใน audit log"></textarea></label><div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" class="app-button-secondary" disabled={ouDeleting} on:click={() => (deleteOuModalOpen = false)}>ยกเลิก</button><button type="button" class="min-h-11 rounded-full border border-rose-700 bg-rose-700 px-4 text-sm font-semibold text-white hover:bg-rose-800 disabled:opacity-60" disabled={ouDeleting || !deleteOuReason.trim()} on:click={deleteOu}>{ouDeleting ? 'กำลังปิดใช้งาน...' : 'ยืนยัน Soft Delete'}</button></div></section>
  </div>
{/if}

{#if inviteModalOpen}
  <div class="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4" role="dialog" aria-modal="true" aria-labelledby="invite-title">
    <button type="button" class="absolute inset-0 h-full w-full bg-slate-950/55 backdrop-blur-sm" aria-label="ปิดหน้าต่าง Invite Link" on:click={() => (inviteModalOpen = false)}></button>
    <section class="relative max-h-[92vh] w-full overflow-y-auto rounded-t-[1.5rem] bg-white p-5 shadow-2xl sm:max-w-xl sm:rounded-[1.5rem] sm:p-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <span class="flex h-11 w-11 items-center justify-center rounded-2xl bg-sky-50 text-sky-700"><Link2 size={22} /></span>
          <h2 id="invite-title" class="mt-4 text-xl font-semibold text-slate-950">สร้าง Invite Link</h2>
          <p class="mt-1 text-sm text-slate-500">กำหนดสิทธิ์ใน <strong>{selectedOu.name}</strong> แล้วส่งลิงก์ให้ผู้รับทาง LINE</p>
        </div>
        <button type="button" class="app-focus rounded-full p-2 text-slate-400 hover:bg-slate-100" aria-label="ปิด" on:click={() => (inviteModalOpen = false)}><X size={20} /></button>
      </div>

      {#if formError}<p class="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-sm text-rose-700">{formError}</p>{/if}

      {#if inviteLink}
        <div class="mt-5 space-y-4">
          <div class="rounded-2xl border border-emerald-200 bg-emerald-50 p-4">
            <div class="flex gap-3"><CheckCircle2 class="mt-0.5 shrink-0 text-emerald-700" size={18} /><div><p class="text-sm font-semibold text-emerald-900">สร้างลิงก์แล้ว</p><p class="mt-1 text-xs leading-5 text-emerald-800">ลิงก์ใช้ได้ครั้งเดียว สิทธิ์ {roleOptions.find((role) => role.id === inviteRole)?.label} ถูกเก็บไว้ฝั่ง Backend</p></div></div>
          </div>
          <label>
            <span class="text-sm font-medium text-slate-700">Invite Link</span>
            <textarea class="app-input mt-2 min-h-24 resize-none text-xs" readonly value={inviteLink}></textarea>
          </label>
          <p class="flex items-center gap-2 text-xs text-slate-500"><CalendarDays size={15} /> หมดอายุ {new Intl.DateTimeFormat('th-TH', { dateStyle: 'long', timeStyle: 'short' }).format(new Date(inviteExpiresAt))}</p>
          {#if isInLineClient}
            <button type="button" class="app-button-primary app-focus inline-flex w-full items-center justify-center gap-2 disabled:cursor-not-allowed disabled:opacity-60" disabled={inviteSharing} on:click={shareInviteToLineFriend}><Send size={17} /> {inviteSharing ? 'กำลังเปิดรายชื่อเพื่อน...' : 'เลือกเพื่อนใน LINE'}</button>
          {/if}
          <button type="button" class="app-button-secondary app-focus inline-flex w-full items-center justify-center gap-2" on:click={copyInviteLink}><Copy size={17} /> Copy Invite Link</button>
        </div>
      {:else}
        <div class="mt-5 space-y-4">
          <label><span class="text-sm font-medium text-slate-700">ชื่อผู้รับ (ไม่บังคับ)</span><input class="app-input mt-2" bind:value={inviteDisplayName} maxlength="255" placeholder="ใช้ช่วยจำว่าออกลิงก์ให้ใคร" /></label>
          <label>
            <span class="text-sm font-medium text-slate-700">Role</span>
            <select class="app-input mt-2" bind:value={inviteRole} on:change={handleInviteRoleChange}>
              {#each roleOptions as role}<option value={role.id}>{role.label} ({role.id})</option>{/each}
            </select>
            <span class="mt-2 block text-xs leading-5 text-slate-500">{roleOptions.find((role) => role.id === inviteRole)?.description}</span>
          </label>
          {#if inviteRole === 'approver'}
            <label class="flex items-center gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3"><input class="h-4 w-4 accent-amber-600" type="checkbox" bind:checked={inviteCanOverride} /><span><span class="block text-sm font-medium text-amber-900">อนุญาต Override</span><span class="block text-xs text-amber-700">ใช้อนุมัติกรณีพิเศษตามนโยบายระบบ</span></span></label>
          {/if}
          <label><span class="text-sm font-medium text-slate-700">อายุลิงก์</span><select class="app-input mt-2" bind:value={inviteExpiresInDays}><option value={1}>1 วัน</option><option value={3}>3 วัน</option><option value={7}>7 วัน</option><option value={14}>14 วัน</option><option value={30}>30 วัน</option></select></label>
          <div class="flex items-start gap-3 rounded-2xl border border-sky-200 bg-sky-50 p-4"><ShieldCheck class="mt-0.5 shrink-0 text-sky-700" size={17} /><span class="text-xs leading-5 text-sky-800">ผู้รับต้องเปิดลิงก์และยืนยัน LINE Login ระบบจึงจะผูกบัญชีกับ Tenant, OU และ role นี้ ผู้ดูแลระดับ manager ไม่สามารถออกสิทธิ์ admin หรือ override ได้</span></div>
        </div>
        <div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" class="app-button-secondary" on:click={() => (inviteModalOpen = false)}>ยกเลิก</button><button type="button" class="app-button-primary disabled:opacity-60" disabled={inviteCreating} on:click={createInvite}>{inviteCreating ? 'กำลังสร้าง...' : 'สร้าง Invite Link'}</button></div>
      {/if}
    </section>
  </div>
{/if}

{#if assignModalOpen}
  <div class="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4" role="dialog" aria-modal="true" aria-labelledby="assign-title">
    <button type="button" class="absolute inset-0 h-full w-full bg-slate-950/55 backdrop-blur-sm" aria-label="ปิดหน้าต่าง assign account" on:click={() => (assignModalOpen = false)}></button>
    <section class="relative max-h-[92vh] w-full overflow-y-auto rounded-t-[1.5rem] bg-white p-5 shadow-2xl sm:max-w-xl sm:rounded-[1.5rem] sm:p-6">
      <div class="flex items-start justify-between gap-4"><div><span class="flex h-11 w-11 items-center justify-center rounded-2xl bg-emerald-50 text-emerald-700"><UserPlus size={22} /></span><h2 id="assign-title" class="mt-4 text-xl font-semibold text-slate-950">Assign LINE Account</h2><p class="mt-1 text-sm text-slate-500">กำหนดสิทธิ์ใน <strong>{selectedOu.name}</strong></p></div><button type="button" class="app-focus rounded-full p-2 text-slate-400 hover:bg-slate-100" aria-label="ปิด" on:click={() => (assignModalOpen = false)}><X size={20} /></button></div>
      {#if formError}<p class="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-sm text-rose-700">{formError}</p>{/if}
      <div class="mt-5 space-y-4">
        <label><span class="text-sm font-medium text-slate-700">ค้นหา LINE Account</span><span class="mt-2 flex gap-2"><input class="app-input" type="search" bind:value={accountSearch} placeholder="ชื่อ, LINE User ID หรืออีเมล" on:keydown={(event) => event.key === 'Enter' && loadAssignableAccounts()} /><button type="button" class="app-button-secondary shrink-0" disabled={accountSearchLoading} on:click={loadAssignableAccounts}>{accountSearchLoading ? 'กำลังค้นหา...' : 'ค้นหา'}</button></span></label>
        <label><span class="text-sm font-medium text-slate-700">LINE Account</span><select class="app-input mt-2" bind:value={selectedAccountId} disabled={accountSearchLoading}><option value="">เลือกบัญชี...</option>{#each availableAccounts as account}<option value={account.id}>{account.displayName} · {account.lineUserId}</option>{/each}</select>{#if !accountSearchLoading && availableAccounts.length === 0}<span class="mt-2 block text-xs text-slate-500">ไม่พบบัญชีที่เพิ่ม role นี้ได้ใน tenant ปัจจุบัน</span>{/if}</label>
        <label><span class="text-sm font-medium text-slate-700">Role</span><select class="app-input mt-2" bind:value={selectedRole} on:change={() => { selectedAccountId = ''; if (selectedRole !== 'approver') selectedCanOverride = false; }}>{#each roleOptions.filter((role) => memberAssignableRoles.includes(role.id)) as role}<option value={role.id}>{role.label} ({role.id})</option>{/each}</select><span class="mt-2 block text-xs leading-5 text-slate-500">{roleOptions.find((role) => role.id === selectedRole)?.description}</span></label>
        {#if selectedRole === 'approver' && canGrantMemberOverride}<label class="flex items-center gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3"><input class="h-4 w-4 accent-amber-600" type="checkbox" bind:checked={selectedCanOverride} /><span><span class="block text-sm font-medium text-amber-900">อนุญาต Override</span><span class="block text-xs text-amber-700">สิทธิ์นี้จะถูกตรวจและบันทึก audit โดย Backend</span></span></label>{/if}
        <div class="flex items-start gap-3 rounded-2xl border border-sky-200 bg-sky-50 p-4"><ShieldCheck class="mt-0.5 shrink-0 text-sky-700" size={17} /><span><span class="block text-sm font-semibold text-sky-900">ขอบเขตการมอบสิทธิ์</span><span class="mt-0.5 block text-xs leading-5 text-sky-800">{canGrantMemberOverride ? 'Admin มอบ role ได้ทุกประเภท และเปิด Can Override ได้เฉพาะ approver' : 'Manager มอบได้เฉพาะ manager, data_entry, approver และ viewer โดย Can Override ต้องเป็น false'}</span></span></div>
      </div>
      <div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" class="app-button-secondary" disabled={accountAssigning} on:click={() => (assignModalOpen = false)}>ยกเลิก</button><button type="button" class="app-button-primary disabled:opacity-60" disabled={accountAssigning || !selectedAccountId} on:click={assignAccount}>{accountAssigning ? 'กำลังบันทึก...' : 'Assign Account'}</button></div>
    </section>
  </div>
{/if}

{#if removeTarget}
  {@const removeAccount = getAccount(removeTarget.accountId)}
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4" role="alertdialog" aria-modal="true" aria-labelledby="remove-title">
    <button type="button" class="absolute inset-0 h-full w-full bg-slate-950/55 backdrop-blur-sm" aria-label="ยกเลิก" on:click={() => (removeTarget = null)}></button>
    <section class="relative w-full max-w-md rounded-[1.5rem] bg-white p-5 shadow-2xl sm:p-6"><span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-rose-50 text-rose-700"><Trash2 size={22} /></span><h2 id="remove-title" class="mt-4 text-xl font-semibold text-slate-950">นำออกจาก OU นี้?</h2><p class="mt-2 text-sm leading-6 text-slate-600">จะนำ <strong>{removeAccount.displayName}</strong> และ role <strong>{removeTarget.role}</strong> ออกจาก <strong>{selectedOu.name}</strong></p><div class="mt-4 flex gap-2 rounded-xl bg-sky-50 p-3 text-xs leading-5 text-sky-800"><Info class="mt-0.5 shrink-0" size={16} /><span>บัญชี LINE และ assignment ใน OU อื่นจะไม่ถูกลบ</span></div>{#if formError}<p class="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-sm text-rose-700">{formError}</p>{/if}<label class="mt-4 block"><span class="text-sm font-medium text-slate-700">เหตุผล</span><textarea class="app-input mt-2 min-h-24 resize-y" bind:value={removeReason} maxlength="500" placeholder="ระบุเหตุผลเพื่อบันทึกใน audit log"></textarea></label><div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" class="app-button-secondary" disabled={memberMutationId === removeTarget.id} on:click={() => (removeTarget = null)}>ยกเลิก</button><button type="button" class="min-h-11 rounded-full border border-rose-700 bg-rose-700 px-4 text-sm font-semibold text-white hover:bg-rose-800 disabled:opacity-60" disabled={memberMutationId === removeTarget.id || !removeReason.trim()} on:click={removeAssignment}>{memberMutationId === removeTarget.id ? 'กำลังนำออก...' : 'นำออกจาก OU'}</button></div></section>
  </div>
{/if}

{#if revokeInviteTarget}
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4" role="alertdialog" aria-modal="true" aria-labelledby="revoke-invite-title">
    <button type="button" class="absolute inset-0 h-full w-full bg-slate-950/55 backdrop-blur-sm" aria-label="ยกเลิก" on:click={() => (revokeInviteTarget = null)}></button>
    <section class="relative w-full max-w-md rounded-[1.5rem] bg-white p-5 shadow-2xl sm:p-6"><span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-rose-50 text-rose-700"><Link2 size={22} /></span><h2 id="revoke-invite-title" class="mt-4 text-xl font-semibold text-slate-950">เพิกถอน Invite Link?</h2><p class="mt-2 text-sm leading-6 text-slate-600">ลิงก์ของ <strong>{revokeInviteTarget.displayName || revokeInviteTarget.permission}</strong> จะใช้รับสิทธิ์ไม่ได้อีก แต่ประวัติจะยังอยู่ใน audit log</p>{#if formError}<p class="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-sm text-rose-700" role="alert">{formError}</p>{/if}<label class="mt-4 block"><span class="text-sm font-medium text-slate-700">เหตุผล</span><textarea class="app-input mt-2 min-h-24 resize-y" bind:value={revokeInviteReason} maxlength="500" placeholder="ระบุเหตุผลเพื่อบันทึกใน audit log"></textarea></label><div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" class="app-button-secondary" disabled={invitationMutationId === revokeInviteTarget.invitationId} on:click={() => (revokeInviteTarget = null)}>ยกเลิก</button><button type="button" class="min-h-11 rounded-full border border-rose-700 bg-rose-700 px-4 text-sm font-semibold text-white hover:bg-rose-800 disabled:opacity-60" disabled={invitationMutationId === revokeInviteTarget.invitationId || !revokeInviteReason.trim()} on:click={revokeInvitation}>{invitationMutationId === revokeInviteTarget.invitationId ? 'กำลังเพิกถอน...' : 'ยืนยันเพิกถอน'}</button></div></section>
  </div>
{/if}

{#if reissueInviteTarget}
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4" role="alertdialog" aria-modal="true" aria-labelledby="reissue-invite-title">
    <button type="button" class="absolute inset-0 h-full w-full bg-slate-950/55 backdrop-blur-sm" aria-label="ยกเลิก" on:click={() => (reissueInviteTarget = null)}></button>
    <section class="relative w-full max-w-md rounded-[1.5rem] bg-white p-5 shadow-2xl sm:p-6"><span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-sky-50 text-sky-700"><Link2 size={22} /></span><h2 id="reissue-invite-title" class="mt-4 text-xl font-semibold text-slate-950">ออก Invite Link ใหม่?</h2><p class="mt-2 text-sm leading-6 text-slate-600">ระบบจะสร้าง token ใหม่ให้ <strong>{reissueInviteTarget.displayName || reissueInviteTarget.permission}</strong> และทำให้ลิงก์เดิมใช้ไม่ได้ทันที</p>{#if formError}<p class="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-sm text-rose-700" role="alert">{formError}</p>{/if}<label class="mt-4 block"><span class="text-sm font-medium text-slate-700">อายุลิงก์ใหม่</span><select class="app-input mt-2" bind:value={reissueInviteExpiresInDays}><option value={1}>1 วัน</option><option value={3}>3 วัน</option><option value={7}>7 วัน</option><option value={14}>14 วัน</option><option value={30}>30 วัน</option></select></label><div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" class="app-button-secondary" disabled={invitationMutationId === reissueInviteTarget.invitationId} on:click={() => (reissueInviteTarget = null)}>ยกเลิก</button><button type="button" class="app-button-primary disabled:opacity-60" disabled={invitationMutationId === reissueInviteTarget.invitationId} on:click={reissueInvitation}>{invitationMutationId === reissueInviteTarget.invitationId ? 'กำลังออกลิงก์...' : 'ยืนยันออกลิงก์ใหม่'}</button></div></section>
  </div>
{/if}
