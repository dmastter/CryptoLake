@echo off
setlocal

cd /d "%~dp0"

echo [1/4] Resolviendo comando Docker...
set "DOCKER_CMD=docker"
%DOCKER_CMD% --version >nul 2>&1
if errorlevel 1 (
  if exist "C:\Progra~1\Docker\Docker\resources\bin\docker.exe" (
    set "DOCKER_CMD=C:\Progra~1\Docker\Docker\resources\bin\docker.exe"
  ) else (
    echo ERROR: No se encontro Docker CLI en PATH ni en la ruta por defecto.
    exit /b 1
  )
)
for %%I in ("%DOCKER_CMD%") do set "DOCKER_DIR=%%~dpI"
set "PATH=%DOCKER_DIR%;%PATH%"

set "MINIO_ROOT_USER=minioadmin"
set "MINIO_ROOT_PASSWORD=minioadmin"
set "AIRFLOW_ADMIN_PASSWORD="
set "MINIO_LAKEADMIN_PASSWORD="
if exist ".env" (
  for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    if /I "%%A"=="MINIO_ROOT_USER" set "MINIO_ROOT_USER=%%B"
    if /I "%%A"=="MINIO_ROOT_PASSWORD" set "MINIO_ROOT_PASSWORD=%%B"
    if /I "%%A"=="AIRFLOW_ADMIN_PASSWORD" set "AIRFLOW_ADMIN_PASSWORD=%%B"
    if /I "%%A"=="MINIO_LAKEADMIN_PASSWORD" set "MINIO_LAKEADMIN_PASSWORD=%%B"
  )
)
if not defined AIRFLOW_ADMIN_PASSWORD (
  echo ERROR: Falta AIRFLOW_ADMIN_PASSWORD en .env
  exit /b 1
)
if not defined MINIO_LAKEADMIN_PASSWORD (
  echo ERROR: Falta MINIO_LAKEADMIN_PASSWORD en .env
  exit /b 1
)

echo [2/4] Levantando servicios...
"%DOCKER_CMD%" compose up -d
if errorlevel 1 (
  echo ERROR: Fallo al levantar docker compose.
  exit /b 1
)

echo [3/4] Inicializando Airflow (db + usuario)...
"%DOCKER_CMD%" exec airflow-webserver airflow db migrate >nul 2>&1
"%DOCKER_CMD%" exec airflow-webserver airflow users create --username diego_admin --firstname Diego --lastname Admin --role Admin --email diego_admin@local.dev --password %AIRFLOW_ADMIN_PASSWORD% >nul 2>&1

echo [4/4] Inicializando usuario MinIO...
"%DOCKER_CMD%" run --rm --network cryptolake_default -e MC_HOST_local=http://%MINIO_ROOT_USER%:%MINIO_ROOT_PASSWORD%@minio:9000 minio/mc admin user add local lakeadmin %MINIO_LAKEADMIN_PASSWORD% >nul 2>&1
"%DOCKER_CMD%" run --rm --network cryptolake_default -e MC_HOST_local=http://%MINIO_ROOT_USER%:%MINIO_ROOT_PASSWORD%@minio:9000 minio/mc admin policy attach local readwrite --user lakeadmin >nul 2>&1
"%DOCKER_CMD%" run --rm --network cryptolake_default -e MC_HOST_local=http://%MINIO_ROOT_USER%:%MINIO_ROOT_PASSWORD%@minio:9000 minio/mc admin policy attach local consoleAdmin --user lakeadmin >nul 2>&1

echo.
echo Proyecto listo.
echo Airflow: http://localhost:8083  (diego_admin, contrasena en .env)
echo MinIO:   http://localhost:9001  (lakeadmin, contrasena en .env)

exit /b 0
