$csvPath = "c:\Users\Duong Phung\AndroidStudioProjects\AloT\Bang_Gia_SmartHome.csv"
$xlsxPath = "c:\Users\Duong Phung\AndroidStudioProjects\AloT\Bang_Gia_SmartHome.xlsx"

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $wb = $excel.Workbooks.Open($csvPath)
    # Save as xlOpenXMLWorkbook (51)
    $wb.SaveAs($xlsxPath, 51)
    $wb.Close()
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    Write-Host "Success"
} catch {
    Write-Host "Failed: $_"
}
