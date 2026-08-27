# Limpieza de recursos del workshop.
#
# ⚠️ En modo REUTILIZACIÓN, las cuentas de Foundry de rg-apim-workshop son los BACKENDS del
#    gateway reutilizado (apim-aigw-dev-01). Borrar el RG completo las eliminaría y romperías
#    el gateway. Usa -Mode para elegir un borrado seguro.
param(
    [ValidateSet("RedundantApim", "RedundantApimAndMonitoring", "FullResourceGroup")]
    [string]$Mode = "RedundantApim",
    [string]$ResourceGroup = "rg-apim-workshop",
    [string]$RedundantApimName = "aigw-qyxvx-apim"
)

$ErrorActionPreference = "Stop"

switch ($Mode) {
    "RedundantApim" {
        Write-Host "Se eliminará SOLO el APIM Developer redundante '$RedundantApimName'." -ForegroundColor Yellow
        Write-Host "(Los Foundry se conservan: son backends del gateway reutilizado.)"
        if ((Read-Host "Escribe SI para confirmar") -eq "SI") {
            az resource delete -g $ResourceGroup -n $RedundantApimName --resource-type Microsoft.ApiManagement/service
            Write-Host "APIM redundante eliminado."
        } else { Write-Host "Cancelado." }
    }
    "RedundantApimAndMonitoring" {
        Write-Host "Se eliminará el APIM Developer + Log Analytics/App Insights redundantes." -ForegroundColor Yellow
        if ((Read-Host "Escribe SI para confirmar") -eq "SI") {
            az resource delete -g $ResourceGroup -n $RedundantApimName --resource-type Microsoft.ApiManagement/service
            az resource list -g $ResourceGroup --query "[?type=='microsoft.insights/components' || type=='Microsoft.OperationalInsights/workspaces'].name" -o tsv | ForEach-Object {
                az resource delete -g $ResourceGroup -n $_ --resource-type (az resource show -g $ResourceGroup -n $_ --query type -o tsv)
            }
            Write-Host "Recursos redundantes eliminados (Foundry conservados)."
        } else { Write-Host "Cancelado." }
    }
    "FullResourceGroup" {
        Write-Host "⚠️ Se eliminará el GRUPO COMPLETO '$ResourceGroup' INCLUIDOS los Foundry backends." -ForegroundColor Red
        if ((Read-Host "Escribe el nombre del grupo para confirmar") -eq $ResourceGroup) {
            az group delete -n $ResourceGroup --yes --no-wait
            Write-Host "Eliminación del grupo iniciada."
        } else { Write-Host "Cancelado." }
    }
}
