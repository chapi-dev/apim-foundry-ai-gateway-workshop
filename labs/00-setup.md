# Lab 00 · Preparación del entorno

## Objetivo
Dejar tu equipo listo para el workshop.

## Pasos

1. **Iniciar sesión en Azure y seleccionar la suscripción**
   ```powershell
   az login
   az account set --subscription "<tu-subscription>"
   az account show -o table
   ```

2. **Comprobar herramientas**
   ```powershell
   az bicep version      # extensión Bicep
   gh auth status        # GitHub CLI
   docker --version      # para el puente de Claude Code
   python --version      # 3.10+
   ```

3. **Registrar proveedores (si es la primera vez)**
   ```powershell
   az provider register --namespace Microsoft.ApiManagement
   az provider register --namespace Microsoft.CognitiveServices
   az provider register --namespace Microsoft.Cache
   ```

4. **Región**: el workshop usa `swedencentral` por defecto (modelos y APIM disponibles).
   Cámbiala en `infra/main.bicepparam` si lo necesitas.

## Siguiente
➡️ [Lab 01 · Desplegar y primera llamada](01-desplegar-y-primera-llamada.md)
