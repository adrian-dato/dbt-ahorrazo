# Imagen propia para correr dbt_ahorrazo, desacoplada del Python de
# Airflow (3.10) -- reemplaza el venv compartido por volumen (armado en
# python:3.12-slim, montado dentro de contenedores de otra imagen) que
# rompía de formas distintas cada vez que algo del entorno cambiaba
# (shebang con ruta absoluta grabada, symlink del intérprete resolviendo
# a un Python de otra imagen, librería compartida faltante). Con esto,
# el Python que arma la imagen y el que la corre son siempre el mismo
# binario -- no hay límite de imagen que cruzar.
#
# Se corre vía Docker (contenedor propio por tarea desde Airflow, ver
# _dbt_runner.py), NUNCA copiando el proyecto adentro -- el proyecto
# (models/, profiles.yml, .env) se monta en runtime desde el host. Esta
# imagen es solo el runtime (Python 3.12 + dbt-core + dbt-sqlserver +
# driver ODBC) -- se reconstruye solo cuando cambia requirements.txt, no
# cuando cambia un .sql.
FROM python:3.12-slim-bookworm

# Driver ODBC 17 de Microsoft para SQL Server (coincide con profiles.yml,
# que pide 'ODBC Driver 17 for SQL Server' explícito) + headers de
# unixODBC que pyodbc necesita para compilar su extensión en C. Pasos
# oficiales de Microsoft para Debian 12 (bookworm, la base real de
# python:3.12-slim-bookworm) -- ver
# learn.microsoft.com/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl gnupg2 \
    && curl -sSL -O https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql17 unixodbc-dev \
    && apt-get purge -y --auto-remove curl gnupg2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/app/dbt_ahorrazo

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Sin COPY del proyecto -- se monta en runtime (ver _dbt_runner.py).
ENTRYPOINT ["dbt"]
