param([switch]$ResetForSourceControl)
$ErrorActionPreference = 'Stop'
$modelPath = Join-Path $PSScriptRoot 'Retail.SemanticModel\model.bim'
$model = Get-Content -LiteralPath $modelPath -Raw | ConvertFrom-Json
$dataFolder = if ($ResetForSourceControl) { '__SET_DATA_ROOT__' } else { (Join-Path $PSScriptRoot 'data').Replace('\','/') }
$parameter = $model.model.expressions | Where-Object name -EQ 'DataRoot'
$parameter.expression = '"' + $dataFolder + '" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]'
$model | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $modelPath -Encoding utf8
Write-Host "DataRoot: $dataFolder"
