# Elimina el grupo de recursos del workshop.
param(
    [string]$ResourceGroup = "rg-apim-workshop"
)
Write-Host "Se eliminará el grupo '$ResourceGroup' y TODOS sus recursos." -ForegroundColor Red
$confirm = Read-Host "Escribe el nombre del grupo para confirmar"
if ($confirm -eq $ResourceGroup) {
    az group delete -n $ResourceGroup --yes --no-wait
    Write-Host "Eliminación iniciada (en segundo plano)."
} else {
    Write-Host "Cancelado."
}
