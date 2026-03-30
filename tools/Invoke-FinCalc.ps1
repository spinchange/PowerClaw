<#
.SYNOPSIS
    Time Value of Money and compound returns financial calculator.

.DESCRIPTION
    Performs core TVM calculations (PV, FV, PMT, NPER, RATE) and CAGR.
    All rates are entered as percentages (e.g. 7 for 7%) and converted internally.
    Supports compounding frequency adjustment for all TVM functions.

.CLAW_NAME
    Invoke-FinCalc

.CLAW_RISK
    Low

.CLAW_DESCRIPTION
    Financial calculator: TVM (PV, FV, PMT, NPER, RATE) and CAGR. Rates as percentages. No external calls.

.CLAW_PARAMETERS
    Function  : string : Required : One of PV, FV, PMT, NPER, RATE, CAGR
    Rate      : number : Optional : Annual interest rate as percentage (e.g. 7 for 7%)
    Nper      : number : Optional : Total number of years
    Pmt       : number : Optional : Payment per period (negative = outflow)
    PV        : number : Optional : Present value (negative = outflow)
    FV        : number : Optional : Future value
    Frequency : number : Optional : Compounding periods per year (default 1; 12=monthly, 4=quarterly, 365=daily)
    BeginningValue : number : Optional : Starting value for CAGR
    EndingValue    : number : Optional : Ending value for CAGR
    Years          : number : Optional : Number of years for CAGR

.CLAW_EXAMPLE
    Invoke-FinCalc -Function FV -Rate 7 -Nper 30 -Pmt -500 -PV 0 -Frequency 12
    Invoke-FinCalc -Function PMT -Rate 6.5 -Nper 30 -PV -250000 -FV 0 -Frequency 12
    Invoke-FinCalc -Function CAGR -BeginningValue 10000 -EndingValue 25000 -Years 8

.CLAW_CAPABILITIES
    None
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('PV','FV','PMT','NPER','RATE','CAGR')]
    [string]$Function,

    [double]$Rate,
    [double]$Nper,
    [double]$Pmt = 0,
    [double]$PV = 0,
    [double]$FV = 0,
    [int]$Frequency = 1,

    [double]$BeginningValue,
    [double]$EndingValue,
    [double]$Years
)

# --- Helpers ---

function Format-Currency {
    param([double]$Value)
    if ($Value -lt 0) {
        "-`${0:N2}" -f [Math]::Abs($Value)
    } else {
        "`${0:N2}" -f $Value
    }
}

function Format-Pct {
    param([double]$Value)
    "{0:N4}%" -f $Value
}

# --- TVM Engine ---
# Convention: negative = cash outflow, positive = cash inflow
# Periodic rate = annual rate / frequency
# Periodic nper = years * frequency

function Calc-FV {
    param([double]$r, [double]$n, [double]$pmt, [double]$pv)
    if ($r -eq 0) {
        return -($pv + $pmt * $n)
    }
    $fv = -($pv * [Math]::Pow(1 + $r, $n) + $pmt * (([Math]::Pow(1 + $r, $n) - 1) / $r))
    return $fv
}

function Calc-PV {
    param([double]$r, [double]$n, [double]$pmt, [double]$fv)
    if ($r -eq 0) {
        return -($fv + $pmt * $n)
    }
    $pv = -($fv / [Math]::Pow(1 + $r, $n) + $pmt * ((1 - [Math]::Pow(1 + $r, -$n)) / $r))
    return $pv
}

function Calc-PMT {
    param([double]$r, [double]$n, [double]$pv, [double]$fv)
    if ($r -eq 0) {
        return -($pv + $fv) / $n
    }
    $pmt = -($pv * $r * [Math]::Pow(1 + $r, $n) + $fv * $r) / ([Math]::Pow(1 + $r, $n) - 1)
    return $pmt
}

function Calc-NPER {
    param([double]$r, [double]$pmt, [double]$pv, [double]$fv)
    if ($r -eq 0) {
        return -($pv + $fv) / $pmt
    }
    $num = [Math]::Log(($pmt - $fv * $r) / ($pmt + $pv * $r))
    $den = [Math]::Log(1 + $r)
    return $num / $den
}

function Calc-RATE {
    # Newton-Raphson iterative solve for rate
    param([double]$n, [double]$pmt, [double]$pv, [double]$fv, [int]$maxIter = 100, [double]$tol = 1e-10)

    $guess = 0.1
    for ($i = 0; $i -lt $maxIter; $i++) {
        $r = $guess
        if ($r -eq 0) { $r = 1e-10 }

        $rn = [Math]::Pow(1 + $r, $n)
        $f  = $pv * $rn + $pmt * (($rn - 1) / $r) + $fv
        # derivative
        $drn = $n * [Math]::Pow(1 + $r, $n - 1)
        $fp  = $pv * $drn + $pmt * (($drn * $r - ($rn - 1)) / ($r * $r))

        if ([Math]::Abs($fp) -lt $tol) { break }

        $next = $r - $f / $fp
        if ([Math]::Abs($next - $r) -lt $tol) {
            $guess = $next
            break
        }
        $guess = $next
    }
    return $guess
}

