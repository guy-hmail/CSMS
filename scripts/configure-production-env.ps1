param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRef,

    [Parameter(Mandatory = $true)]
    [string]$VercelScope
)

$ErrorActionPreference = 'Stop'

function Get-DotEnvValues([string]$Path) {
    $values = @{}
    Get-Content -LiteralPath $Path |
        Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=' } |
        ForEach-Object {
            $pair = $_ -split '=', 2
            $values[$pair[0]] = $pair[1]
        }
    return $values
}

function Add-VercelEnvironmentVariable(
    [string]$Name,
    [string]$Target,
    [string]$Value
) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing value for $Name"
    }

    & npx.cmd vercel env add $Name $Target `
        --value $Value `
        --force `
        --yes `
        --no-sensitive `
        --scope $VercelScope | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure $Name for $Target"
    }

    Write-Output "Configured $Name for $Target"
}

$apiKeysRaw = & npx.cmd supabase projects api-keys `
    --project-ref $ProjectRef `
    --output json

if ($LASTEXITCODE -ne 0) {
    throw 'Could not retrieve Supabase API keys'
}

$apiKeys = $apiKeysRaw | ConvertFrom-Json
$publishableKey = ($apiKeys |
    Where-Object { $_.type -eq 'publishable' } |
    Select-Object -First 1).api_key
$localEnvironment = Get-DotEnvValues '.env'
$supabaseUrl = "https://$ProjectRef.supabase.co"

Add-VercelEnvironmentVariable 'PUBLIC_SUPABASE_URL' 'production,preview' $supabaseUrl
Add-VercelEnvironmentVariable 'PUBLIC_SUPABASE_ANON_KEY' 'production,preview' $publishableKey
Add-VercelEnvironmentVariable 'PUBLIC_LINE_LIFF_ID' 'production,preview' $localEnvironment['PUBLIC_LINE_LIFF_ID']
Add-VercelEnvironmentVariable 'PUBLIC_APP_ENV' 'production' 'production'
Add-VercelEnvironmentVariable 'PUBLIC_APP_ENV' 'preview' 'preview'
