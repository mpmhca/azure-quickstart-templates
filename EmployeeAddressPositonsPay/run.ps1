# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}
#########################################################################
#region	Script Logging Setup#
# if (!!$PSScriptRoot) { set-location $PSScriptRoot }
# $psscriptname = $MyInvocation.MyCommand.name
# if (!!$psscriptname) {
#     $transcript = "./$psscriptname.logs/$psscriptname." + (get-date -Format MM.dd.yy.hh.mm.tt) + ".log"
#     Start-Transcript $transcript -Force -IncludeInvocationHeader
# }
# if (!$psscriptname) {
#     $psscriptname = "ManualRun"
#     $transcript = "./$psscriptname.logs/$psscriptname." + (get-date -Format MM.dd.yy.hh.mm.tt) + ".log"
#     Start-Transcript $transcript -Force -IncludeInvocationHeader
# }
#endregion Script Logging Setup#

#region ion Token retrieval#
#$ion = Get-Content '.\bin\Compass.ionapi' | ConvertFrom-Json
$uri = $env:pu + $env:ot
$body = @{grant_type = 'password'; username = $env:saak; password = $env:sask; client_id = $env:ci; client_secret = $env:cs; scope = ''; redirect_uri = 'https://localhost/' }
$token = (invoke-restmethod -method post -uri $uri -body $body).access_token
$headers = @{authorization = "bearer " + $token }
#$ion | add-member -name "headers" -value $headers -membertype noteproperty -force
#endregion#

#DataLake Call 1. - Post initial query to "HCM_Employee" and retrieves {QueryID}#
$object = @(
    "e.Employee" 
    "e.NameFamilyName" 
    "e.NameGivenName" 
    "e.NamePreferredGivenName" 
    "e.RelationshipToOrganization" 
    "ea.Municipality" 
    "ea.StateProvince" 
    "ea.PostalCode" 
    "e.StartDate" 
    "e.AdjustedStartDate" 
    "wa.hrorganizationunit" 
    "wa.annualrate" 
    "wa.glcompany" 
    "wa.directsupervisor" 
    "wa.costcenter" 
    "wa.combinedpayrate" 
    "wa.job" 
    "wa.payrate" 
    "wa.payratetype" 
    "wa.payfrequency" 
    "wa.position" 
    "pos.salarystructure" 
    "wa.shift" 
    "wa.workassignment" 
    "wa.workschedule" 
    "pos.PositionFamily" 
    "pos.PositionCategory" 
    "pos.PositionCategoryDescription" 
    "pos.PositionLevel" 
    "pos.PositionLevelDescription" 
    "sup.SupervisorEmployeeName" 
    "sup.SupervisorType"
  )
$object = $object -join ","
$fromDB = "HCM_Employee e INNER JOIN HCM_EmployeeAddress AS ea ON e.Employee = ea.Employee INNER JOIN HCM_WorkAssignment AS wa ON e.employee = wa.Employee INNER JOIN HCM_Position AS pos ON wa.position = pos.position INNER JOIN HCM_Supervisor as sup ON pos.directsupervisor = sup.Supervisor" 
$whereDB = "e.RelationshipToOrganization = 'EMPLOYEE' AND e.RelationshipStatus = 'ACTIVE'"
$param = @{
    Uri     = "https://mingle-ionapi.inforcloudsuite.com/HCAHEALTHCARE_PRD/IONSERVICES/datalakeapi/v1/compass/jobs?resultFormat=text%2Fcsv"
    Headers = @{
        "authorization" = "bearer " + $token
        "Content-Type"  = "text/plain"
        "accept"        = "application/json"
    }
    Method  = "Post"
    # Body        =  "SELECT $object FROM $fromDB AS e INNER JOIN `"HCM_EmployeeAddress`" AS ea ON `"e`".`"Employee`" = `"ea`".`"Employee`""
    Body    = "SELECT $object FROM $fromDB WHERE $whereDB"
}

$response1 = $null
write-output "Running SQL Query: $($param.body)"
$response1 = Invoke-RestMethod @param

#DataLake Call 2. - status - Queries until it receives a status of FINISHED#
$queryid = $response1.queryid
do {
    $response2 = $null
    $uri = "https://mingle-ionapi.inforcloudsuite.com/HCAHEALTHCARE_PRD/IONSERVICES/datalakeapi/v1/compass/jobs/$queryid/status"
    Invoke-RestMethod $uri -Headers $headers | Tee-Object -Variable response2
} until ($response2.status -eq "FINISHED" -or $response2.status -eq "FAILED")
write-output "SQL Query: $($response2.status)"

#DataLake Call 3. - results -Queries to provide count#
$response3 = $null
$param = @{
    Uri     = "https://mingle-ionapi.inforcloudsuite.com/HCAHEALTHCARE_PRD/IONSERVICES/datalakeapi/v1/compass/jobs/$queryid/result"
    Headers = @{
        "authorization"   = "bearer " + $token
        "accept"          = "*/*"
        "Accept-Encoding" = "identity"
    } 
}
$response3 = Invoke-RestMethod @param #-OutFile "$PWD\Output\EmployeeAddressCombined.csv"
#
# Send to storage account.
Push-OutputBinding -name combinedData -value $response3 

# remove-item "\\xrdcwpappxip01b\e$\dmon_sources\PRD\EmployeeAddressCombined.csv" -force
# copy-item "$PWD\Output\EmployeeAddressCombined.csv" \\xrdcwpappxip01b\e$\dmon_sources\PRD\EmployeeAddressCombined.csv -Force
# $Localtest = Test-path "$PWD\Output\EmployeeAddressCombined.csv"
# $remotetest = Test-Path "\\xrdcwpappxip01b\e$\dmon_sources\PRD\EmployeeAddressCombined.csv"
# $response3 = import-csv "$PWD\Output\EmployeeAddressCombined.csv"
# #$response3|Format-Table
# if (!!$remotetest) {
#     write-output "$($response3.count) items found::output has been written to \\xrdcwpappxip01b\e$\dmon_sources\PRD\EmployeeAddressCombined.csv successfully" 
# }
# else {
#     write-output "Error:output has not been written to \\xrdcwpappxip01b\e$\dmon_sources\PRD\EmployeeAddressCombined.csv successfully" 
# }
# if (!!$Localtest) {
#     write-output "$($response3.count) items found::output has been written to $PWD\Output\EmployeeAddressCombined.csv successfully" 
# }
# else {
#     write-output "Error:output has not been written to $PWD\Output\EmployeeAddressCombined.csv successfully" 
# }
# Stop-Transcript



# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

$timeSpan = New-TimeSpan -Start $currentUTCtime -End ((Get-Date).ToUniversalTime())
Write-Host "Time Taken is  $($timeSpan)"