param(
   [string]$TerminalId = "9BB124B7D418C7FB69DF2865535BA9BF",
   [string]$TerminalExe = "C:\Program Files\VT Markets (Pty) MT5 Terminal\terminal64.exe",
   [string]$MetaEditorExe = "C:\Program Files\VT Markets (Pty) MT5 Terminal\metaeditor64.exe",
   [string]$Symbol = "XAUUSD-STD",
   [string]$Period = "M5",
   [int]$Deposit = 10000,
   [int]$TimeoutMinutes = 10,
   [switch]$SkipCompile
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TerminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\$TerminalId"
$ExpertDir = Join-Path $TerminalData "MQL5\Experts\GoldSignalEA"
$CommonFiles = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
$TradesCsv = Join-Path $CommonFiles "GoldSignalEA_Trades.csv"
$PresetPath = Join-Path $RepoRoot "GoldSignalEA_H4ZoneRetest.set"
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputDir = Join-Path $PSScriptRoot "backtest-results\$RunStamp"

$Segments = @(
   @{ Name = "janfeb"; From = "2026.01.27"; To = "2026.02.28" },
   @{ Name = "march";  From = "2026.03.01"; To = "2026.03.31" },
   @{ Name = "april";  From = "2026.04.01"; To = "2026.04.29" },
   @{ Name = "recent"; From = "2026.04.27"; To = "2026.05.05" }
)

function Copy-EaFiles {
   New-Item -ItemType Directory -Force -Path $ExpertDir | Out-Null

   $files = @(
      (Join-Path $RepoRoot "GoldSignalEA.mq5"),
      (Join-Path $RepoRoot "GoldSignalEngine.mqh"),
      (Join-Path $RepoRoot "RiskManager.mqh"),
      (Join-Path $RepoRoot "TradeManager.mqh")
   )

   Copy-Item -LiteralPath $files -Destination $ExpertDir -Force
}

function Compile-Ea {
   $source = Join-Path $ExpertDir "GoldSignalEA.mq5"
   $log = Join-Path $OutputDir "compile.log"

   & $MetaEditorExe /compile:"$source" /log:"$log"
   Start-Sleep -Seconds 4

   $tail = Get-Content -Tail 20 $log
   $result = $tail | Select-String -Pattern "Result:\s+0 errors,\s+0 warnings"

   if(-not $result) {
      $tail | Write-Host
      throw "Compilation failed. See $log"
   }
}

function Stop-IsolatedTerminal {
   Get-Process terminal64,metatester64 -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -like "C:\Program Files\VT Markets (Pty) MT5 Terminal\*" } |
      Stop-Process -Force
}

function New-TesterIni {
   param(
      [hashtable]$Segment,
      [string]$Path,
      [string]$ReportPath
   )

   $inputLines = Get-Content $PresetPath |
      Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith(";") }

   $header = @"
[Tester]
Expert=GoldSignalEA\GoldSignalEA.ex5
Symbol=$Symbol
Period=$Period
Optimization=0
Model=4
FromDate=$($Segment.From)
ToDate=$($Segment.To)
ForwardMode=0
Deposit=$Deposit
Currency=USD
ProfitInPips=0
Leverage=100
ExecutionMode=1
OptimizationCriterion=0
Visual=0
Report=$ReportPath
ReplaceReport=1

[TesterInputs]
"@

   ($header + ($inputLines -join [Environment]::NewLine)) |
      Set-Content -LiteralPath $Path -Encoding ASCII
}

function Read-TradeSummary {
   param([string]$SegmentName)

   if(-not (Test-Path $TradesCsv)) {
      return [pscustomobject]@{
         Segment = $SegmentName
         Trades = 0
         Wins = 0
         Losses = 0
         BE = 0
         WinRate = 0
         NetProfit = 0
      }
   }

   $rows = @(Import-Csv -Delimiter ";" $TradesCsv)
   $wins = @($rows | Where-Object Result -eq "WIN").Count
   $losses = @($rows | Where-Object Result -eq "LOSS").Count
   $be = @($rows | Where-Object Result -eq "BE").Count
   $net = if($rows.Count) { ($rows | Measure-Object -Property Profit -Sum).Sum } else { 0 }

   [pscustomobject]@{
      Segment = $SegmentName
      Trades = $rows.Count
      Wins = $wins
      Losses = $losses
      BE = $be
      WinRate = if($rows.Count) { [math]::Round(($wins / $rows.Count) * 100, 2) } else { 0 }
      NetProfit = [math]::Round($net, 2)
   }
}

function Run-Backtest {
   param([hashtable]$Segment)

   $ini = Join-Path $OutputDir "$($Segment.Name).ini"
   $report = Join-Path $OutputDir "$($Segment.Name)-report"
   $testerLog = Join-Path $TerminalData ("Tester\logs\" + (Get-Date -Format "yyyyMMdd") + ".log")
   $beforeLines = if(Test-Path $testerLog) { (Get-Content $testerLog).Count } else { 0 }

   New-TesterIni -Segment $Segment -Path $ini -ReportPath $report

   $process = Start-Process -FilePath $TerminalExe -ArgumentList "/config:`"$ini`"" -WindowStyle Hidden -PassThru
   $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
   $finalLine = $null

   do {
      Start-Sleep -Seconds 5

      if(Test-Path $testerLog) {
         $newLines = Get-Content $testerLog | Select-Object -Skip $beforeLines
         $finalLine = ($newLines | Select-String -Pattern "final balance" | Select-Object -Last 1).Line

         if($finalLine) {
            break
         }
      }
   } while((Get-Date) -lt $deadline)

   Stop-IsolatedTerminal

   if(-not $finalLine) {
      throw "Backtest '$($Segment.Name)' timed out after $TimeoutMinutes minutes."
   }

   $copyPath = Join-Path $OutputDir "$($Segment.Name)-trades.csv"
   if(Test-Path $TradesCsv) {
      Copy-Item -LiteralPath $TradesCsv -Destination $copyPath -Force
   }

   $summary = Read-TradeSummary -SegmentName $Segment.Name
   $summary | Add-Member -NotePropertyName From -NotePropertyValue $Segment.From
   $summary | Add-Member -NotePropertyName To -NotePropertyValue $Segment.To
   $summary | Add-Member -NotePropertyName FinalBalanceLine -NotePropertyValue $finalLine

   $summary
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Copy-EaFiles

if(-not $SkipCompile) {
   Compile-Ea
}

$results = foreach($segment in $Segments) {
   Write-Host "Running $($segment.Name): $($segment.From) -> $($segment.To)"
   Run-Backtest -Segment $segment
}

$summaryPath = Join-Path $OutputDir "summary.csv"
$results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $summaryPath
$results | Format-Table -AutoSize

Write-Host "Summary written to $summaryPath"
