param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRef,

    [Parameter(Mandatory = $true)]
    [string]$Email,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [string]$DisplayName = 'Super Admin'
)

$ErrorActionPreference = 'Stop'

$apiKeysRaw = & npx.cmd supabase projects api-keys `
    --project-ref $ProjectRef `
    --output json

if ($LASTEXITCODE -ne 0) {
    throw 'Could not retrieve Supabase API keys'
}

$apiKeys = $apiKeysRaw | ConvertFrom-Json
$serviceRoleKey = ($apiKeys |
    Where-Object { $_.name -eq 'service_role' } |
    Select-Object -First 1).api_key

if ([string]::IsNullOrWhiteSpace($serviceRoleKey)) {
    throw 'Supabase service_role key was not found'
}

$apiBaseUrl = "https://$ProjectRef.supabase.co"
$commonHeaders = @(
    '-H', "apikey: $serviceRoleKey",
    '-H', "Authorization: Bearer $serviceRoleKey",
    '-H', 'Content-Type: application/json',
    '-H', 'User-Agent: CSMS-Production-Bootstrap/1.0'
)
$httpHeaders = @{
    apikey = $serviceRoleKey
    Authorization = "Bearer $serviceRoleKey"
    'User-Agent' = 'CSMS-Production-Bootstrap/1.0'
}

$authUsersRaw = & curl.exe -sS --fail-with-body `
    "$apiBaseUrl/auth/v1/admin/users?page=1&per_page=1000" `
    @commonHeaders

if ($LASTEXITCODE -ne 0) {
    throw 'Could not list Supabase Auth users'
}

$authUsersResponse = $authUsersRaw | ConvertFrom-Json
$normalizedEmail = $Email.Trim().ToLowerInvariant()
$authUser = $authUsersResponse.users |
    Where-Object { $_.email -eq $normalizedEmail } |
    Select-Object -First 1

if ($null -eq $authUser) {
    $createPayload = @{
        email = $normalizedEmail
        password = $Password
        email_confirm = $true
        user_metadata = @{ display_name = $DisplayName }
    } | ConvertTo-Json -Compress

    try {
        $authUser = Invoke-RestMethod `
            -Uri "$apiBaseUrl/auth/v1/admin/users" `
            -Method Post `
            -Headers $httpHeaders `
            -ContentType 'application/json' `
            -Body $createPayload
    } catch {
        $safeErrorMessage = 'Supabase Auth rejected the user creation request'
        try {
            $errorReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $authError = $errorReader.ReadToEnd() | ConvertFrom-Json
            if (-not [string]::IsNullOrWhiteSpace($authError.message)) {
                $safeErrorMessage = $authError.message
            } elseif (-not [string]::IsNullOrWhiteSpace($authError.msg)) {
                $safeErrorMessage = $authError.msg
            }
        } catch {
            # Keep the generic message; never echo the original request payload.
        }
        throw "Could not create the Supabase Auth user: $safeErrorMessage"
    }
    Write-Output 'Created Supabase Auth user'
} else {
    Write-Output 'Supabase Auth user already exists'
}

$profilePayload = @{
    auth_user_id = $authUser.id
    line_user_id = "email:$normalizedEmail"
    display_name = $DisplayName
    email = $normalizedEmail
    global_role = 'system_admin'
    is_active = $true
} | ConvertTo-Json -Compress

try {
    $profileHeaders = $httpHeaders.Clone()
    $profileHeaders['Prefer'] = 'resolution=merge-duplicates,return=minimal'
    Invoke-RestMethod `
        -Uri "$apiBaseUrl/rest/v1/users?on_conflict=auth_user_id" `
        -Method Post `
        -Headers $profileHeaders `
        -ContentType 'application/json' `
        -Body $profilePayload | Out-Null
} catch {
    throw 'Could not create or update the system admin profile'
}

Write-Output "System admin is ready: $normalizedEmail"
