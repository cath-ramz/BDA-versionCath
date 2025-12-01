Proyecto Final de Bases de Datos Avanzada. Sistema de eCommerce para una joyeria.

# Instrucciones para replicar en tu maquina

## Linux

### Creacion de base de datos

```bash
mysql -u root -p < scripts/create_database.sql
mysql -u joyeria_user -p joyeria_db < scripts/create_stored_procedures.sql
mysql -u joyeria_user -p joyeria_db < scripts/create_tables.sql
mysql -u joyeria_user -p joyeria_db < scripts/create_views.sql
mysql -u joyeria_user -p joyeria_db < scripts/create_triggers.sql
mysql -u joyeria_user -p joyeria_db < scripts/insert_data.sql
mysql -u joyeria_user -p joyeria_db < scripts/create_temporary_tables.sql
```

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
bash run.sh
```