# --- Main ---

$result = [ordered]@{
    Function  = $Function
    Status    = "OK"
}

switch ($Function) {
    'FV' {
        $periodicRate = ($Rate / 100) / $Frequency
        $totalPeriods = $Nper * $Frequency
        $val = Calc-FV -r $periodicRate -n $totalPeriods -pmt $Pmt -pv $PV
        $result['FutureValue']  = Format-Currency $val
        $result['RawValue']     = [Math]::Round($val, 2)
        $result['Inputs']       = [ordered]@{
            AnnualRate   = Format-Pct $Rate
            Years        = $Nper
            Frequency    = $Frequency
            TotalPeriods = $totalPeriods
            Payment      = Format-Currency $Pmt
            PresentValue = Format-Currency $PV
        }
    }
    'PV' {
        $periodicRate = ($Rate / 100) / $Frequency
        $totalPeriods = $Nper * $Frequency
        $val = Calc-PV -r $periodicRate -n $totalPeriods -pmt $Pmt -fv $FV
        $result['PresentValue'] = Format-Currency $val
        $result['RawValue']     = [Math]::Round($val, 2)
        $result['Inputs']       = [ordered]@{
            AnnualRate   = Format-Pct $Rate
            Years        = $Nper
            Frequency    = $Frequency
            TotalPeriods = $totalPeriods
            Payment      = Format-Currency $Pmt
            FutureValue  = Format-Currency $FV
        }
    }
    'PMT' {
        $periodicRate = ($Rate / 100) / $Frequency
        $totalPeriods = $Nper * $Frequency
        $val = Calc-PMT -r $periodicRate -n $totalPeriods -pv $PV -fv $FV
        $result['Payment']       = Format-Currency $val
        $result['PerPeriod']     = if ($Frequency -eq 12) { "Monthly" } elseif ($Frequency -eq 4) { "Quarterly" } elseif ($Frequency -eq 1) { "Annual" } else { "Every $(365/$Frequency) days approx" }
        $result['RawValue']      = [Math]::Round($val, 2)
        $result['TotalPaid']     = Format-Currency ($val * $totalPeriods)
        $result['TotalInterest'] = Format-Currency (($val * $totalPeriods) + $PV + $FV)
        $result['Inputs']        = [ordered]@{
            AnnualRate   = Format-Pct $Rate
            Years        = $Nper
            Frequency    = $Frequency
            TotalPeriods = $totalPeriods
            PresentValue = Format-Currency $PV
            FutureValue  = Format-Currency $FV
        }
    }
    'NPER' {
        $periodicRate = ($Rate / 100) / $Frequency
        $totalPeriods = Calc-NPER -r $periodicRate -pmt $Pmt -pv $PV -fv $FV
        $years = [Math]::Round($totalPeriods / $Frequency, 2)
        $result['TotalPeriods'] = [Math]::Round($totalPeriods, 2)
        $result['Years']        = $years
        $result['Inputs']       = [ordered]@{
            AnnualRate   = Format-Pct $Rate
            Frequency    = $Frequency
            Payment      = Format-Currency $Pmt
            PresentValue = Format-Currency $PV
            FutureValue  = Format-Currency $FV
        }
    }
    'RATE' {
        $totalPeriods = $Nper * $Frequency
        $periodicRate = Calc-RATE -n $totalPeriods -pmt $Pmt -pv $PV -fv $FV
        $annualRate   = $periodicRate * $Frequency * 100
        $result['AnnualRate']   = Format-Pct $annualRate
        $result['PeriodicRate'] = Format-Pct ($periodicRate * 100)
        $result['RawAnnualPct'] = [Math]::Round($annualRate, 6)
        $result['Inputs']       = [ordered]@{
            Years        = $Nper
            Frequency    = $Frequency
            TotalPeriods = $totalPeriods
            Payment      = Format-Currency $Pmt
            PresentValue = Format-Currency $PV
            FutureValue  = Format-Currency $FV
        }
    }
    'CAGR' {
        if ($BeginningValue -le 0) {
            $result['Status'] = "ERROR"
            $result['Message'] = "BeginningValue must be greater than 0."
        } elseif ($Years -le 0) {
            $result['Status'] = "ERROR"
            $result['Message'] = "Years must be greater than 0."
        } else {
            $cagr = ([Math]::Pow($EndingValue / $BeginningValue, 1 / $Years) - 1) * 100
            $result['CAGR']          = Format-Pct $cagr
            $result['RawPct']        = [Math]::Round($cagr, 6)
            $result['TotalReturn']   = Format-Pct (($EndingValue / $BeginningValue - 1) * 100)
            $result['Inputs']        = [ordered]@{
                BeginningValue = Format-Currency $BeginningValue
                EndingValue    = Format-Currency $EndingValue
                Years          = $Years
            }
        }
    }
}

$result | ConvertTo-Json -Depth 3